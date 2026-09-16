import SwiftUI

struct OnboardingView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Welcome to Fn Dictate")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                Text("Hold Fn to dictate into Cursor, Edge, or any app. Meetings get local summaries.")
                    .foregroundStyle(.secondary)
            }

            permissionRow(
                title: "Microphone",
                granted: model.permissions.microphoneGranted,
                actionTitle: "Allow",
                action: {
                    Task { await model.permissions.requestMicrophone() }
                },
                settings: { model.permissions.openMicrophoneSettings() }
            )

            permissionRow(
                title: "Accessibility",
                granted: model.permissions.accessibilityTrusted,
                actionTitle: "Prompt",
                action: { model.permissions.promptAccessibility() },
                settings: { model.permissions.openAccessibilitySettings() }
            )

            permissionRow(
                title: "Input Monitoring",
                granted: model.permissions.inputMonitoringTrusted,
                actionTitle: "Prompt",
                action: { model.permissions.promptInputMonitoring() },
                settings: { model.permissions.openInputMonitoringSettings() }
            )

            GroupBox("Avoid conflicts") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("• Quit Wispr Flow if it’s installed")
                    Text("• Remove BetterTouchTool remaps of the Fn / Globe key")
                    Text("• Turn off macOS Dictation’s Fn shortcut in Keyboard settings")
                }
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Spacer()
                Button("Continue") {
                    model.refreshPermissionsAndMaybeStart()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!model.permissions.microphoneGranted || !model.permissions.accessibilityTrusted)
            }
        }
        .padding(28)
        .frame(width: 480)
        .onAppear { model.permissions.refresh() }
    }

    private func permissionRow(
        title: String,
        granted: Bool,
        actionTitle: String,
        action: @escaping () -> Void,
        settings: @escaping () -> Void
    ) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(granted ? .green : .secondary)
            Text(title)
            Spacer()
            if !granted {
                Button(actionTitle, action: action)
                Button("Settings", action: settings)
            }
        }
    }
}
