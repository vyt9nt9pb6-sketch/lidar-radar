import SwiftUI

/// 相機被拒絕時的說明。光達走的是相機權限，沒有它就沒有深度。
struct PermissionView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(Theme.safe)
                    .accessibilityHidden(true)
                Text(L10n.permissionTitle)
                    .font(.title.weight(.bold))
                    .foregroundStyle(Theme.text)
                Text(L10n.permissionBody)
                    .font(.body)
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    model.openSystemSettings()
                } label: {
                    Text(L10n.permissionOpenSettings)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.safe)
                .foregroundStyle(Theme.background)
                Button(L10n.permissionOpenPrivacy) {
                    model.showSettings = true
                }
                .buttonStyle(.bordered)
                .tint(Theme.text)
                Spacer()
            }
            .padding(24)
        }
    }
}
