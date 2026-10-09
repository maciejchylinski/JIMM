//
//  ContentView.swift
//  JIMM
//
//  Created by Maciek on 26/03/2026.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    private enum Tab: Hashable {
        case home
        case workout
        case settings
    }

    @Query(sort: \WorkoutSession.sessionDate, order: .reverse)
    private var allSessionsBySessionDate: [WorkoutSession]
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var workoutSessionPresentationState: WorkoutSessionPresentationState
    @State private var selectedTab: Tab = .home
    @State private var pendingResumeSession: WorkoutSession?

    private var activeUnfinishedSession: WorkoutSession? {
        allSessionsBySessionDate.first(where: { $0.completedAt == nil })
    }

    private var activeWorkoutMiniBarScrollInset: CGFloat {
        guard activeUnfinishedSession != nil,
              !workoutSessionPresentationState.isWorkoutSessionViewPresented else {
            return 0
        }
        return ActiveWorkoutMiniBarLayout.scrollContentInset
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                HomeView()
            }
            .tag(Tab.home)
            .tabItem {
                Label("Home", systemImage: "house")
            }

            NavigationStack {
                WorkoutView(externalResumeSession: $pendingResumeSession)
            }
            .tag(Tab.workout)
            .tabItem {
                Label("Workout", systemImage: "figure.run")
            }

            NavigationStack {
                SettingsView()
            }
            .tag(Tab.settings)
            .tabItem {
                Label("Settings", systemImage: "gear")
            }
        }
        .environment(\.activeWorkoutMiniBarScrollInset, activeWorkoutMiniBarScrollInset)
        .tint(UITheme.accent)
        // Tab bar fill matches `WorkoutSessionView` bottom accessory (`UITheme.cardBackground` + shared chrome tokens).
        .toolbarBackground(UITheme.cardBackground, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let active = activeUnfinishedSession, !workoutSessionPresentationState.isWorkoutSessionViewPresented {
                ActiveWorkoutMiniCard(
                    session: active,
                    workoutTitle: workoutTitle(for: active),
                    currentExerciseName: currentExerciseName(for: active),
                    onTap: { openActiveWorkout(active) }
                )
                .padding(.horizontal, UITheme.spaceL)
                .padding(.top, UITheme.spaceS)
                // Keep the mini card clearly above the tab bar area.
                .padding(.bottom, ActiveWorkoutMiniBarLayout.tabBarClearance + UITheme.spaceS)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .jimOpenActiveWorkoutSession)) { notification in
            guard let session = notification.object as? WorkoutSession else { return }
            openActiveWorkout(session)
        }
        .task {
            try? ActiveWorkoutSession.pruneDuplicateUnfinishedSessions(in: modelContext)
        }
        .alert("Active workout", isPresented: $workoutSessionPresentationState.showActiveWorkoutBlockingAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("You have an active workout. Finish it before starting a new workout.")
        }
    }

    private func openActiveWorkout(_ session: WorkoutSession) {
        selectedTab = .workout
        // Reset first so repeated taps always retrigger resume in WorkoutView.
        pendingResumeSession = nil
        DispatchQueue.main.async {
            pendingResumeSession = session
        }
    }

    private func workoutTitle(for session: WorkoutSession) -> String {
        let customName = session.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !customName.isEmpty {
            return customName
        }
        let ordered = session.sessionExercises.sorted { $0.exerciseOrder < $1.exerciseOrder }
        guard let firstName = ordered.first?.displayName, !firstName.isEmpty else {
            return "Workout"
        }
        if ordered.count == 1 {
            return firstName
        }
        return "\(firstName) +\(ordered.count - 1)"
    }

    private func currentExerciseName(for session: WorkoutSession) -> String {
        if workoutSessionPresentationState.activeRestSessionID == session.persistentModelID,
           workoutSessionPresentationState.activeRestStartDate != nil,
           let sourceExerciseID = workoutSessionPresentationState.activeRestSourceSessionExerciseID {
            return miniBarExerciseNameDuringRest(
                for: session,
                sourceExerciseID: sourceExerciseID,
                sourceSetOrder: workoutSessionPresentationState.activeRestSourceSetOrder
            )
        }
        return miniBarExerciseNameWhenNotResting(for: session)
    }

    /// During rest: next set in same exercise, else next exercise, else the just-finished exercise.
    private func miniBarExerciseNameDuringRest(
        for session: WorkoutSession,
        sourceExerciseID: PersistentIdentifier,
        sourceSetOrder: Int?
    ) -> String {
        let orderedExercises = session.sessionExercises.sorted { $0.exerciseOrder < $1.exerciseOrder }
        guard let sourceExerciseIndex = orderedExercises.firstIndex(where: { $0.persistentModelID == sourceExerciseID }) else {
            return miniBarExerciseNameWhenNotResting(for: session)
        }
        let sourceExercise = orderedExercises[sourceExerciseIndex]
        let exerciseName = sourceExercise.displayName.trimmingCharacters(in: .whitespacesAndNewlines)

        if let sourceSetOrder {
            let sortedSets = sourceExercise.sets.sorted { $0.setOrder < $1.setOrder }
            if let sourceSetIndex = sortedSets.firstIndex(where: { $0.setOrder == sourceSetOrder }),
               sourceSetIndex + 1 < sortedSets.count {
                let nextSetOrder = sortedSets[sourceSetIndex + 1].setOrder
                if !exerciseName.isEmpty {
                    return "\(exerciseName) · Set \(nextSetOrder)"
                }
            }
        }

        if sourceExerciseIndex + 1 < orderedExercises.count {
            let nextName = orderedExercises[sourceExerciseIndex + 1].displayName
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !nextName.isEmpty {
                return nextName
            }
        }

        if !exerciseName.isEmpty {
            return exerciseName
        }
        return miniBarExerciseNameWhenNotResting(for: session)
    }

    /// Outside rest: first exercise by `exerciseOrder`, else workout name / "Active Workout".
    private func miniBarExerciseNameWhenNotResting(for session: WorkoutSession) -> String {
        let ordered = session.sessionExercises.sorted { $0.exerciseOrder < $1.exerciseOrder }
        if let name = ordered.first?.displayName.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return name
        }
        let customName = session.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !customName.isEmpty {
            return customName
        }
        return "Active Workout"
    }

}

private struct ActiveWorkoutMiniCard: View {
    @EnvironmentObject private var workoutSessionPresentationState: WorkoutSessionPresentationState
    let session: WorkoutSession
    let workoutTitle: String
    let currentExerciseName: String
    let onTap: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Button(action: onTap) {
                HStack(alignment: .center, spacing: UITheme.spaceS) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(currentExerciseName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(workoutTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer(minLength: 0)

                    HStack(spacing: 6) {
                        metricColumn(
                            label: "Rest",
                            value: liveRestTimerText(now: context.date),
                            systemImage: "pause.circle"
                        )
                        metricColumn(
                            label: "Workout",
                            value: totalWorkoutText(now: context.date),
                            systemImage: "timer"
                        )
                    }

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 2)
                }
                .padding(.horizontal, UITheme.spaceL)
                .padding(.vertical, 13)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(UITheme.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(UITheme.stroke, lineWidth: 0.7)
            )
        }
    }

    private func totalWorkoutText(now: Date) -> String {
        let totalSeconds = max(0, Int(now.timeIntervalSince(session.sessionDate)))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func metricColumn(label: String, value: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
            Text(value)
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(Color(uiColor: .label))
                .lineLimit(1)
        }
        .frame(width: 82, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: UITheme.cornerRadiusSmall, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: UITheme.cornerRadiusSmall, style: .continuous)
                        .stroke(UITheme.stroke, lineWidth: 0.6)
                )
        )
    }

    private func liveRestTimerText(now: Date) -> String {
        workoutSessionPresentationState.restTimerText(
            for: session.persistentModelID,
            now: now
        )
    }
}

#Preview {
    ContentView()
        .environmentObject(WorkoutSessionPresentationState())
}
