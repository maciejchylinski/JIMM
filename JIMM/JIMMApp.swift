//
//  JIMMApp.swift
//  JIMM
//
//  Created by Maciek on 26/03/2026.
//

import SwiftData
import SwiftUI

@main
struct JIMMApp: App {
    @StateObject private var workoutSessionPresentationState = WorkoutSessionPresentationState()
    @StateObject private var restTimerLiveActivityManager = RestTimerLiveActivityManager()
    @AppStorage("settings.appearance") private var appearanceRawValue: String = "system"
    @AppStorage("onboarding.hasCompleted") private var hasCompletedOnboarding = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var isLaunchLoadingVisible = true

    private let container: ModelContainer = {
        do {
            let schema = Schema([
                Exercise.self,
                WorkoutSession.self,
                WorkoutSessionExercise.self,
                WorkoutSet.self,
                WorkoutPlan.self,
                WorkoutPlanExercise.self
            ])
            let config = ModelConfiguration(schema: schema)
            let container = try ModelContainer(for: schema, configurations: [config])
            try ExerciseCatalog.seedIfNeeded(context: container.mainContext)
            try ActiveWorkoutSession.pruneDuplicateUnfinishedSessions(in: container.mainContext)
            return container
        } catch {
            fatalError("Failed to initialize model container: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ZStack {
                if isLaunchLoadingVisible {
                    LaunchLoadingView()
                        .transition(.opacity)
                } else {
                    rootContent
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.35), value: isLaunchLoadingVisible)
            .task {
                await dismissLaunchLoadingIfNeeded()
                reconcileRestTimerLiveActivity()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    reconcileRestTimerLiveActivity()
                }
            }
        }
        .modelContainer(container)
    }

    @ViewBuilder
    private var rootContent: some View {
        if hasCompletedOnboarding {
            mainAppContent
        } else {
            OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
                .preferredColorScheme(preferredColorScheme)
        }
    }

    @MainActor
    private func dismissLaunchLoadingIfNeeded() async {
        try? await Task.sleep(for: .milliseconds(600))
        isLaunchLoadingVisible = false
    }

    private var mainAppContent: some View {
        ContentView()
            .environmentObject(workoutSessionPresentationState)
            .environmentObject(restTimerLiveActivityManager)
            .preferredColorScheme(preferredColorScheme)
            .onChange(of: workoutSessionPresentationState.activeRestStartDate) { _, newValue in
                if newValue == nil {
                    restTimerLiveActivityManager.sync(payload: nil)
                }
            }
            .onOpenURL { url in
                guard url.scheme == "mch.jim", url.host == "active-workout" else { return }
                Task { @MainActor in
                    if let session = try? ActiveWorkoutSession.canonicalUnfinishedSessionAfterCleanup(in: container.mainContext) {
                        NotificationCenter.default.post(name: .jimOpenActiveWorkoutSession, object: session)
                    }
                }
            }
    }

    @MainActor
    private func reconcileRestTimerLiveActivity() {
        restTimerLiveActivityManager.reconcile(payload: currentRestTimerLiveActivityPayload())
    }

    @MainActor
    private func currentRestTimerLiveActivityPayload() -> RestTimerLiveActivityPayload? {
        guard
            let sessionID = workoutSessionPresentationState.activeRestSessionID,
            let restStartDate = workoutSessionPresentationState.activeRestStartDate,
            let session = activeUnfinishedSession(matching: sessionID)
        else {
            workoutSessionPresentationState.clearRestTimer()
            return nil
        }

        return RestTimerLiveActivityPayload(
            restStartDate: restStartDate,
            workoutSessionStartDate: session.sessionDate,
            exerciseName: liveActivityExerciseName(fallbackSession: session),
            setSummary: workoutSessionPresentationState.liveActivitySetSummary
        )
    }

    @MainActor
    private func activeUnfinishedSession(matching sessionID: PersistentIdentifier) -> WorkoutSession? {
        var descriptor = FetchDescriptor<WorkoutSession>(
            sortBy: [SortDescriptor(\WorkoutSession.sessionDate, order: .reverse)]
        )
        descriptor.fetchLimit = 20
        let sessions = (try? container.mainContext.fetch(descriptor)) ?? []
        return sessions.first {
            $0.persistentModelID == sessionID && $0.completedAt == nil
        }
    }

    private func liveActivityExerciseName(fallbackSession session: WorkoutSession) -> String {
        let liveName = workoutSessionPresentationState.liveActivityExerciseName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !liveName.isEmpty {
            return liveName
        }
        let orderedExercises = session.sessionExercises.sorted { $0.exerciseOrder < $1.exerciseOrder }
        if let exerciseName = orderedExercises.first?.displayName.trimmingCharacters(in: .whitespacesAndNewlines),
           !exerciseName.isEmpty {
            return exerciseName
        }
        let workoutName = session.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return workoutName.isEmpty ? "Active Workout" : workoutName
    }

    private var preferredColorScheme: ColorScheme? {
        switch appearanceRawValue {
        case "light":
            return .light
        case "dark":
            return .dark
        default:
            return nil
        }
    }
}
