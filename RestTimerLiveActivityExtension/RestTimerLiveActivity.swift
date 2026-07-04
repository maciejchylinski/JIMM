import ActivityKit
import SwiftUI
import WidgetKit

private let resumeActiveWorkoutURL = URL(string: "mch.jim://active-workout")!

// MARK: - Palette (extension target does not compile app `UITheme`.)

private enum RestTimerLiveActivityPalette {
    static let accent = Color(UIColor.systemOrange)
    /// Icon only: slightly softer than full `systemOrange`.
    static let accentIcon = Color(UIColor.systemOrange.withAlphaComponent(0.88))
}

private enum RestTimerLiveActivityChrome {
    static let restIcon = "timer"
    static let workoutIcon = "clock"
}

/// Dynamic Island only: `Text(..., style: .timer)` is updated by the system inside Live Activities (including background).
private struct DynamicIslandLiveCountUpTimer: View {
    let start: Date
    var font: Font
    var minimumScaleFactor: CGFloat = 0.75
    /// Clamps layout width so `.timer` does not expand the Dynamic Island; pass `nil` for no cap.
    var layoutMaxWidth: CGFloat?
    var layoutAlignment: Alignment = .center

    var body: some View {
        let text = Text(start, style: .timer)
            .font(font)
            .monospacedDigit()
            .foregroundStyle(.primary)
            .minimumScaleFactor(minimumScaleFactor)
            .lineLimit(1)

        if let layoutMaxWidth {
            text
                .frame(maxWidth: layoutMaxWidth, alignment: layoutAlignment)
        } else {
            text
        }
    }
}

private struct WorkoutLiveActivityMiniCard: View {
    let state: RestTimerActivityAttributes.ContentState
    var exerciseTitleFont: Font = .headline.weight(.semibold)
    var timerValueFont: Font = .system(size: 24, weight: .semibold, design: .default)
    var labelFont: Font = .caption2.weight(.semibold)
    var setSummaryFont: Font = .subheadline.weight(.medium)
    var columnSpacing: CGFloat = 18

    private var displayExerciseTitle: String {
        let trimmed = state.exerciseName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Current exercise" }
        return trimmed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(displayExerciseTitle)
                .font(exerciseTitleFont)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.82)

            HStack(alignment: .firstTextBaseline, spacing: columnSpacing) {
                timerBlock(
                    label: "Rest",
                    iconName: RestTimerLiveActivityChrome.restIcon,
                    date: state.restStartDate,
                    accentIcon: true
                )
                timerBlock(
                    label: "Workout",
                    iconName: RestTimerLiveActivityChrome.workoutIcon,
                    date: state.workoutSessionStartDate,
                    accentIcon: false
                )
            }

            if !state.setSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(state.setSummary)
                    .font(setSummaryFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func timerBlock(label: String, iconName: String, date: Date, accentIcon: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Image(systemName: iconName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(accentIcon ? RestTimerLiveActivityPalette.accentIcon : Color.secondary)
                Text(label)
                    .font(labelFont)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.35)
            }
            Text(date, style: .timer)
                .font(timerValueFont)
                .monospacedDigit()
                .foregroundStyle(.primary)
                .minimumScaleFactor(0.65)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct RestTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestTimerActivityAttributes.self) { context in
            WorkoutLiveActivityMiniCard(state: context.state)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .widgetURL(resumeActiveWorkoutURL)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    dynamicIslandExpandedContent(state: context.state)
                }
            } compactLeading: {
                compactLeadingRestDuration(restStart: context.state.restStartDate)
            } compactTrailing: {
                compactTrailingIcon
            } minimal: {
                minimalIslandContent(restStart: context.state.restStartDate)
            }
            .widgetURL(resumeActiveWorkoutURL)
        }
    }

    private var compactTrailingIcon: some View {
        Image(systemName: RestTimerLiveActivityChrome.restIcon)
            .font(.system(size: DynamicIslandCompactStyle.leadingIconSize, weight: .semibold))
            .foregroundStyle(RestTimerLiveActivityPalette.accentIcon)
            .frame(maxHeight: .infinity, alignment: .center)
    }

    private func compactLeadingRestDuration(restStart: Date) -> some View {
        DynamicIslandLiveCountUpTimer(
            start: restStart,
            font: .system(size: DynamicIslandCompactStyle.trailingTimerSize, weight: .semibold, design: .monospaced),
            minimumScaleFactor: 0.5,
            layoutMaxWidth: DynamicIslandCompactStyle.compactTrailingTimerMaxWidth,
            layoutAlignment: .leading
        )
    }

    private func minimalIslandContent(restStart: Date) -> some View {
        DynamicIslandLiveCountUpTimer(
            start: restStart,
            font: .system(size: DynamicIslandCompactStyle.minimalTimerSize, weight: .semibold, design: .monospaced),
            minimumScaleFactor: 0.5,
            layoutMaxWidth: DynamicIslandCompactStyle.minimalTimerMaxWidth,
            layoutAlignment: .center
        )
    }

    /// Compact expanded island: rest focus; workout row only when horizontal space allows.
    private func dynamicIslandExpandedContent(state: RestTimerActivityAttributes.ContentState) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                dynamicIslandExpandedRestColumn(restStart: state.restStartDate)
                dynamicIslandExpandedWorkoutColumn(workoutStart: state.workoutSessionStartDate)
            }
            dynamicIslandExpandedRestColumn(restStart: state.restStartDate)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    private func dynamicIslandExpandedRestColumn(restStart: Date) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Rest")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            DynamicIslandLiveCountUpTimer(
                start: restStart,
                font: .system(size: 20, weight: .semibold, design: .monospaced),
                minimumScaleFactor: 0.55,
                layoutMaxWidth: DynamicIslandCompactStyle.expandedRestTimerMaxWidth,
                layoutAlignment: .leading
            )
        }
    }

    private func dynamicIslandExpandedWorkoutColumn(workoutStart: Date) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Workout")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            DynamicIslandLiveCountUpTimer(
                start: workoutStart,
                font: .system(size: 15, weight: .semibold, design: .monospaced),
                minimumScaleFactor: 0.55,
                layoutMaxWidth: DynamicIslandCompactStyle.expandedWorkoutTimerMaxWidth,
                layoutAlignment: .leading
            )
        }
    }
}

/// Typography tuned for Dynamic Island compact / minimal.
private enum DynamicIslandCompactStyle {
    static let leadingIconSize: CGFloat = 10
    static let trailingTimerSize: CGFloat = 11
    static let minimalTimerSize: CGFloat = 10
    /// Keeps `Text(..., style: .timer)` from widening the compact trailing capsule.
    static let compactTrailingTimerMaxWidth: CGFloat = 50
    /// Slightly tighter slot for minimal island timer text.
    static let minimalTimerMaxWidth: CGFloat = 44
    static let expandedRestTimerMaxWidth: CGFloat = 88
    static let expandedWorkoutTimerMaxWidth: CGFloat = 72
}