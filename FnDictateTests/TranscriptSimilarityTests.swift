import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FnDictate

struct TranscriptSimilarityTests {
    @Test func tokensIgnoreCaseAndPunctuation() {
        #expect(TranscriptSimilarity.tokens("Hey, Sam! It's 5pm.") == ["hey", "sam", "it", "s", "5pm"])
        #expect(TranscriptSimilarity.tokenCount("   ") == 0)
    }

    @Test func similarityIsSharedWordsOverLongerLine() {
        #expect(TranscriptSimilarity.similarity("ship it friday", "ship it on friday") == 0.75)
        #expect(TranscriptSimilarity.similarity("", "anything") == 0)
    }

    @Test func nearDuplicateToleratesSmallAsrDifferences() {
        #expect(TranscriptSimilarity.isNearDuplicate(
            "we should ship the build on friday",
            "We should ship the bill on Friday"
        ))
    }

    @Test func shortRepliesNeedAClosematch() {
        #expect(!TranscriptSimilarity.isNearDuplicate("sounds good", "sounds great"))
        #expect(TranscriptSimilarity.isNearDuplicate("sounds good", "Sounds good."))
        #expect(!TranscriptSimilarity.isNearDuplicate("ok", "ok"))
    }

    @Test func collapsingEchoesPrefersTheNonYouCopyWithLongerText() {
        let voice = UUID()
        let segments = [
            MeetingTranscriptSegment(startOffset: 2, text: "we should ship the build on friday", speaker: "You"),
            MeetingTranscriptSegment(
                startOffset: 2.4,
                text: "we should ship the build",
                speaker: "Jodi",
                voiceID: voice
            ),
            MeetingTranscriptSegment(startOffset: 30, text: "we should ship the build on friday", speaker: "You"),
        ]
        let collapsed = TranscriptSimilarity.collapsingChannelEchoes(segments)
        #expect(collapsed.count == 2)
        #expect(collapsed[0].speaker == "Jodi")
        #expect(collapsed[0].text == "we should ship the build on friday")
        #expect(collapsed[0].voiceID == voice)
        #expect(collapsed[0].startOffset == 2)
        #expect(collapsed[1].speaker == "You")
    }
}

struct CalendarMeetingContextTests {
    private func context(_ attendees: [String]) -> CalendarMeetingContext {
        CalendarMeetingContext(
            eventIdentifier: "id",
            title: "Sync",
            startDate: .now,
            endDate: .now,
            attendees: attendees,
            location: nil,
            notes: nil
        )
    }

    @Test func singleAttendeeIsTheOneOnOneName() {
        #expect(context(["Jodi"]).remoteOneOnOneName == "Jodi")
        #expect(context([" Jodi ", "Jodi", "  "]).remoteOneOnOneName == "Jodi")
    }

    @Test func groupOrEmptyInviteHasNoOneOnOneName() {
        #expect(context([]).remoteOneOnOneName == nil)
        #expect(context(["Jodi", "Virginia"]).remoteOneOnOneName == nil)
    }
}

struct HostingHitTestPolicyTests {
    @Test func pressureAndDirectTouchNeverEnterSwiftUIHitTesting() {
        #expect(HostingHitTestPolicy.bypassesSwiftUIHitTest(.pressure))
        #expect(HostingHitTestPolicy.bypassesSwiftUIHitTest(.directTouch))
    }

    @Test func ordinaryPointerEventsStillHitTest() {
        #expect(!HostingHitTestPolicy.bypassesSwiftUIHitTest(.mouseMoved))
        #expect(!HostingHitTestPolicy.bypassesSwiftUIHitTest(.leftMouseDown))
        #expect(!HostingHitTestPolicy.bypassesSwiftUIHitTest(.leftMouseDragged))
        #expect(!HostingHitTestPolicy.bypassesSwiftUIHitTest(.mouseEntered))
    }

    @MainActor
    @Test func openingTheRailDoesNotWalkThePanelDownAndRight() {
        let panel = OverlayPanel(
            contentRect: NSRect(x: 0, y: 0, width: 15, height: 48),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.hasShadow = false
        panel.lockFrameSize()
        let model = AppModel()
        panel.contentViewController = ClearHostingController(rootView: MeetingPromptView(model: model))

        func place(_ size: CGSize, from old: NSRect) -> NSRect {
            NSRect(
                origin: NSPoint(x: old.maxX - size.width, y: old.midY - size.height / 2),
                size: size
            )
        }

        let collapsed = CGSize(width: 15, height: 48)
        let expanded = CGSize(width: 168, height: 112)
        var frame = NSRect(x: 400, y: 500, width: collapsed.width, height: collapsed.height)
        panel.setFrameAllowingSizeChange(frame, display: true)
        panel.orderFrontRegardless()

        for _ in 0..<6 {
            model.flowSidebarExpanded = true
            frame = place(expanded, from: panel.frame)
            panel.setFrameAllowingSizeChange(frame, display: true)
            panel.contentView?.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))

            model.flowSidebarExpanded = false
            frame = place(collapsed, from: panel.frame)
            panel.setFrameAllowingSizeChange(frame, display: true)
            panel.contentView?.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }

        #expect(abs(panel.frame.maxX - 415) < 1)
        #expect(abs(panel.frame.midY - 524) < 1)
        #expect(abs(panel.frame.width - collapsed.width) < 1)
        #expect(abs(panel.frame.height - collapsed.height) < 1)

        panel.setFrameOrigin(NSPoint(x: panel.frame.origin.x - 30, y: panel.frame.origin.y - 20))
        #expect(abs(panel.frame.maxX - 385) < 1)
        #expect(abs(panel.frame.midY - 504) < 1)

        panel.orderOut(nil)
    }

    @MainActor
    @Test func shieldedHostingViewStillHitTestsClicks() {
        HostingEventShield.install()
        let hosting = NSHostingView(rootView: Text("Hi").frame(width: 80, height: 40))
        hosting.frame = NSRect(x: 0, y: 0, width: 80, height: 40)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 80, height: 40),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        let hit = hosting.hitTest(NSPoint(x: 20, y: 20))
        #expect(hit != nil)
        #expect(HostingEventShield.wrapsSwiftUIHitTest())
    }
}
