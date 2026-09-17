import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// On-device meeting reasoning: re-read, catch-up, Q&A, and pre-meeting briefs.
struct MeetingIntelligence: Sendable {
    struct RefinedMeeting: Sendable {
        var title: String
        var transcript: String
        var summary: String
        var decisions: [String]
        var actionItems: [String]
        var openQuestions: [String]
        var segments: [MeetingTranscriptSegment]
    }

    struct RefineResult: Sendable {
        var meeting: RefinedMeeting
        /// True when Apple Intelligence produced the structured notes.
        var usedAppleIntelligence: Bool
        /// Human-readable reason when falling back or partially succeeding.
        var message: String?
    }

    /// Soft cap for a single on-device prompt. Longer meetings are chunked.
    private let maxChunkCharacters = 5_500

    func refine(
        transcript: String,
        segments: [MeetingTranscriptSegment],
        attendees: [String],
        calendarTitle: String?,
        dictionaryHints: [String]
    ) async -> RefineResult {
        let labeled = labeledBody(transcript: transcript, segments: segments)
        let availabilityMessage = appleIntelligenceUnavailableReason()

        #if canImport(FoundationModels)
        if #available(macOS 26, *), availabilityMessage == nil {
            if let smart = await smartRefineLongMeeting(
                labeled: labeled,
                segments: segments,
                attendees: attendees,
                calendarTitle: calendarTitle,
                dictionaryHints: dictionaryHints
            ) {
                return RefineResult(
                    meeting: smart,
                    usedAppleIntelligence: true,
                    message: nil
                )
            }
            return fallbackResult(
                labeled: labeled,
                segments: segments,
                calendarTitle: calendarTitle,
                message: "Apple Intelligence couldn't finish summarizing this meeting. You can retry."
            )
        }
        #endif

        return fallbackResult(
            labeled: labeled,
            segments: segments,
            calendarTitle: calendarTitle,
            message: availabilityMessage
                ?? "Apple Intelligence unavailable — showing a short transcript preview."
        )
    }

    func catchUp(
        segments: [MeetingTranscriptSegment],
        sinceOffset: TimeInterval,
        attendees: [String]
    ) async -> String {
        let recent = segments
            .filter { $0.startOffset >= sinceOffset }
            .sorted { $0.startOffset < $1.startOffset }
        guard !recent.isEmpty else {
            return "Nothing new to catch up on yet."
        }
        let body = recent.map { "[\($0.speaker)] \($0.text)" }.joined(separator: "\n")

        #if canImport(FoundationModels)
        if #available(macOS 26, *),
           let answer = await prompt(
            instructions: "You write short mid-meeting catch-up notes. Be concrete and brief.",
            user: """
            Summarize what the listener missed in the last few minutes.
            Attendees: \(attendees.isEmpty ? "unknown" : attendees.joined(separator: ", "))
            Focus on decisions, action items, and open questions.

            Transcript:
            \(body)
            """
           )
        {
            return answer
        }
        #endif

        return fallbackSummary(from: body)
    }

    func ask(
        question: String,
        notes: [MeetingNote]
    ) async -> String {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Ask a question about your meetings." }
        guard !notes.isEmpty else { return "No meeting notes yet." }

        let corpus = notes.prefix(12).map { note in
            """
            ---
            Title: \(note.title)
            Date: \(note.createdAt.formatted(date: .abbreviated, time: .shortened))
            Attendees: \(note.attendees.joined(separator: ", "))
            Summary: \(note.summary)
            Decisions: \(note.decisions.joined(separator: "; "))
            Actions: \(note.actionItems.joined(separator: "; "))
            Questions: \(note.openQuestions.joined(separator: "; "))
            Transcript excerpt:
            \(String(note.labeledTranscript.prefix(2500)))
            """
        }.joined(separator: "\n")

        #if canImport(FoundationModels)
        if #available(macOS 26, *),
           let answer = await prompt(
            instructions: """
            You answer questions using only the provided meeting notes. \
            Cite the meeting title and approximate time when possible. \
            If the notes don't contain the answer, say so.
            """,
            user: """
            Question: \(trimmed)

            Meeting notes:
            \(corpus)
            """
           )
        {
            return answer
        }
        #endif

        // Keyword fallback when Foundation Models unavailable.
        let q = trimmed.lowercased()
        let hits = notes.filter {
            $0.title.lowercased().contains(q)
                || $0.summary.lowercased().contains(q)
                || $0.transcript.lowercased().contains(q)
                || $0.actionItems.contains { $0.lowercased().contains(q) }
        }
        if hits.isEmpty {
            return "Couldn't find that in your local notes (Apple Intelligence unavailable for a fuller answer)."
        }
        return hits.prefix(3).map {
            "• \($0.title) — \($0.summary.isEmpty ? String($0.transcript.prefix(160)) : String($0.summary.prefix(200)))"
        }.joined(separator: "\n")
    }

    func brief(
        calendar: CalendarMeetingContext?,
        pastNotes: [MeetingNote]
    ) async -> String? {
        guard let calendar else { return nil }

        let related = pastNotes.filter { note in
            let hay = "\(note.title) \(note.summary) \(note.attendees.joined(separator: " "))".lowercased()
            let titleHit = hay.contains(calendar.title.lowercased())
            let peopleHit = calendar.attendees.contains { attendee in
                hay.contains(attendee.lowercased())
            }
            return titleHit || peopleHit
        }.prefix(5)

        let past = related.map {
            "- \($0.title) (\($0.createdAt.formatted(date: .abbreviated, time: .omitted))): \(String($0.summary.prefix(280)))"
        }.joined(separator: "\n")

        #if canImport(FoundationModels)
        if #available(macOS 26, *),
           let answer = await prompt(
            instructions: "You write concise pre-meeting briefs from local notes only. No web search.",
            user: """
            Upcoming meeting: \(calendar.title)
            When: \(calendar.startDate.formatted(date: .abbreviated, time: .shortened)) – \(calendar.endDate.formatted(date: .omitted, time: .shortened))
            Attendees: \(calendar.attendees.isEmpty ? "unknown" : calendar.attendees.joined(separator: ", "))
            Location: \(calendar.location ?? "n/a")
            Invite notes: \(calendar.notes ?? "n/a")

            Related past notes:
            \(past.isEmpty ? "(none)" : past)

            Write a short brief: agenda guess, people to watch, open threads from past notes, and 2–3 questions to ask.
            """
           )
        {
            return answer
        }
        #endif

        var lines = ["Meeting: \(calendar.title)"]
        if !calendar.attendees.isEmpty {
            lines.append("With: \(calendar.attendees.joined(separator: ", "))")
        }
        if !past.isEmpty {
            lines.append("Related past notes:\n\(past)")
        } else {
            lines.append("No related past notes found locally.")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Private

    private func labeledBody(transcript: String, segments: [MeetingTranscriptSegment]) -> String {
        if !segments.isEmpty {
            return segments
                .sorted { $0.startOffset < $1.startOffset }
                .map { "[\($0.speaker)] \($0.text)" }
                .joined(separator: "\n")
        }
        return transcript
    }

    private func fallbackSummary(from transcript: String) -> String {
        let stripped = transcript
            .replacingOccurrences(of: #"^\[.*?\]\s*"#, with: "", options: .regularExpression)
        let sentences = stripped
            .components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let preview = sentences.prefix(3).joined(separator: ". ")
        if preview.isEmpty { return "No speech captured." }
        return preview + (preview.hasSuffix(".") ? "" : ".")
    }

    private func fallbackResult(
        labeled: String,
        segments: [MeetingTranscriptSegment],
        calendarTitle: String?,
        message: String
    ) -> RefineResult {
        RefineResult(
            meeting: RefinedMeeting(
                title: calendarTitle?.isEmpty == false ? calendarTitle! : "Meeting",
                transcript: labeled,
                summary: fallbackSummary(from: labeled),
                decisions: [],
                actionItems: [],
                openQuestions: [],
                segments: segments
            ),
            usedAppleIntelligence: false,
            message: message
        )
    }

    private func appleIntelligenceUnavailableReason() -> String? {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            let model = SystemLanguageModel.default
            if case .available = model.availability {
                return nil
            }
            return "Apple Intelligence isn't ready. Check System Settings, then retry."
        }
        return "macOS 26+ with Apple Intelligence is required for meeting summaries."
        #else
        return "Apple Intelligence isn't available in this build."
        #endif
    }

    #if canImport(FoundationModels)
    @available(macOS 26, *)
    private func smartRefineLongMeeting(
        labeled: String,
        segments: [MeetingTranscriptSegment],
        attendees: [String],
        calendarTitle: String?,
        dictionaryHints: [String]
    ) async -> RefinedMeeting? {
        let people = attendees.isEmpty ? "unknown" : attendees.joined(separator: ", ")
        let terms = dictionaryHints.prefix(40).joined(separator: ", ")

        let notes: RefinedMeeting?
        if labeled.count <= maxChunkCharacters {
            notes = await smartRefineSinglePass(
                labeled: labeled,
                attendees: attendees,
                calendarTitle: calendarTitle,
                dictionaryHints: dictionaryHints,
                includeTranscriptRewrite: labeled.count <= 3_500
            )
        } else {
            notes = await smartRefineChunked(
                labeled: labeled,
                segments: segments,
                people: people,
                calendarTitle: calendarTitle,
                terms: terms
            )
        }

        guard var refined = notes else { return nil }

        let relabeled = await relabelSpeakers(
            segments: segments.isEmpty ? refined.segments : segments,
            attendees: attendees
        )
        if !relabeled.isEmpty {
            refined.segments = relabeled
            refined.transcript = labeledBody(transcript: refined.transcript, segments: relabeled)
        } else if refined.segments.isEmpty {
            refined.segments = segments
        }
        if refined.transcript.isEmpty {
            refined.transcript = labeled
        }

        if refined.title.isEmpty {
            refined.title = calendarTitle?.isEmpty == false ? calendarTitle! : "Meeting"
        }
        return refined
    }

    @available(macOS 26, *)
    private func smartRefineSinglePass(
        labeled: String,
        attendees: [String],
        calendarTitle: String?,
        dictionaryHints: [String],
        includeTranscriptRewrite: Bool
    ) async -> RefinedMeeting? {
        let people = attendees.isEmpty ? "unknown" : attendees.joined(separator: ", ")
        let terms = dictionaryHints.prefix(40).joined(separator: ", ")
        let transcriptBlock = includeTranscriptRewrite
            ? """
            TRANSCRIPT:
            <refined labeled transcript, one utterance per line as [Speaker] text>
            """
            : """
            TRANSCRIPT:
            (omit — keep original)
            """

        let prompt = """
        Refine this meeting transcript into structured personal notes.

        Known attendees (prefer these spellings for speaker labels): \(people)
        Calendar title hint: \(calendarTitle ?? "n/a")
        Preferred spellings / jargon: \(terms.isEmpty ? "n/a" : terms)

        Rules:
        - Keep [You] for the local participant.
        - Relabel [Others] (or mislabeled lines) to a real attendee name when the transcript strongly implies who spoke; otherwise keep [Others] or [You].
        - Extract concrete action items with owners when known — even if worded casually ("I'll send…", "can you…").
        - Prefer useful key points over filler. Do not invent facts that aren't supported.

        Return exactly:
        TITLE: <short title>
        SUMMARY: <1-3 paragraph overview of what the meeting was about and outcomes>
        DECISIONS:
        - <key point or decision>
        ACTIONS:
        - <action item with owner when known>
        QUESTIONS:
        - <open question>
        \(transcriptBlock)

        Transcript:
        \(labeled)
        """

        guard let content = await self.prompt(
            instructions: "You write accurate personal meeting notes. Follow the requested format exactly.",
            user: prompt
        ) else { return nil }

        return parseRefineResponse(content, fallbackSegments: [])
    }

    @available(macOS 26, *)
    private func smartRefineChunked(
        labeled: String,
        segments: [MeetingTranscriptSegment],
        people: String,
        calendarTitle: String?,
        terms: String
    ) async -> RefinedMeeting? {
        let chunks = chunkLabeledTranscript(labeled, segments: segments)
        guard !chunks.isEmpty else { return nil }

        var partials: [String] = []
        for (index, chunk) in chunks.enumerated() {
            let prompt = """
            Extract structured notes from part \(index + 1) of \(chunks.count) of a longer meeting.

            Known attendees: \(people)
            Calendar title hint: \(calendarTitle ?? "n/a")
            Preferred spellings / jargon: \(terms.isEmpty ? "n/a" : terms)

            Return exactly:
            SUMMARY: <2-5 sentences covering this part only>
            DECISIONS:
            - <key point or decision from this part>
            ACTIONS:
            - <action item with owner when known>
            QUESTIONS:
            - <open question from this part>

            Omit empty sections' bullets. Do not invent items.

            Transcript part:
            \(chunk)
            """
            if let content = await self.prompt(
                instructions: "You extract concrete meeting notes from a transcript excerpt. Follow the format exactly.",
                user: prompt
            ) {
                partials.append(content)
            }
        }

        guard !partials.isEmpty else { return nil }

        let mergePrompt = """
        Merge these partial meeting notes into one clean personal note.

        Calendar title hint: \(calendarTitle ?? "n/a")
        Attendees: \(people)

        Deduplicate overlapping items. Prefer concrete actions and decisions. Write a coherent overview.

        Return exactly:
        TITLE: <short title>
        SUMMARY: <1-3 paragraph overview>
        DECISIONS:
        - <key point or decision>
        ACTIONS:
        - <action item with owner when known>
        QUESTIONS:
        - <open question>

        Partial notes:
        \(partials.joined(separator: "\n\n---\n\n"))
        """

        guard let merged = await self.prompt(
            instructions: "You merge meeting note excerpts into one accurate note. Follow the format exactly.",
            user: mergePrompt
        ) else { return nil }

        var refined = parseRefineResponse(merged, fallbackSegments: segments)
        if refined.transcript.isEmpty {
            refined.transcript = labeled
        }
        if refined.segments.isEmpty {
            refined.segments = segments
        }
        return refined
    }

    @available(macOS 26, *)
    private func relabelSpeakers(
        segments: [MeetingTranscriptSegment],
        attendees: [String]
    ) async -> [MeetingTranscriptSegment] {
        guard !segments.isEmpty else { return [] }
        let speakers = Set(segments.map(\.speaker))
        let onlyYou = speakers.count == 1 && speakers.contains("You")
        let hasOthers = speakers.contains("Others")
        // Relabel when we have attendee names and either coarse "Others" labels or a mono "You" mic mix.
        guard !attendees.isEmpty, onlyYou || hasOthers else {
            return []
        }

        var result: [MeetingTranscriptSegment] = []
        let batches = chunkSegments(segments, maxCharacters: maxChunkCharacters)
        for batch in batches {
            let body = batch.map { "[\($0.speaker)] \($0.text)" }.joined(separator: "\n")
            let prompt = """
            Relabel speakers for these meeting utterances.

            Known attendees: \(attendees.joined(separator: ", "))
            Rules:
            - Keep [You] when the local participant is speaking (first person about their own actions is a hint, not a rule).
            - Replace [Others] with an attendee name when the content strongly implies who spoke.
            - If everything is labeled [You] but clearly includes other people talking, relabel those lines to attendees when possible; otherwise leave [You].
            - Do not change the spoken text — only the [Speaker] label.
            - Return the same number of lines, one per input line, as [Speaker] text.

            Utterances:
            \(body)
            """
            guard let content = await self.prompt(
                instructions: "You only relabel speakers. Preserve utterance text. One [Speaker] line per input line.",
                user: prompt
            ) else {
                result.append(contentsOf: batch)
                continue
            }
            let parsed = parseLabeledSegments(from: content.components(separatedBy: .newlines))
            if parsed.count == batch.count {
                for (index, seg) in batch.enumerated() {
                    var updated = seg
                    updated.speaker = parsed[index].speaker
                    result.append(updated)
                }
            } else {
                result.append(contentsOf: batch)
            }
        }
        return result
    }

    private func chunkLabeledTranscript(
        _ labeled: String,
        segments: [MeetingTranscriptSegment]
    ) -> [String] {
        if !segments.isEmpty {
            return chunkSegments(segments, maxCharacters: maxChunkCharacters)
                .map { batch in
                    batch.map { "[\($0.speaker)] \($0.text)" }.joined(separator: "\n")
                }
        }
        return chunkPlainText(labeled, maxCharacters: maxChunkCharacters)
    }

    private func chunkSegments(
        _ segments: [MeetingTranscriptSegment],
        maxCharacters: Int
    ) -> [[MeetingTranscriptSegment]] {
        let ordered = segments.sorted { $0.startOffset < $1.startOffset }
        var batches: [[MeetingTranscriptSegment]] = []
        var current: [MeetingTranscriptSegment] = []
        var size = 0
        for seg in ordered {
            let lineSize = seg.speaker.count + seg.text.count + 4
            if !current.isEmpty, size + lineSize > maxCharacters {
                batches.append(current)
                current = []
                size = 0
            }
            current.append(seg)
            size += lineSize
        }
        if !current.isEmpty {
            batches.append(current)
        }
        return batches
    }

    private func chunkPlainText(_ text: String, maxCharacters: Int) -> [String] {
        guard text.count > maxCharacters else { return text.isEmpty ? [] : [text] }
        var chunks: [String] = []
        var start = text.startIndex
        while start < text.endIndex {
            let remaining = text.distance(from: start, to: text.endIndex)
            let length = min(maxCharacters, remaining)
            var end = text.index(start, offsetBy: length)
            if end < text.endIndex,
               let breakIdx = text[start..<end].lastIndex(of: "\n")
            {
                end = text.index(after: breakIdx)
            }
            let chunk = String(text[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !chunk.isEmpty {
                chunks.append(chunk)
            }
            start = end
        }
        return chunks
    }

    @available(macOS 26, *)
    private func prompt(instructions: String, user: String) async -> String? {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else { return nil }
        do {
            let session = LanguageModelSession(model: model, instructions: instructions)
            let response = try await session.respond(to: user)
            let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        } catch {
            return nil
        }
    }

    private func parseRefineResponse(
        _ content: String,
        fallbackSegments: [MeetingTranscriptSegment]
    ) -> RefinedMeeting {
        var title = ""
        var summary = ""
        var decisions: [String] = []
        var actions: [String] = []
        var questions: [String] = []
        var transcriptLines: [String] = []
        var section = ""

        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            let upper = line.uppercased()
            if upper.hasPrefix("TITLE:") {
                title = line.drop(while: { $0 != ":" }).dropFirst().trimmingCharacters(in: .whitespaces)
                section = "title"
            } else if upper.hasPrefix("SUMMARY:") {
                summary = line.drop(while: { $0 != ":" }).dropFirst().trimmingCharacters(in: .whitespaces)
                section = "summary"
            } else if upper.hasPrefix("DECISIONS") {
                section = "decisions"
            } else if upper.hasPrefix("ACTIONS") {
                section = "actions"
            } else if upper.hasPrefix("QUESTIONS") {
                section = "questions"
            } else if upper.hasPrefix("TRANSCRIPT") {
                section = "transcript"
            } else if line.hasPrefix("-") {
                let item = line.dropFirst().trimmingCharacters(in: .whitespaces)
                guard !item.isEmpty else { continue }
                // Skip placeholder / omit lines from the model.
                let lower = item.lowercased()
                if lower.hasPrefix("(omit") || lower == "none" || lower == "n/a" { continue }
                switch section {
                case "decisions": decisions.append(item)
                case "actions": actions.append(item)
                case "questions": questions.append(item)
                default: break
                }
            } else if section == "summary", !line.isEmpty {
                summary = summary.isEmpty ? line : summary + "\n" + line
            } else if section == "transcript", !line.isEmpty {
                transcriptLines.append(line)
            }
        }

        let transcript = transcriptLines.joined(separator: "\n")
        let parsedSegments = parseLabeledSegments(from: transcriptLines)
        let segments = parsedSegments.isEmpty ? fallbackSegments : parsedSegments

        return RefinedMeeting(
            title: title.isEmpty ? "Meeting" : title,
            transcript: transcript,
            summary: summary,
            decisions: decisions,
            actionItems: actions,
            openQuestions: questions,
            segments: segments
        )
    }

    private func parseLabeledSegments(from lines: [String]) -> [MeetingTranscriptSegment] {
        var offset: TimeInterval = 0
        var result: [MeetingTranscriptSegment] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("["),
                  let close = trimmed.firstIndex(of: "]")
            else { continue }
            let speaker = String(trimmed[trimmed.index(after: trimmed.startIndex)..<close])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let textStart = trimmed.index(after: close)
            let text = String(trimmed[textStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !speaker.isEmpty, !text.isEmpty else { continue }
            result.append(
                MeetingTranscriptSegment(startOffset: offset, text: text, speaker: speaker)
            )
            offset += 4
        }
        return result
    }
    #endif
}
