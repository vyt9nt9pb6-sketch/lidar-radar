import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch model.phase {
            case .needsConsent:
                ConsentView()
            case .checking:
                checking
            case .unsupported:
                UnsupportedDeviceView()
            case .needsCamera:
                PermissionView()
            case .monitoring:
                RadarView()
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { model.onAppear() }
        .onChange(of: scenePhase) { phase in
            model.handle(scenePhase: phase)
        }
        .sheet(isPresented: $model.showSettings) {
            SettingsView(settings: model.settings)
                .environmentObject(model)
        }
    }

    private var checking: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                    .tint(Theme.safe)
                Text(L10n.checking)
                    .foregroundStyle(Theme.secondary)
            }
        }
    }
}

@main
struct LidarRadarApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
        }
    }
}
