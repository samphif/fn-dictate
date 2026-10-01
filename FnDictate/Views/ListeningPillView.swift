import AppKit
import Darwin
import ObjectiveC
import SwiftUI

/// Wispr-style vertical listening rail: cancel · waveform · confirm, docked to the side.
struct ListeningPillView: View {
    @Bindable var model: AppModel

    private var isLive: Bool {
        model.phase == .listening || model.phase == .meetingRecording
    }

    var body: some View {
        VStack(spacing: 14) {
            Button {
                model.cancelListeningPill()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.white.opacity(0.14)))
            }
            .buttonStyle(.plain)
            .help(cancelHelp)

            ZStack {
                WindowDragHandle(onClick: nil)
                SideWaveformView(
                    level: model.audioLevel,
                    isActive: isLive,
                    tint: indicatorColor
                )
                .frame(width: 22, height: 72)
                .allowsHitTesting(false)
            }
            .frame(width: 28, height: 72)
            .help("Listening — drag to move")

            Button {
                model.confirmListeningPill()
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.white))
            }
            .buttonStyle(.plain)
            .help(confirmHelp)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .background(
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.92))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
        )
        // No compositingGroup shadow — that casts a square halo around the panel.
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .preferredColorScheme(.dark)
    }

    private var cancelHelp: String {
        switch model.phase {
        case .meetingRecording: return "Cancel meeting recording"
        default: return "Cancel dictation"
        }
    }

    private var confirmHelp: String {
        switch model.phase {
        case .meetingRecording: return "Stop and save meeting notes"
        default: return "Finish and paste"
        }
    }

    private var indicatorColor: Color {
        switch model.phase {
        case .listening, .meetingRecording: return .white
        case .processing, .meetingProcessing: return .orange
        case .idle: return .white.opacity(0.45)
        }
    }
}

/// Horizontal bars stacked vertically — Wispr Flow side-rail waveform.
struct SideWaveformView: View {
    let level: Float
    let isActive: Bool
    let tint: Color

    /// Avoid `TimelineView(.animation)` — on macOS 26+ its update path can crash in
    /// `swift_task_isMainExecutorImpl` during NSHostingView layout. Drive motion via
    /// Shape `animatableData` instead.
    @State private var phase: CGFloat = 0

    private let barCount = 11

    var body: some View {
        SideWaveformShape(
            phase: phase,
            level: CGFloat(level),
            isActive: isActive,
            barCount: barCount
        )
        .fill(tint.opacity(isActive ? 0.95 : 0.35))
        .onAppear { syncAnimation() }
        .onChange(of: isActive) { _, _ in syncAnimation() }
    }

    private func syncAnimation() {
        if isActive {
            phase = 0
            withAnimation(.linear(duration: 120).repeatForever(autoreverses: false)) {
                phase = 120
            }
        } else {
            withAnimation(.easeOut(duration: 0.15)) {
                phase = 0
            }
        }
    }
}

private struct SideWaveformShape: Shape {
    var phase: CGFloat
    var level: CGFloat
    var isActive: Bool
    var barCount: Int

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(phase, level) }
        set {
            phase = newValue.first
            level = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let spacing: CGFloat = 2.5
        let barHeight: CGFloat = 2.5
        let totalHeight = CGFloat(barCount) * barHeight + CGFloat(barCount - 1) * spacing
        let originY = (rect.height - totalHeight) / 2
        let mid = CGFloat(barCount - 1) / 2
        let base: CGFloat = 4
        let maxExtra: CGFloat = min(16, max(0, rect.width - base))
        let speech = max(0.08, min(1, level))

        for index in 0..<barCount {
            let envelope = 1 - abs(CGFloat(index) - mid) / mid
            let width: CGFloat
            if isActive {
                let barPhase = CGFloat(index) * 0.55
                let wobble = (sin(phase * (10.0 + CGFloat(index) * 0.9) + barPhase) + 1) / 2
                let pulse = 0.3 * wobble + 0.7 * speech * (0.5 + 0.5 * wobble)
                width = base + maxExtra * envelope * (0.35 + 0.65 * pulse)
            } else {
                width = base + maxExtra * envelope * 0.45
            }
            let x = (rect.width - width) / 2
            let y = originY + CGFloat(index) * (barHeight + spacing)
            path.addRoundedRect(
                in: CGRect(x: x, y: y, width: width, height: barHeight),
                cornerSize: CGSize(width: barHeight / 2, height: barHeight / 2)
            )
        }
        return path
    }
}

// MARK: - Panel dragging

/// AppKit drag handle — click (no drag) fires `onClick`; drag moves the window.
/// Optional `onHover` uses a tracking area so expand works even when the panel isn't key.
struct WindowDragHandle: NSViewRepresentable {
    var onClick: (() -> Void)?
    var onHover: ((Bool) -> Void)?

    func makeNSView(context: Context) -> WindowDragNSView {
        let view = WindowDragNSView()
        view.onClick = onClick
        view.onHover = onHover
        return view
    }

    func updateNSView(_ nsView: WindowDragNSView, context: Context) {
        nsView.onClick = onClick
        nsView.onHover = onHover
        nsView.updateTrackingAreas()
    }
}

final class WindowDragNSView: NSView {
    var onClick: (() -> Void)?
    var onHover: ((Bool) -> Void)?
    private let clickSlop: CGFloat = 5

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        guard onHover != nil else { return }
        addTrackingArea(
            NSTrackingArea(
                rect: .zero,
                options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
        )
    }

    override func mouseEntered(with event: NSEvent) {
        onHover?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHover?(false)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Always claim hits inside our bounds so we sit above SwiftUI chrome.
        bounds.contains(point) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        let downScreen = NSEvent.mouseLocation
        let originOnDown = window.frame.origin
        var dragged = false

        while true {
            guard let tracked = window.nextEvent(
                matching: [.leftMouseDragged, .leftMouseUp],
                until: .distantFuture,
                inMode: .eventTracking,
                dequeue: true
            ) else { break }

            if tracked.type == .leftMouseUp {
                if !dragged {
                    onClick?()
                }
                break
            }

            let now = NSEvent.mouseLocation
            let dx = now.x - downScreen.x
            let dy = now.y - downScreen.y
            if hypot(dx, dy) >= clickSlop {
                dragged = true
            }
            if dragged {
                window.setFrameOrigin(NSPoint(x: originOnDown.x + dx, y: originOnDown.y + dy))
            }
        }
    }
}

// MARK: - Hover without SwiftUI

extension View {
    /// Hover via an AppKit tracking area.
    ///
    /// SwiftUI `.onHover` installs a HoverResponder. On this OS, delivering that
    /// hover from `NSHostingView` traps in `MainActor.assumeIsolated`.
    func appKitHover(_ action: @escaping (Bool) -> Void) -> some View {
        background(AppKitHoverPad(onHover: action))
    }
}

private struct AppKitHoverPad: NSViewRepresentable {
    var onHover: (Bool) -> Void

    func makeNSView(context: Context) -> AppKitHoverNSView {
        let view = AppKitHoverNSView()
        view.onHover = onHover
        return view
    }

    func updateNSView(_ view: AppKitHoverNSView, context: Context) {
        view.onHover = onHover
        view.updateTrackingAreas()
    }
}

/// Tracking only. `hitTest` returns nil so clicks fall through to buttons and rows.
final class AppKitHoverNSView: NSView {
    var onHover: ((Bool) -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        guard onHover != nil else { return }
        addTrackingArea(
            NSTrackingArea(
                rect: .zero,
                options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
        )
    }

    override func mouseEntered(with event: NSEvent) {
        onHover?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHover?(false)
    }
}

// MARK: - Hosting-view event shield

/// Which AppKit events must not enter SwiftUI hit testing.
///
/// Trackpad pressure is latched from inside `nextEventMatchingMask` before the
/// event is installed as current. SwiftUI's `platformCurrentEvent` then calls
/// `MainActor.assumeIsolated`, and `swift_getObjectType` pointer-auth traps.
enum HostingHitTestPolicy {
    static func bypassesSwiftUIHitTest(_ type: NSEvent.EventType) -> Bool {
        switch type {
        case .pressure, .directTouch:
            true
        default:
            false
        }
    }
}

/// Keeps AppKit event delivery out of the SwiftUI paths that crash the process.
enum HostingEventShield {
    // Touched from ObjC block IMPs. Those IMPs must not be MainActor-isolated:
    // the crash is the isolation check itself.
    private nonisolated(unsafe) static var installed = false
    private nonisolated(unsafe) static var originalHitTest: IMP?
    private nonisolated(unsafe) static var pressureRaw: UInt = 0
    private nonisolated(unsafe) static var directTouchRaw: UInt = 0

    @MainActor
    static func install() {
        guard !installed else { return }
        pressureRaw = NSEvent.EventType.pressure.rawValue
        directTouchRaw = NSEvent.EventType.directTouch.rawValue
        HostingEventProbe.captureApplication()
        let hostingClass: AnyClass = NSHostingView<AnyView>.self
        wrap(hostingClass, NSSelectorFromString("hitTest:"), hitTestBlock, store: { originalHitTest = $0 })
        // Drop SwiftUI hover delivery everywhere. `.onHover` was reaching
        // `sendHoverEvent` and trapping; AppKit tracking covers the hovers we need.
        // Clicks still go through hitTest.
        let dropHover = ignoreHoverBlock
        wrap(hostingClass, NSSelectorFromString("mouseMoved:"), dropHover, store: { _ in })
        wrap(hostingClass, NSSelectorFromString("mouseEntered:"), dropHover, store: { _ in })
        wrap(hostingClass, NSSelectorFromString("mouseExited:"), dropHover, store: { _ in })
        installed = true
    }

    /// True when ordinary clicks still enter SwiftUI's hit test, not `NSView`'s.
    static func wrapsSwiftUIHitTest() -> Bool {
        guard let original = originalHitTest,
              let viewMethod = class_getInstanceMethod(NSView.self, NSSelectorFromString("hitTest:")) else {
            return false
        }
        return original != method_getImplementation(viewMethod)
    }

    private static func wrap(
        _ cls: AnyClass,
        _ selector: Selector,
        _ block: Any,
        store: (IMP) -> Void
    ) {
        guard let method = class_getInstanceMethod(cls, selector),
              let encoding = method_getTypeEncoding(method) else { return }
        let newIMP = imp_implementationWithBlock(block)
        if class_addMethod(cls, selector, newIMP, encoding) {
            store(method_getImplementation(method))
        } else if let owned = class_getInstanceMethod(cls, selector) {
            store(method_setImplementation(owned, newIMP))
        }
    }

    /// ObjC block IMPs, not Swift methods. A Swift `hitTest` override is MainActor
    /// isolated, and that isolation check is the crash we're avoiding.
    private nonisolated(unsafe) static let hitTestBlock: @convention(block) (AnyObject, NSPoint) -> NSView? = { object, point in
        if let raw = HostingEventProbe.currentEventTypeRawValue(),
           raw == pressureRaw || raw == directTouchRaw {
            return nil
        }
        guard let original = originalHitTest else { return nil }
        typealias HitTest = @convention(c) (AnyObject, Selector, NSPoint) -> NSView?
        return unsafeBitCast(original, to: HitTest.self)(object, NSSelectorFromString("hitTest:"), point)
    }

    private nonisolated(unsafe) static let ignoreHoverBlock: @convention(block) (AnyObject, NSEvent) -> Void = { _, _ in }
}

/// Reads `NSApp.currentEvent` without entering a Swift actor.
/// `MainActor.assumeIsolated` is what traps during AppKit hit testing.
private enum HostingEventProbe {
    private nonisolated(unsafe) static var appPointer: UnsafeMutableRawPointer?
    private nonisolated(unsafe) static let msgSend: UnsafeMutableRawPointer = {
        // RTLD_DEFAULT is ((void *) -2). Darwin doesn't export the macro to Swift.
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "objc_msgSend") else {
            fatalError("objc_msgSend missing")
        }
        return symbol
    }()

    @MainActor
    static func captureApplication() {
        appPointer = Unmanaged.passUnretained(NSApplication.shared).toOpaque()
    }

    static func currentEventTypeRawValue() -> UInt? {
        guard let app = appPointer else { return nil }
        // Raw pointers so ARC does not retain the event AppKit owns.
        typealias RawMsg = @convention(c) (UnsafeMutableRawPointer, Selector) -> UnsafeMutableRawPointer?
        typealias TypeMsg = @convention(c) (UnsafeMutableRawPointer, Selector) -> UInt
        let rawMsg = unsafeBitCast(msgSend, to: RawMsg.self)
        let typeMsg = unsafeBitCast(msgSend, to: TypeMsg.self)
        guard let event = rawMsg(app, sel_registerName("currentEvent")) else { return nil }
        return typeMsg(event, sel_registerName("type"))
    }
}
