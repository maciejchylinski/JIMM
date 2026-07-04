import Foundation
import SwiftData

/// Helpers for the single active (unfinished) workout: newest `WorkoutSession` with `completedAt == nil`
/// by `sessionDate`.
enum ActiveWorkoutSession {
    /// Unfinished sessions sorted with newest `sessionDate` first. The active session is `first`.
    static func unfinishedSessionsSorted(in context: ModelContext) throws -> [WorkoutSession] {
        let predicate = #Predicate<WorkoutSession> { $0.completedAt == nil }
        var descriptor = FetchDescriptor<WorkoutSession>(predicate: predicate)
        descriptor.sortBy = [SortDescriptor(\.sessionDate, order: .reverse)]
        return try context.fetch(descriptor)
    }

    /// If more than one unfinished session exists, keeps the newest by `sessionDate` and deletes the rest.
    static func pruneDuplicateUnfinishedSessions(in context: ModelContext) throws {
        let sessions = try unfinishedSessionsSorted(in: context)
        guard sessions.count > 1 else { return }
        for session in sessions.dropFirst() {
            context.delete(session)
        }
        try context.save()
    }

    /// Newest unfinished session if any (does not prune). Prefer `canonicalUnfinishedSessionAfterCleanup` before starting a new workout.
    static func newestUnfinishedSession(in context: ModelContext) throws -> WorkoutSession? {
        try unfinishedSessionsSorted(in: context).first
    }

    /// Prunes duplicate unfinished sessions, then returns the single remaining in-progress workout, if any.
    /// Call this **before** inserting a new active `WorkoutSession` so the UI can resume the existing one instead.
    static func canonicalUnfinishedSessionAfterCleanup(in context: ModelContext) throws -> WorkoutSession? {
        try pruneDuplicateUnfinishedSessions(in: context)
        return try newestUnfinishedSession(in: context)
    }

}
