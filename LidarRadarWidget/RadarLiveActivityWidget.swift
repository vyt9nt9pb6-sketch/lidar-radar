import ActivityKit
import SwiftUI
import WidgetKit

/// 鎖定畫面與動態島。這個 target 不開相機，只把主 App 送來的狀態畫出來。
struct RadarLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RadarAttributes.self) { context in
            LockScreenRadarView(state: context.state, startedAt: context.attributes.startedAt)
                .activityBackgroundTint(Color(red: 0.05, green: 0.06, blue: 0.08))
                .activitySystemActionForegroundColor(Color.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.state.displayLevel.emoji)
                        .font(.title2)
                        .accessibilityLabel(context.state.isPaused ? L10n.radarPaused : context.state.level.label)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(context.state.isPaused ? "—" : context.state.distanceLabel)
                            .font(.title2.weight(.bold).monospacedDigit())
                            .foregroundStyle(context.state.displayLevel.color)
                        Text(context.state.isPaused ? L10n.radarPaused : L10n.widgetMeters)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.isPaused ? L10n.radarPaused : context.state.level.label)
                        .font(.headline)
                        .foregroundStyle(context.state.displayLevel.color)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.statusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        if !context.state.isPaused {
                            Text(context.attributes.startedAt, style: .timer)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .accessibilityLabel(L10n.widgetElapsed)
                        }
                    }
                }
            } compactLeading: {
                Text(context.state.displayLevel.emoji)
                    .accessibilityLabel(context.state.isPaused ? L10n.radarPaused : context.state.level.label)
            } compactTrailing: {
                Text(context.state.compactDistance)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(context.state.displayLevel.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } minimal: {
                Text(context.state.displayLevel.emoji)
                    .accessibilityLabel(context.state.isPaused ? L10n.radarPaused : context.state.level.label)
            }
            .keylineTint(context.state.displayLevel.color)
        }
    }
}

/// 鎖定畫面，以及沒有動態島的 iPhone 上那條橫幅。
struct LockScreenRadarView: View {
    let state: RadarAttributes.ContentState
    let startedAt: Date

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(state.displayLevel.color)
                .frame(width: 6)
            VStack(alignment: .leading, spacing: 4) {
                Text(state.isPaused ? L10n.radarPaused : "\(state.displayLevel.emoji) \(state.level.label)")
                    .font(.headline)
                    .foregroundStyle(state.displayLevel.color)
                Text(state.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if state.isPaused {
                    Text(state.updatedAt, style: .time)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    Text(startedAt, style: .timer)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 0) {
                Text(state.isPaused ? "—" : state.distanceLabel)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(L10n.widgetMeters)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .accessibilityElement(children: .combine)
    }
}

@main
struct LidarRadarWidgetBundle: WidgetBundle {
    var body: some Widget {
        RadarLiveActivityWidget()
    }
}
