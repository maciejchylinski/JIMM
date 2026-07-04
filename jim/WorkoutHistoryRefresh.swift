import Foundation

extension Notification.Name {
    /// Posted after a workout is marked complete and persisted so Home can refresh history without relying on @Query timing alone.
    static let jimWorkoutSessionFinishedForHistory = Notification.Name("mch.jim.workoutSessionFinishedForHistory")
    /// Posted when any flow should open/resume an active workout via the same global route as the mini card.
    static let jimOpenActiveWorkoutSession = Notification.Name("mch.jim.openActiveWorkoutSession")
}
