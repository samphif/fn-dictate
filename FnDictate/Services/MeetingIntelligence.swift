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

    func refine(
        transcript: String,
        segments: [MeetingTranscriptSegment],
        attendees: [String],
        calendarTitle: String?,
        dictionaryHints: [String]
    ) async -> RefinedMeeting {
        let labeled = labeledBody(transcript: transcript, segments: segments)

        #if canImport(FoundationModels)
        if #available(macOS 26, *),
           let smart = await smartRefine(
            labeled: labeled,
            attendees: attendees,
            calendarTitle: calendarTitle,
            dictionaryHints: dictionaryHints
           )
        {
            return smart
        }
        #endif

        return RefinedMeeting(
            title: calendarTitle?.isEmpty == false ? calendarTitle! : "Meeting",
            transcript: labeled,
            summary: fallbackSummary(from: labeled),
            decisions: [],
            actionItems: [],
            openQuestions: [],
            segments: segments
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
        let sentences = transcript
            .components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let preview = sentences.prefix(3).joined(separator: ". ")
        if preview.isEmpty { return "No speech captured." }
        return preview + (preview.hasSuffix(".") ? "" : ".")
    }

    #if canImport(FoundationModels)
    @available(macOS 26, *)
    private func smartRefine(
        labeled: String,
        attendees: [String],
        calendarTitle: String?,
        dictionaryHints: [String]
    ) async -> RefinedMeeting? {
        let people = attendees.isEmpty ? "unknown" : attendees.joined(separator: ", ")
        let terms = dictionaryHints.prefix(40).joined(separator: ", ")
        let prompt = """
        Refine this meeting transcript and produce structured notes.

        Known attendees (prefer these spellings for speaker labels): \(people)
        Calendar title hint: \(calendarTitle ?? "n/a")
        Preferred spellings / jargon: \(terms.isEmpty ? "n/a" : terms)

        Rules:
        - Keep [You] for the local participant.
        - Relabel [Others] lines to a real attendee name when the transcript strongly implies who spoke; otherwise keep [Others].
        - Fix names using the attendee list and preferred spellings.
        - Do not invent decisions or action items.

        Return exactly:
        TITLE: <short title>
        SUMMARY: <1-3 paragraph overview>
        DECISIONS:
        - <key point or decision>
        ACTIONS:
        - <action item with owner when known>
        QUESTIONS:
        - <open question>
        TRANSCRIPT:
        <full refined labeled transcript, one utterance per line as [Speaker] text>

        Prefer concrete key points in DECISIONS (outcomes, agreements, important facts), not filler.

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
        let segments = parseLabeledSegments(from: transcriptLines).isEmpty
            ? fallbackSegments
            : parseLabeledSegments(from: transcriptLines)

        return RefinedMeeting(
            title: title.isEmpty ? "Meeting" : title,
            transcript: transcript.isEmpty ? content : transcript,
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
            guard line.hasPrefix("["),
                  let close = line.firstIndex(of: "]")
            else { continue }
            let speaker = String(line[line.index(after: line.startIndex)..<close])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let textStart = line.index(after: close)
            let text = String(line[textStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
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
