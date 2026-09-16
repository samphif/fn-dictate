import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    /// Captured for SwiftUI-managed windows (e.g. Setup).
    var openWindow: OpenWindowAction?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Regular policy → Dock + Cmd+Tab. Menu bar extra still works.
        NSApp.setActivationPolicy(.regular)
        model.presentOnboardingHandler = { [weak self] in
            self?.presentOnboarding()
        }
        model.bootstrap()
    }

    /// TCC grants often only stick after Settings → return (or a full relaunch).
    func applicationDidBecomeActive(_ notification: Notification) {
        model.permissions.refresh()
        if model.permissions.allRequiredGranted {
            model.completeSetup()
            model.startHotkeysIfPossible()
        }
    }

    /// Dock icon / Spotlight / Cmd+Tab re-activation.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        presentLibrary()
        // false → don't let AppKit focus the MenuBarExtra chrome instead.
        return false
    }

    func presentLibrary() {
        model.presentLibraryWindow()
    }

    func presentOnboarding() {
        model.showOnboarding = true
        NSApp.activate(ignoringOtherApps: true)
        if let openWindow {
            openWindow(id: "onboarding")
        }
    }
}

/// Keeps a live openWindow action for scenes that still use SwiftUI Window.
private struct WindowActionRegistrar: View {
    @Environment(\.openWindow) private var openWindow
    var appDelegate: AppDelegate

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onAppear {
                appDelegate.openWindow = openWindow
            }
    }
}

@main
struct FnDictateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(model: appDelegate.model, appDelegate: appDelegate)
        } label: {
            Label("Fn Dictate", systemImage: "waveform.circle.fill")
                .background(WindowActionRegistrar(appDelegate: appDelegate))
        }
        .menuBarExtraStyle(.window)

        Window("Setup", id: "onboarding") {
            OnboardingView(model: appDelegate.model)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
    }
}
