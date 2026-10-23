import SwiftUI

/// 沒有光達就停在這裡。不開相機，也不會因為不支援的設定而崩潰。
struct UnsupportedDeviceView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: "iphone")
                        .font(.system(size: 44))
                        .foregroundStyle(Theme.safe)
                        .accessibilityHidden(true)
                    Text(L10n.unsupportedTitle)
                        .font(.title.weight(.bold))
                        .foregroundStyle(Theme.text)
                    Text(L10n.unsupportedBody)
                        .font(.body)
                        .foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 10) {
                        capabilityRow(L10n.unsupportedSceneDepth, supported: model.supportsSceneDepth)
                        capabilityRow(L10n.unsupportedMesh, supported: model.supportsMesh)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                    Text(L10n.unsupportedIsland)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button(L10n.permissionOpenPrivacy) {
                        model.showSettings = true
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.safe)
                }
                .padding(24)
            }
        }
    }

    private func capabilityRow(_ title: String, supported: Bool) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(Theme.text)
            Spacer()
            Text(supported ? L10n.unsupportedYes : L10n.unsupportedNo)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(supported ? Theme.safe : Color(red: 1, green: 0.45, blue: 0.42))
        }
        .accessibilityElement(children: .combine)
    }
}
