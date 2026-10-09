import Foundation
import Combine
import SwiftData

@MainActor
final class WorkoutSessionPresentationState: ObservableObject {
    /// Active `WorkoutSessionView` instances (by session id). Set semantics allow pre-registering
    /// before navigation so tab chrome / mini UI update immediately without double-counting.
    @Published private(set) var registeredWorkoutSessionIDs: Set<PersistentIdentifier> = []
    @Published private(set) var activeRestSessionID: PersistentIdentifier?
    @Published private(set) var activeRestStartDate: Date?
    /// Exercise whose set just finished when rest started (mini bar “up next” during rest).
    @Published private(set) var activeRestSourceSessionExerciseID: PersistentIdentifier?
    /// `setOrder` of the set that was just confirmed when rest started.
    @Published private(set) var activeRestSourceSetOrder: Int?
    /// Strings for Live Activity mini-card while rest is active (cleared with rest timer).
    @Published private(set) var liveActivityExerciseName: String = ""
    @Published private(set) var liveActivitySetSummary: String = ""
    @Published var showActiveWorkoutBlockingAlert = false

    var isWorkoutSessionViewPresented: Bool {
        !registeredWorkoutSessionIDs.isEmpty
    }

    /// Call before pushing a `WorkoutSessionView`, and from `WorkoutSessionView.onAppear` (idempotent).
    func registerWorkoutSessionView(for sessionID: PersistentIdentifier) {
        registeredWorkoutSessionIDs.insert(sessionID)
    }

    /// Call from `WorkoutSessionView.onDisappear` and when cancelling a push without a view appearing.
    func unregisterWorkoutSessionView(for sessionID: PersistentIdentifier) {
        registeredWorkoutSessionIDs.remove(sessionID)
    }

    func startRestTimer(
        for sessionID: PersistentIdentifier,
        at date: Date = Date(),
        sourceSessionExerciseID: PersistentIdentifier? = nil,
        sourceSetOrder: Int? = nil,
        exerciseName: String = "",
        setSummary: String = ""
    ) {
        activeRestSessionID = sessionID
        activeRestStartDate = date
        activeRestSourceSessionExerciseID = sourceSessionExerciseID
        activeRestSourceSetOrder = sourceSetOrder
        liveActivityExerciseName = exerciseName
        liveActivitySetSummary = setSummary
    }

    func clearRestTimer(for sessionID: PersistentIdentifier? = nil) {
        guard let sessionID else {
            activeRestSessionID = nil
            activeRestStartDate = nil
            activeRestSourceSessionExerciseID = nil
            activeRestSourceSetOrder = nil
            liveActivityExerciseName = ""
            liveActivitySetSummary = ""
            return
        }
        guard activeRestSessionID == sessionID else { return }
        activeRestSessionID = nil
        activeRestStartDate = nil
        activeRestSourceSessionExerciseID = nil
        activeRestSourceSetOrder = nil
        liveActivityExerciseName = ""
        liveActivitySetSummary = ""
    }

    func restElapsedSeconds(for sessionID: PersistentIdentifier, now: Date = Date()) -> Int {
        guard activeRestSessionID == sessionID, let restStart = activeRestStartDate else {
            return 0
        }
        return max(0, Int(now.timeIntervalSince(restStart)))
    }

    func restTimerText(for sessionID: PersistentIdentifier, now: Date = Date()) -> String {
        let elapsed = restElapsedSeconds(for: sessionID, now: now)
        let minutes = elapsed / 60
        let seconds = elapsed % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
