import SwiftUI

@main
struct FnDictateApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra("Fn Dictate", systemImage: "waveform.circle.fill") {
            MenuBarView(model: model)
        }
        .menuBarExtraStyle(.window)

        Window("Setup", id: "onboarding") {
            OnboardingView(model: model)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)

        Window("Meeting Notes", id: "notes") {
            NotesLibraryView(model: model)
        }
        .defaultSize(width: 900, height: 560)
        .defaultLaunchBehavior(.suppressed)
    }
}
