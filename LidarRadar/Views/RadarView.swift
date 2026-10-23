import SwiftUI

struct RadarView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 96
    @State private var pulse = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Theme.background.ignoresSafeArea()
                RadialGradient(
                    colors: [model.level.color.opacity(model.isInterrupted ? 0.08 : 0.28), Theme.background],
                    center: .center,
                    startRadius: 20,
                    endRadius: 360
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 22) {
                        header
                        hero
                        statusBlock
                        PipExperimentHost(settings: model.settings, pip: model.pictureInPicture)
                        footer
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity, minHeight: geo.size.height)
                }
            }
        }
        .overlay(edgeGlow)
        .onAppear {
            guard !reduceMotion else { return }
            pulse = true
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.appName)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Theme.text)
                HStack(spacing: 8) {
                    Circle()
                        .fill(model.isInterrupted ? Theme.secondary : model.level.color)
                        .frame(width: 9, height: 9)
                        .opacity(model.isInterrupted ? 1 : (pulse ? 1 : 0.35))
                        .animation(
                            reduceMotion || model.isInterrupted
                                ? nil
                                : .easeInOut(duration: model.level == .danger ? 0.45 : 1.2).repeatForever(autoreverses: true),
                            value: pulse
                        )
                    Text(model.isInterrupted ? L10n.radarPaused : L10n.radarMonitoring)
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondary)
                }
            }
            Spacer()
            Button {
                model.showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.title3)
                    .foregroundStyle(Theme.text)
                    .frame(width: 44, height: 44)
                    .background(Theme.card, in: Circle())
            }
            .accessibilityLabel(L10n.radarSettings)
        }
    }

    private var hero: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(model.level.color.opacity(0.18), lineWidth: 16)
                    .frame(width: 250, height: 250)
                Circle()
                    .stroke(model.level.color.opacity(0.45), lineWidth: 2)
                    .frame(width: 196, height: 196)
                VStack(spacing: 0) {
                    Text(model.distanceLabel)
                        .font(.system(size: heroSize, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.text)
                        .minimumScaleFactor(0.4)
                        .lineLimit(1)
                        .opacity(model.isInterrupted ? 0.4 : 1)
                    Text(L10n.radarMeters)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(Theme.secondary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(model.accessibilityDistance)

            Text(model.level.emoji + " " + (model.isInterrupted ? L10n.radarPaused : model.level.label))
                .font(.title3.weight(.semibold))
                .foregroundStyle(model.isInterrupted ? Theme.secondary : model.level.color)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Theme.card, in: Capsule())
        }
        .frame(maxWidth: .infinity)
    }

    private var statusBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.isInterrupted {
                banner(
                    title: L10n.radarPausedTitle,
                    message: L10n.radarPausedMessage
                )
            }
            if let failure = model.failureMessage {
                banner(title: L10n.radarFailureTitle, message: failure)
                Button(L10n.radarRetry) {
                    model.retrySession()
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.safe)
                .foregroundStyle(Theme.background)
            }
            if let hint = model.trackingHint, !model.isInterrupted {
                Text(hint)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondary)
            }
            Text(model.liveActivityCaption)
                .font(.subheadline)
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !model.isInterrupted && model.isLowPower {
                Text(model.lowPowerReason)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(DangerLevel.warning.color)
            } else if !model.isInterrupted && model.measuredFPS > 0 {
                Text(L10n.radarFPS(model.measuredFPS))
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)
            } else if !model.isInterrupted {
                Text(L10n.radarStarting)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.radarAim)
                .font(.footnote)
                .foregroundStyle(Theme.secondary)
            Text(L10n.radarThresholds)
                .font(.footnote)
                .foregroundStyle(Theme.secondary)
            Text(L10n.principlesLine)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.text.opacity(0.85))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 12)
    }

    private var edgeGlow: some View {
        Rectangle()
            .stroke(model.level.color.opacity(model.isInterrupted ? 0 : (model.level == .safe ? 0.25 : 0.85)), lineWidth: model.level == .danger ? 8 : 4)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func banner(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.text)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// 開關打開時，這張卡片必須留在畫面上，系統才願意把它帶成子母畫面。
/// 自己觀察設定和子母畫面狀態，主畫面不用為此再發一次通知。
private struct PipExperimentHost: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var pip: DistancePictureInPicture

    var body: some View {
        if settings.pictureInPictureEnabled {
            VStack(alignment: .leading, spacing: 8) {
                PictureInPictureInlineView(layer: pip.displayLayer)
                    .frame(height: 140)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityLabel(L10n.pipInlineCaption)
                Text(L10n.pipInlineCaption)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.text)
                if !pip.statusText.isEmpty {
                    Text(pip.statusText)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct RadarView_Previews: PreviewProvider {
    static var previews: some View {
        RadarView()
            .environmentObject(AppModel.preview(distance: 0.6, level: .danger))
            .preferredColorScheme(.dark)
    }
}
