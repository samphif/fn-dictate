import AppKit
import ApplicationServices
import Foundation

/// After a dictation paste, watches the focused field via Accessibility and learns
/// short spelling fixes the user makes in-place (Wispr-style "correct once → remember").
@MainActor
final class InAppCorrectionWatcher {
    struct Result: Sendable {
        let correctedPaste: String
        let historyEntryID: UUID?
    }

    /// How long to keep observing after paste.
    var watchDuration: TimeInterval = 25
    /// Poll interval while watching.
    var pollInterval: TimeInterval = 0.45

    private var task: Task<Void, Never>?

    func cancel() {
        task?.cancel()
        task = nil
    }

    /// Begins watching. Calls `onResult` at most once when corrections are learned (or history should update).
    func start(
        pasted: String,
        targetApp: NSRunningApplication?,
        historyEntryID: UUID?,
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
                onResult: onResult
            )
        }
    }

    // MARK: - Watch loop

    private func watch(
        pasted: String,
        expectedPID: pid_t?,
        historyEntryID: UUID?,
        onResult: @escaping @MainActor (Result) -> Void
    ) async {
        guard let baseline = await settleBaseline(pasted: pasted, expectedPID: expectedPID) else {
            return
        }

        let deadline = Date().addingTimeInterval(watchDuration)
        var lastValue = baseline.snapshot.value
        var missCount = 0

        while Date() < deadline {
            if Task.isCancelled { return }
            try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
            if Task.isCancelled { return }

            guard let (element, snapshot) = FocusedTextReader.readFocused() else {
                missCount += 1
                if missCount >= 4 { return }
                continue
            }
            missCount = 0

            if snapshot.isSecure { return }
            if let expectedPID, snapshot.pid != expectedPID { return }
            if !FocusedTextReader.isSameElement(element, baseline.element) {
                // Focus moved to another control — stop (don't learn unrelated edits).
                return
            }

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

            // Defer learning until the edit looks stable (user paused briefly).
            try? await Task.sleep(nanoseconds: 550_000_000)
            if Task.isCancelled { return }

            guard let (_, stableSnap) = FocusedTextReader.readFocused(),
                  stableSnap.value == current
            else { continue }

            onResult(
                Result(
                    correctedPaste: corrected,
                    historyEntryID: historyEntryID
                )
            )
            return
        }
    }

    private struct Baseline {
        let element: AXUIElement
        let snapshot: FocusedTextReader.Snapshot
        let pasteRange: Range<String.Index>
    }

    /// Wait for paste to appear in the focused field.
    private func settleBaseline(pasted: String, expectedPID: pid_t?) async -> Baseline? {
        for _ in 0..<10 {
            if Task.isCancelled { return nil }
            try? await Task.sleep(nanoseconds: 120_000_000)
            if Task.isCancelled { return nil }

            guard let (element, snapshot) = FocusedTextReader.readFocused() else { continue }
            if snapshot.isSecure { return nil }
            if let expectedPID, snapshot.pid != expectedPID {
                // Activation race — keep trying briefly.
                continue
            }
            guard let range = Self.locatePaste(pasted, in: snapshot.value) else { continue }
            return Baseline(element: element, snapshot: snapshot, pasteRange: range)
        }
        return nil
    }

    // MARK: - Diff helpers

    /// Prefer the last exact occurrence (caret usually at end of insert).
    static func locatePaste(_ pasted: String, in haystack: String) -> Range<String.Index>? {
        if let range = haystack.range(of: pasted, options: .backwards) {
            return range
        }
        let collapsedPaste = collapseWhitespace(pasted)
        let collapsedHay = collapseWhitespace(haystack)
        guard collapsedPaste.count >= 2,
              let collapsedRange = collapsedHay.range(of: collapsedPaste, options: .backwards)
        else { return nil }

        // Map collapsed range back approximately via character offsets (best-effort).
        let startOffset = collapsedHay.distance(from: collapsedHay.startIndex, to: collapsedRange.lowerBound)
        let endOffset = collapsedHay.distance(from: collapsedHay.startIndex, to: collapsedRange.upperBound)
        guard let start = haystack.index(
            haystack.startIndex,
            offsetBy: min(startOffset, haystack.count),
            limitedBy: haystack.endIndex
        ),
            let end = haystack.index(
                haystack.startIndex,
                offsetBy: min(endOffset, haystack.count),
                limitedBy: haystack.endIndex
            ),
            start < end
        else { return nil }
        return start..<end
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

        if current.hasPrefix(prefix), current.hasSuffix(suffix) {
            let start = current.index(current.startIndex, offsetBy: prefix.count)
            let end = current.index(current.endIndex, offsetBy: -suffix.count)
            guard start <= end else { return nil }
            return String(current[start..<end])
        }

        // Field was (effectively) just our paste.
        if baseline == pasted
            || baseline.trimmingCharacters(in: .whitespacesAndNewlines)
                == pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        {
            return current
        }

        return nil
    }

    private static func collapseWhitespace(_ text: String) -> String {
        text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
