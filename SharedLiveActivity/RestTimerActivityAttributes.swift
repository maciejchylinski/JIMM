import Foundation
import ActivityKit

/// Shared between the app and the widget extension. Must stay `Codable` / stable for ActivityKit.
public struct RestTimerActivityAttributes: ActivityAttributes {
    public init() {}

    public struct ContentState: Codable, Hashable, Sendable {
        public var restStartDate: Date
        /// Elapsed workout time uses `Text(..., style: .timer)` from this instant.
        public var workoutSessionStartDate: Date
        /// Next exercise / set to perform (computed in the app during rest).
        public var exerciseName: String
        /// Last confirmed set and optional next-set hint, e.g. `Set 3 · 80 kg × 8` or `Prev 80 × 8`.
        public var setSummary: String

        public init(
            restStartDate: Date,
            workoutSessionStartDate: Date,
            exerciseName: String = "",
            setSummary: String = ""
        ) {
            self.restStartDate = restStartDate
            self.workoutSessionStartDate = workoutSessionStartDate
            self.exerciseName = exerciseName
            self.setSummary = setSummary
        }
    }
}
