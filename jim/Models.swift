import Foundation
import SwiftData

enum ExerciseSource: String, CaseIterable {
    case builtIn = "built_in"
    case userSaved = "user_saved"
    case sessionOnly = "session_only"
}

/// How an exercise is intended to be logged in the workout UI (weights/reps vs time/cardio, etc.).
/// Persisted via optional raw string: `nil` and unknown values migrate as **strength** for backward compatibility.
enum ExerciseLoggingType: String, CaseIterable {
    case strength
    case bodyweight
    case cardio
    case duration
    case mobility
}

// MARK: - Starting / repeating sessions

extension WorkoutSession {
    /// New session copying exercises and logged sets from a completed workout (repeat).
    static func newRepeating(from source: WorkoutSession, in context: ModelContext) -> WorkoutSession? {
        guard source.completedAt != nil else { return nil }
        let orderedExercises = source.sessionExercises.sorted { $0.exerciseOrder < $1.exerciseOrder }
        guard !orderedExercises.isEmpty else { return nil }

        let session = WorkoutSession(name: source.name, sessionDate: Date())
        context.insert(session)
        for oldExercise in orderedExercises {
            let sessionExercise = WorkoutSessionExercise(
                exerciseOrder: oldExercise.exerciseOrder,
                session: session,
                exercise: oldExercise.exercise,
                sourceRawValue: oldExercise.sourceRawValue,
                customExerciseName: oldExercise.customExerciseName
            )
            context.insert(sessionExercise)
            session.sessionExercises.append(sessionExercise)
            let orderedSets = oldExercise.sets.sorted { $0.setOrder < $1.setOrder }
            for oldSet in orderedSets {
                let newSet = WorkoutSet(
                    setOrder: oldSet.setOrder,
                    weight: oldSet.weight,
                    reps: oldSet.reps,
                    isPendingSuggestion: true,
                    restDurationSeconds: oldSet.restDurationSeconds,
                    durationSeconds: oldSet.durationSeconds,
                    distanceMeters: oldSet.distanceMeters,
                    sessionExercise: sessionExercise
                )
                context.insert(newSet)
                sessionExercise.sets.append(newSet)
            }
        }
        try? context.save()
        return session
    }

    /// New session copied from a workout plan in persisted exercise order.
    static func newFromPlan(_ plan: WorkoutPlan, in context: ModelContext) -> WorkoutSession? {
        let orderedExercises = plan.exercises.sorted { $0.exerciseOrder < $1.exerciseOrder }
        guard !orderedExercises.isEmpty else { return nil }

        let trimmedName = plan.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let sessionName = trimmedName.isEmpty ? nil : trimmedName
        let session = WorkoutSession(
            name: sessionName,
            sessionDate: Date(),
            startedFromPlanTemplate: true
        )
        context.insert(session)

        for (index, planExercise) in orderedExercises.enumerated() {
            let sessionExercise = WorkoutSessionExercise(
                exerciseOrder: index + 1,
                session: session,
                exercise: planExercise.exercise,
                sourceRawValue: planExercise.sourceRawValue,
                customExerciseName: planExercise.customExerciseName
            )
            context.insert(sessionExercise)
            session.sessionExercises.append(sessionExercise)

            // Keep active workout behavior unchanged: each exercise starts with one pending 0 x 0 row.
            let pendingSet = WorkoutSet(
                setOrder: 1,
                weight: 0,
                reps: 0,
                isPendingSuggestion: true,
                sessionExercise: sessionExercise
            )
            context.insert(pendingSet)
            sessionExercise.sets.append(pendingSet)
        }

        try? context.save()
        return session
    }
}

@Model
final class Exercise {
    var name: String
    var category: String
    /// Hidden search metadata (aliases/tags), newline-separated.
    /// Not shown in UI; used only for exercise suggestions.
    var searchMetadata: String = ""
    /// Source classification for exercise library rows (built-in vs user-saved).
    var sourceRawValue: String = ExerciseSource.userSaved.rawValue
    /// When `true`, user-saved exercise is omitted from library pickers; `nil` and `false` mean visible (migration-safe).
    var isHiddenFromLibrary: Bool?
    /// Optional persisted logging mode; missing/invalid reads as `.strength` (legacy default).
    var loggingTypeRawValue: String?

    var source: ExerciseSource {
        get { ExerciseSource(rawValue: sourceRawValue) ?? .userSaved }
        set { sourceRawValue = newValue.rawValue }
    }

    var loggingType: ExerciseLoggingType {
        get {
            guard let raw = loggingTypeRawValue,
                  let parsed = ExerciseLoggingType(rawValue: raw) else { return .strength }
            return parsed
        }
        set {
            if newValue == .strength {
                loggingTypeRawValue = nil
            } else {
                loggingTypeRawValue = newValue.rawValue
            }
        }
    }

    init(
        name: String,
        category: String,
        searchMetadata: String = "",
        source: ExerciseSource = .userSaved,
        isHiddenFromLibrary: Bool? = nil,
        loggingType: ExerciseLoggingType? = nil
    ) {
        self.name = name
        self.category = category
        self.searchMetadata = searchMetadata
        self.sourceRawValue = source.rawValue
        self.isHiddenFromLibrary = isHiddenFromLibrary
        self.loggingTypeRawValue = loggingType.flatMap { $0 == .strength ? nil : $0.rawValue }
    }
}

@Model
final class WorkoutSession {
    var name: String?
    var sessionDate: Date
    /// True when this session was started from an existing saved workout plan/template.
    var startedFromPlanTemplate: Bool?
    /// When non-nil, the workout was finished by the user and can be used for history / previous-reference lookup.
    var completedAt: Date?
    @Relationship(deleteRule: .cascade, inverse: \WorkoutSessionExercise.session)
    var sessionExercises: [WorkoutSessionExercise]

    init(
        name: String? = nil,
        sessionDate: Date,
        startedFromPlanTemplate: Bool? = nil,
        completedAt: Date? = nil,
        sessionExercises: [WorkoutSessionExercise] = []
    ) {
        self.name = name
        self.sessionDate = sessionDate
        self.startedFromPlanTemplate = startedFromPlanTemplate
        self.completedAt = completedAt
        self.sessionExercises = sessionExercises
    }
}

@Model
final class WorkoutSessionExercise {
    var exerciseOrder: Int
    var session: WorkoutSession?
    var exercise: Exercise?
    /// Session-level source classification (built-in, user-saved custom, or session-only custom).
    var sourceRawValue: String = ExerciseSource.builtIn.rawValue
    /// Used only for session-only exercises that should not be persisted in global library.
    var customExerciseName: String?
    @Relationship(deleteRule: .cascade, inverse: \WorkoutSet.sessionExercise)
    var sets: [WorkoutSet]

    var source: ExerciseSource {
        get { ExerciseSource(rawValue: sourceRawValue) ?? .builtIn }
        set { sourceRawValue = newValue.rawValue }
    }

    var displayName: String {
        if let name = exercise?.name, !name.isEmpty { return name }
        let custom = customExerciseName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !custom.isEmpty { return custom }
        return "Exercise"
    }

    init(
        exerciseOrder: Int,
        session: WorkoutSession? = nil,
        exercise: Exercise? = nil,
        sourceRawValue: String = ExerciseSource.builtIn.rawValue,
        customExerciseName: String? = nil,
        sets: [WorkoutSet] = []
    ) {
        self.exerciseOrder = exerciseOrder
        self.session = session
        self.exercise = exercise
        self.sourceRawValue = sourceRawValue
        self.customExerciseName = customExerciseName
        self.sets = sets
    }
}

@Model
final class WorkoutSet {
    var setOrder: Int
    var weight: Double
    var reps: Int
    /// True when values are prefilled as a suggestion and still awaiting per-set confirmation/edit.
    var isPendingSuggestion: Bool = false
    var restDurationSeconds: Int?
    /// Logged hold/duration for time-based exercises (e.g. plank). Separate from rest between sets.
    var durationSeconds: Int?
    /// Logged distance for cardio exercises (e.g. treadmill, bike). Stored in meters.
    var distanceMeters: Double?
    var sessionExercise: WorkoutSessionExercise?

    init(
        setOrder: Int,
        weight: Double,
        reps: Int,
        isPendingSuggestion: Bool = false,
        restDurationSeconds: Int? = nil,
        durationSeconds: Int? = nil,
        distanceMeters: Double? = nil,
        sessionExercise: WorkoutSessionExercise? = nil
    ) {
        self.setOrder = setOrder
        self.weight = weight
        self.reps = reps
        self.isPendingSuggestion = isPendingSuggestion
        self.restDurationSeconds = restDurationSeconds
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.sessionExercise = sessionExercise
    }
}

// MARK: - Workout plans model

@Model
final class WorkoutPlan {
    var name: String
    var createdAt: Date
    @Relationship(deleteRule: .cascade, inverse: \WorkoutPlanExercise.plan)
    var exercises: [WorkoutPlanExercise]

    init(
        name: String,
        createdAt: Date = Date(),
        exercises: [WorkoutPlanExercise] = []
    ) {
        self.name = name
        self.createdAt = createdAt
        self.exercises = exercises
    }
}

@Model
final class WorkoutPlanExercise {
    var exerciseOrder: Int
    var exercise: Exercise?
    var customExerciseName: String?
    var sourceRawValue: String
    var plan: WorkoutPlan?

    var source: ExerciseSource {
        get { ExerciseSource(rawValue: sourceRawValue) ?? .builtIn }
        set { sourceRawValue = newValue.rawValue }
    }

    init(
        exerciseOrder: Int,
        exercise: Exercise? = nil,
        customExerciseName: String? = nil,
        sourceRawValue: String = ExerciseSource.builtIn.rawValue,
        plan: WorkoutPlan? = nil
    ) {
        self.exerciseOrder = exerciseOrder
        self.exercise = exercise
        self.customExerciseName = customExerciseName
        self.sourceRawValue = sourceRawValue
        self.plan = plan
    }
}
