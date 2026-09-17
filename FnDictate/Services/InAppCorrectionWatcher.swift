import AppKit
import ApplicationServices
import Foundation

/// After a dictation paste, watches the focused field via Accessibility and learns
/// short spelling fixes the user makes in-place (Wispr-style "correct once → remember").
///
/// Electron apps (Cursor, Slack, VS Code) recreate AX nodes while typing, so we key
/// off process ID + paste anchors rather than CFEqual on the focused element.
@MainActor
final class InAppCorrectionWatcher {
    struct Result: Sendable {
        let correctedPaste: String
        let historyEntryID: UUID?
    }

    /// How long to keep observing after paste.
    var watchDuration: TimeInterval = 45
    /// Poll interval while watching.
    var pollInterval: TimeInterval = 0.4

    private var task: Task<Void, Never>?

    func cancel() {
        task?.cancel()
        task = nil
    }

    /// Begins watching. Calls `onResult` at most once when a stable in-field edit is seen.
    func start(
        pasted: String,
        targetApp: NSRunningApplication?,
        historyEntryID: UUID?,
        onSettled: (@MainActor () -> Void)? = nil,
        onFailedToAttach: (@MainActor () -> Void)? = nil,
        onResult: @escaping @MainActor (Result) -> Void
    ) {
        cancel()
        let trimmed = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let expectedPID = targetApp?.processIdentifier
        task = Task { [weak self] in
            guard let self else { return }
            await self.watch(
                pasted: pasted,
                expectedPID: expectedPID,
                historyEntryID: historyEntryID,
                onSettled: onSettled,
                onFailedToAttach: onFailedToAttach,
                onResult: onResult
            )
        }
    }

    // MARK: - Watch loop

    private func watch(
        pasted: String,
        expectedPID: pid_t?,
        historyEntryID: UUID?,
        onSettled: (@MainActor () -> Void)?,
        onFailedToAttach: (@MainActor () -> Void)?,
        onResult: @escaping @MainActor (Result) -> Void
    ) async {
        guard let baseline = await settleBaseline(pasted: pasted, expectedPID: expectedPID) else {
            // Cursor/Electron often hide the chat field from Accessibility — fall back to
            // learning if the user copies the corrected text (⌘A ⌘C) within the window.
            onFailedToAttach?()
            await watchClipboardFallback(
                pasted: pasted,
                historyEntryID: historyEntryID,
                onResult: onResult
            )
            return
        }
        onSettled?()

        let deadline = Date().addingTimeInterval(watchDuration)
        var lastValue = baseline.snapshot.value
        var missCount = 0

        while Date() < deadline {
            if Task.isCancelled { return }
            try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
            if Task.isCancelled { return }

            // Prefer AX; also accept a clipboard copy of a near-match correction.
            if let clip = clipboardCorrection(vs: pasted) {
                onResult(Result(correctedPaste: clip, historyEntryID: historyEntryID))
                return
            }

            // Prefer fields that still look like our paste — never grab Cursor chrome
            // ("Plan, Build, / for skills…") just because it's focused/longer.
            guard let reading = FocusedTextReader.readFocused(preferringSimilarTo: pasted) else {
                missCount += 1
                if missCount >= 8 {
                    await watchClipboardFallback(
                        pasted: pasted,
                        historyEntryID: historyEntryID,
                        onResult: onResult
                    )
                    return
                }
                continue
            }
            missCount = 0

            let snapshot = reading.snapshot
            if snapshot.isSecure { return }
            if let expectedPID, snapshot.pid != expectedPID { return }

            let current = snapshot.value
            guard current != lastValue else { continue }
            lastValue = current

            guard let corrected = Self.correctedPaste(
                baseline: baseline.snapshot.value,
                current: current,
                pasteRange: baseline.pasteRange,
                pasted: pasted
            ) else { continue }

            let trimmedCorrected = corrected.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedCorrected.isEmpty else { continue }
            guard corrected != pasted else { continue }
            guard Self.isPlausibleCorrection(pasted: pasted, corrected: corrected) else { continue }

            // Wait for a brief pause so we learn the finished edit, not mid-keystroke.
            try? await Task.sleep(nanoseconds: 700_000_000)
            if Task.isCancelled { return }

            guard let stable = FocusedTextReader.readFocused(preferringSimilarTo: pasted),
                stable.snapshot.value == current
                    || Self.correctedPaste(
                        baseline: baseline.snapshot.value,
                        current: stable.snapshot.value,
                        pasteRange: baseline.pasteRange,
                        pasted: pasted
                    ) == corrected
            else { continue }

            // Re-check after settle — Electron UIs often swap AX values mid-poll.
            guard Self.isPlausibleCorrection(pasted: pasted, corrected: corrected) else { continue }

            onResult(
                Result(
                    correctedPaste: corrected,
                    historyEntryID: historyEntryID
                )
            )
            return
        }
    }

    /// When Accessibility can't see the field, learn from a copy of the edited paste.
    private func watchClipboardFallback(
        pasted: String,
        historyEntryID: UUID?,
        onResult: @escaping @MainActor (Result) -> Void
    ) async {
        let deadline = Date().addingTimeInterval(watchDuration)
        let baselineChangeCount = NSPasteboard.general.changeCount

        while Date() < deadline {
            if Task.isCancelled { return }
            try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
            if Task.isCancelled { return }

            let board = NSPasteboard.general
            guard board.changeCount != baselineChangeCount else { continue }
            guard let clip = clipboardCorrection(vs: pasted) else { continue }
            onResult(Result(correctedPaste: clip, historyEntryID: historyEntryID))
            return
        }
    }

    private func clipboardCorrection(vs pasted: String) -> String? {
        guard let clip = NSPasteboard.general.string(forType: .string) else { return nil }
        let trimmed = clip.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != pasted else { return nil }
        // Ignore huge clipboard dumps unrelated to this dictation.
        guard trimmed.count <= max(pasted.count * 3, pasted.count + 400) else { return nil }
        guard Self.isPlausibleCorrection(pasted: pasted, corrected: trimmed) else { return nil }
        return clip
    }

    private struct Baseline {
        let snapshot: FocusedTextReader.Snapshot
        let pasteRange: Range<String.Index>
    }

    /// Wait for paste to appear in an accessible text field.
    private func settleBaseline(pasted: String, expectedPID: pid_t?) async -> Baseline? {
        // Electron UIs often need longer after ⌘V before AXValue updates.
        for _ in 0..<20 {
            if Task.isCancelled { return nil }
            try? await Task.sleep(nanoseconds: 150_000_000)
            if Task.isCancelled { return nil }

            // Only accept a field that actually contains our paste — never a nearby
            // Cursor composer hint / mode row.
            guard let reading = FocusedTextReader.readFocused(containing: pasted) else {
                continue
            }

            let snapshot = reading.snapshot
            if snapshot.isSecure { return nil }
            if let expectedPID, snapshot.pid != expectedPID {
                continue
            }
            guard let range = Self.locatePaste(pasted, in: snapshot.value) else { continue }
            return Baseline(snapshot: snapshot, pasteRange: range)
        }
        return nil
    }

    // MARK: - Diff helpers

    /// Prefer the last exact occurrence (caret usually at end of insert).
    static func locatePaste(_ pasted: String, in haystack: String) -> Range<String.Index>? {
        if let range = haystack.range(of: pasted, options: .backwards) {
            return range
        }
        return locateCollapsedPaste(pasted, in: haystack)
    }

    /// Whitespace-insensitive locate that maps back to real haystack indices
    /// (unlike a naive collapsed-string character offset).
    private static func locateCollapsedPaste(_ pasted: String, in haystack: String) -> Range<String.Index>? {
        let pasteTokens = pasted
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        guard pasteTokens.count >= 1, pasteTokens.joined().count >= 2 else { return nil }

        let pattern = pasteTokens
            .map { NSRegularExpression.escapedPattern(for: $0) }
            .joined(separator: "\\s+")
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }

        let nsRange = NSRange(haystack.startIndex..<haystack.endIndex, in: haystack)
        let matches = regex.matches(in: haystack, options: [], range: nsRange)
        guard let last = matches.last, let range = Range(last.range, in: haystack) else { return nil }
        return range
    }

    /// Reconstruct the paste segment after an in-field edit using prefix/suffix anchors.
    static func correctedPaste(
        baseline: String,
        current: String,
        pasteRange: Range<String.Index>,
        pasted: String
    ) -> String? {
        let prefix = String(baseline[..<pasteRange.lowerBound])
        let suffix = String(baseline[pasteRange.upperBound...])

        if let sliced = slice(current, afterPrefix: prefix, beforeSuffix: suffix),
           isPlausibleCorrection(pasted: pasted, corrected: sliced)
        {
            return sliced
        }

        // Field was (effectively) just our paste — still require the new value to
        // look like an edit of that paste (Cursor AX often jumps to UI chrome).
        if baseline == pasted
            || collapseWhitespace(baseline) == collapseWhitespace(pasted)
        {
            if isPlausibleCorrection(pasted: pasted, corrected: current) {
                return current
            }
            return nil
        }

        // Electron sometimes replaces the whole value with only the edited paste
        // (losing surrounding chrome). Accept when still highly similar.
        if isPlausibleCorrection(pasted: pasted, corrected: current) {
            return current
        }

        return nil
    }

    /// True when `corrected` looks like an in-place edit of `pasted`, not a
    /// wholesale replacement with unrelated Cursor UI / chat chrome.
    static func isPlausibleCorrection(pasted: String, corrected: String) -> Bool {
        let a = collapseWhitespace(pasted)
        let b = collapseWhitespace(corrected)
        guard !a.isEmpty, !b.isEmpty, a != b else { return false }

        let ratio = Double(b.count) / Double(a.count)
        // Spelling/punctuation fixes stay near the original length.
        guard ratio >= 0.45, ratio <= 2.2 else { return false }

        if a.count >= 40 {
            let delta = abs(a.count - b.count)
            guard delta <= max(Int(Double(a.count) * 0.35), 24) else { return false }
        }

        let originalTokens = tokens(pasted)
        let retained = retainedTokenFraction(from: pasted, in: corrected)
        let overlap = tokenOverlap(pasted, corrected)

        // Few-token dictations: Jaccard is harsh for a single-word fix
        // ("jungle" → "jungles"). Prefer retained-token + length checks.
        if originalTokens.count <= 6 {
            guard retained >= 0.5 else { return false }
            // Still reject total rewrites that keep only a stopword-ish token.
            if originalTokens.count >= 3 {
                guard retained >= 0.6 || overlap >= 0.5 else { return false }
            }
            return true
        }

        let minOverlap: Double = a.count < 80 ? 0.62 : 0.55
        guard overlap >= minOverlap else { return false }
        guard retained >= 0.5 else { return false }

        return true
    }

    private static func slice(
        _ text: String,
        afterPrefix prefix: String,
        beforeSuffix suffix: String
    ) -> String? {
        if text.hasPrefix(prefix), text.hasSuffix(suffix) {
            let start = text.index(text.startIndex, offsetBy: prefix.count)
            let end = text.index(text.endIndex, offsetBy: -suffix.count)
            guard start <= end else { return nil }
            return String(text[start..<end])
        }
        return nil
    }

    /// Rough Jaccard overlap on whitespace tokens (case-insensitive).
    private static func tokenOverlap(_ a: String, _ b: String) -> Double {
        let left = Set(tokens(a))
        let right = Set(tokens(b))
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        let inter = left.intersection(right).count
        let union = left.union(right).count
        return Double(inter) / Double(union)
    }

    /// Fraction of original tokens that still appear in the candidate.
    private static func retainedTokenFraction(from original: String, in candidate: String) -> Double {
        let left = tokens(original)
        guard !left.isEmpty else { return 0 }
        let right = Set(tokens(candidate))
        let kept = left.filter { right.contains($0) }.count
        return Double(kept) / Double(left.count)
    }

    private static func tokens(_ text: String) -> [String] {
        text
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { $0.count >= 2 }
    }

    private static func collapseWhitespace(_ text: String) -> String {
        text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
