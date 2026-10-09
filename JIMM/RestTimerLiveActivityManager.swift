import ActivityKit
import Combine
import Foundation

struct RestTimerLiveActivityPayload: Equatable {
    var restStartDate: Date
    var workoutSessionStartDate: Date
    var exerciseName: String
    var setSummary: String
}

/// Owns the optional rest-timer Live Activity (local updates only; no push).
@MainActor
final class RestTimerLiveActivityManager: ObservableObject {
    private static let liveActivityFreshnessWindow: TimeInterval = 60 * 60
    private static let minimumForegroundFreshnessWindow: TimeInterval = 5 * 60

    private var activity: Activity<RestTimerActivityAttributes>?
    private var lastSyncedPayload: RestTimerLiveActivityPayload?

    /// `nil` ends the Live Activity. Same lifecycle as before; payload carries lock-screen / expanded context.
    func sync(payload: RestTimerLiveActivityPayload?) {
        guard #available(iOS 16.1, *) else { return }
        guard let payload else {
            lastSyncedPayload = nil
            Task { await endInternal() }
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            lastSyncedPayload = nil
            Task { await endInternal() }
            return
        }
        if payload == lastSyncedPayload { return }
        lastSyncedPayload = payload
        Task { await startOrUpdate(payload: payload) }
    }

    /// Reconciles ActivityKit's process-independent activities with the app's current rest state.
    /// Use on launch/foreground to clean up activities left behind by a previous crash or kill.
    func reconcile(payload: RestTimerLiveActivityPayload?) {
        guard #available(iOS 16.1, *) else { return }
        if let payload, ActivityAuthorizationInfo().areActivitiesEnabled {
            lastSyncedPayload = payload
            Task { await startOrUpdate(payload: payload, shouldEndDuplicates: true) }
        } else {
            lastSyncedPayload = nil
            Task { await endAllActivities() }
        }
    }

    @available(iOS 16.1, *)
    private func startOrUpdate(payload: RestTimerLiveActivityPayload, shouldEndDuplicates: Bool = false) async {
        let state = RestTimerActivityAttributes.ContentState(
            restStartDate: payload.restStartDate,
            workoutSessionStartDate: payload.workoutSessionStartDate,
            exerciseName: payload.exerciseName,
            setSummary: payload.setSummary
        )
        let content = ActivityContent(state: state, staleDate: staleDate(for: payload))

        if let existing = activity {
            switch existing.activityState {
            case .active, .stale:
                await existing.update(content)
                return
            case .ended, .dismissed, .pending:
                activity = nil
            @unknown default:
                activity = nil
            }
        }

        if let existing = Self.reusableSystemActivity() {
            activity = existing
            await existing.update(content)
            if shouldEndDuplicates {
                await endDuplicateActivities(keeping: existing.id)
            }
            return
        }

        let attributes = RestTimerActivityAttributes()
        do {
            activity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
        } catch {
            activity = nil
        }
    }

    @available(iOS 16.1, *)
    private func staleDate(for payload: RestTimerLiveActivityPayload) -> Date {
        max(
            payload.restStartDate.addingTimeInterval(Self.liveActivityFreshnessWindow),
            Date().addingTimeInterval(Self.minimumForegroundFreshnessWindow)
        )
    }

    @available(iOS 16.1, *)
    private static func reusableSystemActivity() -> Activity<RestTimerActivityAttributes>? {
        Activity<RestTimerActivityAttributes>.activities.first { activity in
            switch activity.activityState {
            case .active, .stale:
                return true
            case .ended, .dismissed, .pending:
                return false
            @unknown default:
                return false
            }
        }
    }

    @available(iOS 16.1, *)
    private func endInternal() async {
        guard let activity else {
            await endAllActivities()
            return
        }
        self.activity = nil
        await activity.end(nil, dismissalPolicy: .immediate)
        await endDuplicateActivities(keeping: activity.id)
    }

    @available(iOS 16.1, *)
    private func endAllActivities() async {
        activity = nil
        for activity in Activity<RestTimerActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    @available(iOS 16.1, *)
    private func endDuplicateActivities(keeping keptID: String) async {
        for activity in Activity<RestTimerActivityAttributes>.activities where activity.id != keptID {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
