import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmReset = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(L10n.settingsLowPower, isOn: $settings.lowPower)
                    Toggle(L10n.settingsSound, isOn: $settings.soundEnabled)
                    Toggle(L10n.settingsIgnoreSilent, isOn: $settings.ignoreSilentSwitch)
                        .disabled(!settings.soundEnabled)
                    Toggle(L10n.settingsHaptics, isOn: $settings.hapticsEnabled)
                    Button(L10n.settingsPreview) {
                        model.playPreviewAlert()
                    }
                } header: {
                    Text(L10n.settingsMonitoring)
                } footer: {
                    Text(L10n.settingsMonitoringFooter)
                }

                Section {
                    Button(L10n.settingsRestart) {
                        model.restartLiveActivity()
                    }
                } header: {
                    Text(L10n.settingsIsland)
                } footer: {
                    Text(L10n.settingsIslandFooter)
                }

                Section {
                    Toggle(L10n.settingsPip, isOn: $settings.pictureInPictureEnabled)
                } footer: {
                    Text(model.multitaskingCameraSupported ? L10n.settingsPipFooterSupported : L10n.settingsPipFooterUnsupported)
                }

                Section {
                    ForEach(Principle.all) { principle in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(principle.title)
                            Text(principle.detail)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text(L10n.consentPrinciples)
                }

                Section {
                    Button(L10n.settingsSystemSettings) {
                        model.openSystemSettings()
                    }
                    Button(L10n.settingsRevoke, role: .destructive) {
                        confirmReset = true
                    }
                } header: {
                    Text(L10n.settingsPrivacy)
                } footer: {
                    Text(L10n.settingsPrivacyFooter)
                }

                Section {
                    Text(L10n.appName + " " + version)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(L10n.settingsTitle)
            .navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.dark)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.settingsDone) { dismiss() }
                }
            }
            .confirmationDialog(
                L10n.settingsRevokeTitle,
                isPresented: $confirmReset,
                titleVisibility: .visible
            ) {
                Button(L10n.settingsRevokeConfirm, role: .destructive) {
                    model.revokeConsent()
                }
                Button(L10n.settingsCancel, role: .cancel) {}
            } message: {
                Text(L10n.settingsRevokeMessage)
            }
        }
    }

    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return L10n.settingsVersion(short, build)
    }
}
