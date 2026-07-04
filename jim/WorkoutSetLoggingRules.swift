import Foundation

// MARK: - Set logging rules (completion, volume, PR)

enum WorkoutSetLoggingRules {
    /// Logging type used when rendering a stored set (mobility with duration → duration).
    static func displayLoggingType(exercise: Exercise?, set: WorkoutSet) -> ExerciseLoggingType {
        let base = exercise?.loggingType ?? .strength
        if base == .mobility, (set.durationSeconds ?? 0) > 0 {
            return .duration
        }
        return base
    }

    /// Whether a set has enough logged data to count as complete (rest timer, PR qualification).
    static func isComplete(set: WorkoutSet, loggingType: ExerciseLoggingType) -> Bool {
        switch loggingType {
        case .strength:
            return set.weight > 0 && set.reps > 0
        case .bodyweight:
            return set.reps > 0
        case .duration:
            return (set.durationSeconds ?? 0) > 0
        case .cardio:
            return (set.durationSeconds ?? 0) > 0 || (set.distanceMeters ?? 0) > 0
        case .mobility:
            return (set.durationSeconds ?? 0) > 0
        }
    }

    /// Pending rows or sets that fail `isComplete` are stripped on finish.
    static func isIncompleteForFinish(set: WorkoutSet, loggingType: ExerciseLoggingType?) -> Bool {
        if set.isPendingSuggestion { return true }
        return !isComplete(set: set, loggingType: loggingType ?? .strength)
    }

    static func qualifiesForPR(set: WorkoutSet, loggingType: ExerciseLoggingType) -> Bool {
        isComplete(set: set, loggingType: loggingType)
    }

    static func contributesToVolume(exercise: Exercise?) -> Bool {
        (exercise?.loggingType ?? .strength) == .strength
    }

    static func volumeKg(set: WorkoutSet, exercise: Exercise?) -> Double {
        guard contributesToVolume(exercise: exercise) else { return 0 }
        return set.weight * Double(set.reps)
    }

    /// Strength volume for one finished workout (kg); only complete, non-pending strength sets count.
    static func sessionStrengthVolumeKg(in session: WorkoutSession) -> (volumeKg: Double, setCount: Int) {
        var totalKg = 0.0
        var setCount = 0
        for sessionExercise in session.sessionExercises {
            let exercise = sessionExercise.exercise
            guard contributesToVolume(exercise: exercise) else { continue }
            for set in sessionExercise.sets where !set.isPendingSuggestion {
                guard isComplete(set: set, loggingType: .strength) else { continue }
                totalKg += volumeKg(set: set, exercise: exercise)
                setCount += 1
            }
        }
        return (totalKg, setCount)
    }

    /// True when `candidate` should replace `incumbent` as the workout PR holder (not when performances are equal).
    static func isStrictlyBetterWorkoutPerformance(
        candidate: WorkoutSet,
        than incumbent: WorkoutSet,
        loggingType: ExerciseLoggingType
    ) -> Bool {
        switch loggingType {
        case .duration, .mobility:
            return (candidate.durationSeconds ?? 0) > (incumbent.durationSeconds ?? 0)
        case .cardio:
            let epsilon = 0.000_001
            let candidateDistance = candidate.distanceMeters ?? 0
            let incumbentDistance = incumbent.distanceMeters ?? 0
            if candidateDistance > incumbentDistance + epsilon { return true }
            if candidateDistance < incumbentDistance - epsilon { return false }
            return (candidate.durationSeconds ?? 0) > (incumbent.durationSeconds ?? 0)
        case .bodyweight:
            return candidate.reps > incumbent.reps
        case .strength:
            let epsilon = 0.000_001
            if candidate.weight > incumbent.weight + epsilon { return true }
            if candidate.weight < incumbent.weight - epsilon { return false }
            if candidate.reps > incumbent.reps { return true }
            return false
        }
    }

    /// Scalar for progress charts; preserves the same ordering as `isStrictlyBetterWorkoutPerformance`.
    static func progressChartValue(set: WorkoutSet, exercise: Exercise?) -> Double {
        let loggingType = exercise?.loggingType ?? .strength
        switch loggingType {
        case .strength:
            return set.weight * 10_000 + Double(set.reps)
        case .bodyweight:
            return Double(set.reps)
        case .duration, .mobility:
            return Double(set.durationSeconds ?? 0)
        case .cardio:
            return (set.distanceMeters ?? 0) * 10_000 + Double(set.durationSeconds ?? 0)
        }
    }

    /// Best logged set among completed (non-pending) sets for progress / stats.
    static func bestCompletedPerformance(
        among sets: [WorkoutSet],
        exercise: Exercise?
    ) -> WorkoutSet? {
        let loggingType = exercise?.loggingType ?? .strength
        let candidates = sets.filter {
            !$0.isPendingSuggestion && isComplete(set: $0, loggingType: loggingType)
        }
        guard let first = candidates.first else { return nil }
        return candidates.dropFirst().reduce(first) { best, candidate in
            isStrictlyBetterWorkoutPerformance(
                candidate: candidate,
                than: best,
                loggingType: loggingType
            ) ? candidate : best
        }
    }
}

// MARK: - Weight display (stored kg; display-only rounding)

enum WeightUnitFormatting {
    static let kgPerLb = 0.453_592_37
    static let lbPerKg = 2.204_622_621_8

    /// Stored kilograms → display unit. Kg rounds to 0.5; lbs stay gym-friendly (whole or 0.5).
    static func displayWeight(fromStoredKg kg: Double, unit: String) -> Double {
        guard kg > 0 else { return 0 }
        if unit == "lb" {
            let lbs = kg * lbPerKg
            if lbs >= 10 {
                return lbs.rounded()
            }
            return (lbs * 2).rounded() / 2
        }
        return (kg * 2).rounded() / 2
    }

    /// User-typed display value → stored kg (no display rounding).
    static func storedKg(fromDisplayWeight display: Double, unit: String) -> Double {
        unit == "lb" ? display * kgPerLb : display
    }

    static func formatWeight(fromStoredKg kg: Double, unit: String) -> String {
        let display = displayWeight(fromStoredKg: kg, unit: unit)
        guard display > 0 else { return "0" }
        if display.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", display)
        }
        return String(format: "%.1f", display)
    }

    static func formatVolume(fromStoredKg kg: Double, unit: String) -> String {
        let display: Double
        if unit == "lb" {
            display = kg * lbPerKg
        } else {
            display = (kg * 2).rounded() / 2
        }
        if display.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", display)
        }
        return String(format: "%.1f", display)
    }
}

// MARK: - Logged set display (history, repeat, read-only, live activity)

enum WorkoutSetDisplay {
    static let emptyPlaceholder = "—"

    static func displayLoggingType(exercise: Exercise?, set: WorkoutSet) -> ExerciseLoggingType {
        WorkoutSetLoggingRules.displayLoggingType(exercise: exercise, set: set)
    }

    static func contributesToVolume(exercise: Exercise?) -> Bool {
        WorkoutSetLoggingRules.contributesToVolume(exercise: exercise)
    }

    static func volumeKg(set: WorkoutSet, exercise: Exercise?) -> Double {
        WorkoutSetLoggingRules.volumeKg(set: set, exercise: exercise)
    }

    /// Stored kg volume converted for display with the user's weight unit preference.
    static func formatVolumeDisplay(kg: Double, weightUnit: String) -> String {
        WeightUnitFormatting.formatVolume(fromStoredKg: kg, unit: weightUnit)
    }

    static func formatLoggedSet(set: WorkoutSet, exercise: Exercise?, weightUnit: String) -> String {
        formatCompactResult(
            set: set,
            exercise: exercise,
            weightUnit: weightUnit
        )
    }

    static func formatCompactResult(
        set: WorkoutSet,
        exercise: Exercise?,
        weightUnit: String
    ) -> String {
        formatCompactResult(
            weight: set.weight,
            reps: set.reps,
            weightUnit: weightUnit,
            loggingType: displayLoggingType(exercise: exercise, set: set),
            durationSeconds: set.durationSeconds,
            distanceMeters: set.distanceMeters
        )
    }

    static func formatCompactResult(
        weight: Double,
        reps: Int,
        weightUnit: String,
        loggingType: ExerciseLoggingType,
        durationSeconds: Int? = nil,
        distanceMeters: Double? = nil
    ) -> String {
        switch loggingType {
        case .bodyweight:
            guard reps > 0 else { return emptyPlaceholder }
            return "\(reps)"
        case .duration:
            guard (durationSeconds ?? 0) > 0 else { return emptyPlaceholder }
            return WorkoutDurationFormat.display(seconds: durationSeconds ?? 0)
        case .cardio:
            let duration = durationSeconds ?? 0
            let distance = distanceMeters ?? 0
            guard duration > 0 || distance > 0 else { return emptyPlaceholder }
            var parts: [String] = []
            if duration > 0 {
                parts.append(WorkoutDurationFormat.display(seconds: duration))
            }
            if distance > 0 {
                parts.append(WorkoutDistanceFormat.displayCompactKilometers(meters: distance))
            }
            return parts.joined(separator: " · ")
        case .mobility:
            guard (durationSeconds ?? 0) > 0 else { return emptyPlaceholder }
            return WorkoutDurationFormat.display(seconds: durationSeconds ?? 0)
        default:
            return formatStrength(weight: weight, reps: reps, weightUnit: weightUnit)
        }
    }

    static func readOnlyTrailingHeaderLabel(exercise: Exercise?, weightUnit: String) -> String {
        switch exercise?.loggingType {
        case .duration, .mobility: return "Duration"
        case .bodyweight: return "Reps"
        case .cardio: return ""
        default: return "\(weightUnit) × reps"
        }
    }

    private static func formatStrength(weight: Double, reps: Int, weightUnit: String) -> String {
        guard reps > 0, weight > 0 else { return emptyPlaceholder }
        let w = WeightUnitFormatting.formatWeight(fromStoredKg: weight, unit: weightUnit)
        return "\(w) × \(reps)"
    }
}
