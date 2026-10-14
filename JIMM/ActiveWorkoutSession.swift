import Foundation
import SwiftData

/// Explicit current-workout marker. Do not treat “any unfinished session” as active.
enum ActiveWorkoutSession {
    /// Workouts older than this are no longer eligible to resume as the active session.
    static let staleInterval: TimeInterval = 12 * 60 * 60

    private static let activeSyncIDKey = "activeWorkout.currentSyncID"

    private static var storedActiveSyncID: UUID? {
        get {
            guard let raw = UserDefaults.standard.string(forKey: activeSyncIDKey) else { return nil }
            return UUID(uuidString: raw)
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue.uuidString, forKey: activeSyncIDKey)
            } else {
                UserDefaults.standard.removeObject(forKey: activeSyncIDKey)
            }
        }
    }

    static func markActive(_ session: WorkoutSession) {
        storedActiveSyncID = session.syncID
    }

    static func clearActive(matching session: WorkoutSession? = nil) {
        if let session {
            guard storedActiveSyncID == session.syncID else { return }
        }
        storedActiveSyncID = nil
    }

    static func isMarkedActive(_ session: WorkoutSession) -> Bool {
        storedActiveSyncID == session.syncID
    }

    static func isStale(_ session: WorkoutSession, now: Date = .now) -> Bool {
        now.timeIntervalSince(session.sessionDate) > staleInterval
    }

    /// Returns the explicitly marked active workout if it is still valid.
    /// Clears the marker when the session is missing, completed, or stale.
    /// Does not delete workout records.
    @discardableResult
    static func resolveCurrentActiveSession(in context: ModelContext, now: Date = .now) -> WorkoutSession? {
        guard let syncID = storedActiveSyncID else { return nil }

        let predicate = #Predicate<WorkoutSession> { $0.syncID == syncID }
        var descriptor = FetchDescriptor<WorkoutSession>(predicate: predicate)
        descriptor.fetchLimit = 1

        guard let session = try? context.fetch(descriptor).first else {
            storedActiveSyncID = nil
            return nil
        }

        if session.completedAt != nil {
            storedActiveSyncID = nil
            return nil
        }

        if isStale(session, now: now) {
            storedActiveSyncID = nil
            return nil
        }

        return session
    }

    /// Unfinished sessions sorted with newest `sessionDate` first.
    static func unfinishedSessionsSorted(in context: ModelContext) throws -> [WorkoutSession] {
        let predicate = #Predicate<WorkoutSession> { $0.completedAt == nil }
        var descriptor = FetchDescriptor<WorkoutSession>(predicate: predicate)
        descriptor.sortBy = [SortDescriptor(\.sessionDate, order: .reverse)]
        return try context.fetch(descriptor)
    }

    /// Reconciles the active marker. Does not delete unfinished session records.
    static func pruneDuplicateUnfinishedSessions(in context: ModelContext) throws {
        _ = resolveCurrentActiveSession(in: context)
    }

    /// Current active workout after reconciling the explicit marker (stale / missing / completed cleared).
    static func canonicalUnfinishedSessionAfterCleanup(in context: ModelContext) throws -> WorkoutSession? {
        resolveCurrentActiveSession(in: context)
    }

    static func newestUnfinishedSession(in context: ModelContext) throws -> WorkoutSession? {
        try unfinishedSessionsSorted(in: context).first
    }
}
