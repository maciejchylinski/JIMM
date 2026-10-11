import Foundation

// MARK: - Remote row DTOs (snake_case matches Supabase)

struct ProfileDTO: Codable, Sendable {
    let id: UUID
    var email: String?
    var displayName: String?
    var createdAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case displayName = "display_name"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct ExerciseDTO: Codable, Sendable, Identifiable {
    let id: UUID
    let userId: UUID
    var name: String
    var category: String
    var searchMetadata: String
    var source: String
    var isHiddenFromLibrary: Bool?
    var loggingType: String?
    var updatedAt: Date
    var deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
        case category
        case searchMetadata = "search_metadata"
        case source
        case isHiddenFromLibrary = "is_hidden_from_library"
        case loggingType = "logging_type"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }
}

struct WorkoutSessionDTO: Codable, Sendable, Identifiable {
    let id: UUID
    let userId: UUID
    var name: String?
    var sessionDate: Date
    var startedFromPlanTemplate: Bool?
    var completedAt: Date?
    var updatedAt: Date
    var deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
        case sessionDate = "session_date"
        case startedFromPlanTemplate = "started_from_plan_template"
        case completedAt = "completed_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }
}

struct WorkoutSessionExerciseDTO: Codable, Sendable, Identifiable {
    let id: UUID
    let userId: UUID
    var sessionId: UUID
    var exerciseOrder: Int
    var exerciseId: UUID?
    var builtInExerciseName: String?
    var source: String
    var customExerciseName: String?
    var updatedAt: Date
    var deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case sessionId = "session_id"
        case exerciseOrder = "exercise_order"
        case exerciseId = "exercise_id"
        case builtInExerciseName = "built_in_exercise_name"
        case source
        case customExerciseName = "custom_exercise_name"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }
}

struct WorkoutSetDTO: Codable, Sendable, Identifiable {
    let id: UUID
    let userId: UUID
    var sessionExerciseId: UUID
    var setOrder: Int
    var weight: Double
    var reps: Int
    var isPendingSuggestion: Bool
    var restDurationSeconds: Int?
    var durationSeconds: Int?
    var distanceMeters: Double?
    var updatedAt: Date
    var deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case sessionExerciseId = "session_exercise_id"
        case setOrder = "set_order"
        case weight
        case reps
        case isPendingSuggestion = "is_pending_suggestion"
        case restDurationSeconds = "rest_duration_seconds"
        case durationSeconds = "duration_seconds"
        case distanceMeters = "distance_meters"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }
}

struct WorkoutPlanDTO: Codable, Sendable, Identifiable {
    let id: UUID
    let userId: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }
}

struct WorkoutPlanExerciseDTO: Codable, Sendable, Identifiable {
    let id: UUID
    let userId: UUID
    var planId: UUID
    var exerciseOrder: Int
    var exerciseId: UUID?
    var builtInExerciseName: String?
    var customExerciseName: String?
    var source: String
    var updatedAt: Date
    var deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case planId = "plan_id"
        case exerciseOrder = "exercise_order"
        case exerciseId = "exercise_id"
        case builtInExerciseName = "built_in_exercise_name"
        case customExerciseName = "custom_exercise_name"
        case source
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }
}

struct SyncMetadataDTO: Codable, Sendable {
    let userId: UUID
    var lastSyncedAt: Date?
    var clientDeviceId: String?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case lastSyncedAt = "last_synced_at"
        case clientDeviceId = "client_device_id"
        case updatedAt = "updated_at"
    }
}
