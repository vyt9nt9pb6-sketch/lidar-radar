import SwiftUI

/// 第一次打開必須同意，否則不開相機、不定位、不起動態島。
struct ConsentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var agreed = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.appName)
                            .font(.largeTitle.weight(.bold))
                            .foregroundStyle(Theme.text)
                        Text(L10n.consentSubtitle)
                            .font(.body)
                            .foregroundStyle(Theme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        Text(L10n.consentPrinciples)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Theme.text)
                        ForEach(Principle.all) { principle in
                            PrincipleRow(principle: principle)
                        }
                    }
                    .padding(16)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                    Text(L10n.consentDisclaimer)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Toggle(isOn: $agreed) {
                        Text(L10n.consentToggle)
                            .font(.body.weight(.medium))
                            .foregroundStyle(Theme.text)
                    }
                    .tint(Theme.safe)

                    Button {
                        model.acceptConsent()
                    } label: {
                        Text(L10n.consentAgree)
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.safe)
                    .foregroundStyle(Theme.background)
                    .disabled(!agreed)
                    .opacity(agreed ? 1 : 0.45)

                    Text(L10n.consentLater)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondary)
                }
                .padding(24)
            }
        }
    }
}
