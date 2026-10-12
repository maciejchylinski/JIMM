import Combine
import Foundation
import Network
import Supabase
import SwiftData

extension Notification.Name {
    static let jimCloudSyncRequested = Notification.Name("jimCloudSyncRequested")
    static let jimLocalDataDidChange = Notification.Name("jimLocalDataDidChange")
}

/// Local-first cloud backup/sync. Never blocks workout logging on network failures.
@MainActor
final class SyncService: ObservableObject {
    static let shared = SyncService()

    @Published private(set) var isSyncing = false
    @Published private(set) var lastSyncError: String?

    private var modelContext: ModelContext?
    private var syncTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private let pathMonitor = NWPathMonitor()
    private var isPathSatisfied = true
    private let deviceIDKey = "account.clientDeviceId"

    private init() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isPathSatisfied = path.status == .satisfied
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "jim.sync.network"))
    }

    func attach(modelContext: ModelContext) {
        self.modelContext = modelContext
        AuthService.shared.evaluateInitialBackupOffer()
    }

    var isModelContextAttached: Bool { modelContext != nil }

    /// True when the device has user-created workouts, plans, or custom exercises worth backing up.
    func hasLocalUserDataToBackup() -> Bool {
        guard let context = modelContext else { return false }
        let sessionCount = (try? context.fetchCount(FetchDescriptor<WorkoutSession>())) ?? 0
        let planCount = (try? context.fetchCount(FetchDescriptor<WorkoutPlan>())) ?? 0
        let customCount = ((try? context.fetch(FetchDescriptor<Exercise>())) ?? [])
            .filter { $0.source == .userSaved }
            .count
        return sessionCount > 0 || planCount > 0 || customCount > 0
    }

    var clientDeviceID: String {
        if let existing = UserDefaults.standard.string(forKey: deviceIDKey), !existing.isEmpty {
            return existing
        }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: deviceIDKey)
        return id
    }

    /// Debounced background sync — safe to call after local saves.
    func scheduleSync(delayNanoseconds: UInt64 = 1_500_000_000) {
        guard AuthService.shared.isSignedIn, SupabaseService.shared.isConfigured else { return }
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled else { return }
            await self?.syncNow(isManual: false)
        }
    }

    func syncNow(isManual: Bool = true) async {
        guard !isSyncing else { return }
        guard let context = modelContext else {
            lastSyncError = "Couldn’t sync right now. Try again."
            return
        }
        guard AuthService.shared.isSignedIn else { return }
        guard let client = SupabaseService.shared.client, let userID = AuthService.shared.userID else {
            AuthService.shared.setSyncStatus(.error("Account is not available right now."))
            return
        }

        if !isPathSatisfied {
            AuthService.shared.setSyncStatus(.offline)
            if isManual {
                lastSyncError = "You’re offline. Try again when you’re connected."
            }
            return
        }

        isSyncing = true
        AuthService.shared.setSyncStatus(.syncing)
        lastSyncError = nil
        defer {
            isSyncing = false
        }

        do {
            // Repair shared syncIDs before push/pull so upsert batches and local indexes stay unique.
            try repairDuplicateLocalSyncIDs(in: context)
            try await pushLocalChanges(client: client, userID: userID, context: context)
            try await pullRemoteChanges(client: client, userID: userID, context: context)
            try await upsertSyncMetadata(client: client, userID: userID)
            try context.save()
            AuthService.shared.markInitialBackupCompleted()
            AuthService.shared.setSyncStatus(.synced(Date()))
        } catch {
            let message = error.localizedDescription
            lastSyncError = message
            AuthService.shared.setSyncStatus(.error(message))
            // Never throw to callers of scheduleSync — workout logging stays unblocked.
        }
    }

    // MARK: - Sync ID repair

    /// Existing SwiftData stores can share one default `syncID` after the cloud fields were added.
    private func repairDuplicateLocalSyncIDs(in context: ModelContext) throws {
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let sessionExercises = try context.fetch(FetchDescriptor<WorkoutSessionExercise>())
        let sets = try context.fetch(FetchDescriptor<WorkoutSet>())
        let plans = try context.fetch(FetchDescriptor<WorkoutPlan>())
        let planExercises = try context.fetch(FetchDescriptor<WorkoutPlanExercise>())

        uniquifyLocalSyncIDs(
            exercises,
            entityName: "exercises",
            getID: { $0.syncID },
            setID: { $0.syncID = $1 },
            updatedAt: { $0.updatedAt },
            touch: { $0.touchForSync() }
        )
        uniquifyLocalSyncIDs(
            sessions,
            entityName: "workout_sessions",
            getID: { $0.syncID },
            setID: { $0.syncID = $1 },
            updatedAt: { $0.updatedAt },
            touch: { $0.touchForSync() }
        )
        uniquifyLocalSyncIDs(
            sessionExercises,
            entityName: "workout_session_exercises",
            getID: { $0.syncID },
            setID: { $0.syncID = $1 },
            updatedAt: { $0.updatedAt },
            touch: { $0.touchForSync() }
        )
        uniquifyLocalSyncIDs(
            sets,
            entityName: "workout_sets",
            getID: { $0.syncID },
            setID: { $0.syncID = $1 },
            updatedAt: { $0.updatedAt },
            touch: { $0.touchForSync() }
        )
        uniquifyLocalSyncIDs(
            plans,
            entityName: "workout_plans",
            getID: { $0.syncID },
            setID: { $0.syncID = $1 },
            updatedAt: { $0.updatedAt },
            touch: { $0.touchForSync() }
        )
        uniquifyLocalSyncIDs(
            planExercises,
            entityName: "workout_plan_exercises",
            getID: { $0.syncID },
            setID: { $0.syncID = $1 },
            updatedAt: { $0.updatedAt },
            touch: { $0.touchForSync() }
        )
    }

    // MARK: - Push

    private func pushLocalChanges(client: SupabaseClient, userID: UUID, context: ModelContext) async throws {
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
            .filter { $0.source == .userSaved }
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let sessionExercises = try context.fetch(FetchDescriptor<WorkoutSessionExercise>())
        let sets = try context.fetch(FetchDescriptor<WorkoutSet>())
        let plans = try context.fetch(FetchDescriptor<WorkoutPlan>())
        let planExercises = try context.fetch(FetchDescriptor<WorkoutPlanExercise>())

        let exerciseDTOs = dedupeUpsertRows(
            exercises.map { exercise in
                ExerciseDTO(
                    id: exercise.syncID,
                    userId: userID,
                    name: exercise.name,
                    category: exercise.category,
                    searchMetadata: exercise.searchMetadata,
                    source: ExerciseSource.userSaved.rawValue,
                    isHiddenFromLibrary: exercise.isHiddenFromLibrary,
                    loggingType: exercise.loggingTypeRawValue,
                    updatedAt: exercise.updatedAt,
                    deletedAt: exercise.cloudDeletedAt
                )
            },
            table: "exercises",
            conflictKey: \.id,
            updatedAt: \.updatedAt
        )

        let sessionDTOs = dedupeUpsertRows(
            sessions.map { session in
                WorkoutSessionDTO(
                    id: session.syncID,
                    userId: userID,
                    name: session.name,
                    sessionDate: session.sessionDate,
                    startedFromPlanTemplate: session.startedFromPlanTemplate,
                    completedAt: session.completedAt,
                    updatedAt: session.updatedAt,
                    deletedAt: session.cloudDeletedAt
                )
            },
            table: "workout_sessions",
            conflictKey: \.id,
            updatedAt: \.updatedAt
        )

        let sessionExerciseDTOs = dedupeUpsertRows(
            sessionExercises.compactMap { row -> WorkoutSessionExerciseDTO? in
                guard let sessionID = row.session?.syncID else { return nil }
                let exerciseID: UUID? = row.source == .userSaved ? row.exercise?.syncID : nil
                let builtInName: String? = {
                    if row.source == .builtIn {
                        return row.exercise?.name ?? row.customExerciseName
                    }
                    return nil
                }()
                return WorkoutSessionExerciseDTO(
                    id: row.syncID,
                    userId: userID,
                    sessionId: sessionID,
                    exerciseOrder: row.exerciseOrder,
                    exerciseId: exerciseID,
                    builtInExerciseName: builtInName,
                    source: row.sourceRawValue,
                    customExerciseName: row.customExerciseName,
                    updatedAt: row.updatedAt,
                    deletedAt: row.cloudDeletedAt
                )
            },
            table: "workout_session_exercises",
            conflictKey: \.id,
            updatedAt: \.updatedAt
        )

        let setDTOs = dedupeUpsertRows(
            sets.compactMap { set -> WorkoutSetDTO? in
                guard let sessionExerciseID = set.sessionExercise?.syncID else { return nil }
                return WorkoutSetDTO(
                    id: set.syncID,
                    userId: userID,
                    sessionExerciseId: sessionExerciseID,
                    setOrder: set.setOrder,
                    weight: set.weight,
                    reps: set.reps,
                    isPendingSuggestion: set.isPendingSuggestion,
                    restDurationSeconds: set.restDurationSeconds,
                    durationSeconds: set.durationSeconds,
                    distanceMeters: set.distanceMeters,
                    updatedAt: set.updatedAt,
                    deletedAt: set.cloudDeletedAt
                )
            },
            table: "workout_sets",
            conflictKey: \.id,
            updatedAt: \.updatedAt
        )

        let planDTOs = dedupeUpsertRows(
            plans.map { plan in
                WorkoutPlanDTO(
                    id: plan.syncID,
                    userId: userID,
                    name: plan.name,
                    createdAt: plan.createdAt,
                    updatedAt: plan.updatedAt,
                    deletedAt: plan.cloudDeletedAt
                )
            },
            table: "workout_plans",
            conflictKey: \.id,
            updatedAt: \.updatedAt
        )

        let planExerciseDTOs = dedupeUpsertRows(
            planExercises.compactMap { row -> WorkoutPlanExerciseDTO? in
                guard let planID = row.plan?.syncID else { return nil }
                let exerciseID: UUID? = row.source == .userSaved ? row.exercise?.syncID : nil
                let builtInName: String? = row.source == .builtIn ? (row.exercise?.name ?? row.customExerciseName) : nil
                return WorkoutPlanExerciseDTO(
                    id: row.syncID,
                    userId: userID,
                    planId: planID,
                    exerciseOrder: row.exerciseOrder,
                    exerciseId: exerciseID,
                    builtInExerciseName: builtInName,
                    customExerciseName: row.customExerciseName,
                    source: row.sourceRawValue,
                    updatedAt: row.updatedAt,
                    deletedAt: row.cloudDeletedAt
                )
            },
            table: "workout_plan_exercises",
            conflictKey: \.id,
            updatedAt: \.updatedAt
        )

        // Order matters for FK integrity on first insert.
        try await upsert(client: client, table: "exercises", onConflict: "id", rows: exerciseDTOs)
        try await upsert(client: client, table: "workout_sessions", onConflict: "id", rows: sessionDTOs)
        try await upsert(client: client, table: "workout_session_exercises", onConflict: "id", rows: sessionExerciseDTOs)
        try await upsert(client: client, table: "workout_sets", onConflict: "id", rows: setDTOs)
        try await upsert(client: client, table: "workout_plans", onConflict: "id", rows: planDTOs)
        try await upsert(client: client, table: "workout_plan_exercises", onConflict: "id", rows: planExerciseDTOs)

        let now = Date()
        for exercise in exercises { exercise.lastSyncedAt = now }
        for session in sessions { session.lastSyncedAt = now }
        for row in sessionExercises { row.lastSyncedAt = now }
        for set in sets { set.lastSyncedAt = now }
        for plan in plans { plan.lastSyncedAt = now }
        for row in planExercises { row.lastSyncedAt = now }
    }

    /// When multiple local models share one `syncID`, keep the newest on that ID and give others fresh IDs.
    private func uniquifyLocalSyncIDs<T>(
        _ items: [T],
        entityName: String,
        getID: (T) -> UUID,
        setID: (T, UUID) -> Void,
        updatedAt: (T) -> Date,
        touch: (T) -> Void
    ) {
        var groups: [UUID: [T]] = [:]
        for item in items {
            groups[getID(item), default: []].append(item)
        }

        var reassigned = 0
        for (_, group) in groups where group.count > 1 {
            let sorted = group.sorted { updatedAt($0) > updatedAt($1) }
            // Newest keeps the shared ID; older distinct rows get new IDs so they are not dropped.
            for loser in sorted.dropFirst() {
                setID(loser, UUID())
                touch(loser)
                reassigned += 1
            }
        }

        #if DEBUG
        if reassigned > 0 {
            print("SyncService: reassigned \(reassigned) duplicate syncID(s) for \(entityName)")
        }
        #endif
    }

    /// Safe local index — never fatal on duplicate syncIDs (keeps newest `updatedAt`).
    private func indexedBySyncID<T>(
        _ items: [T],
        getID: (T) -> UUID,
        updatedAt: (T) -> Date
    ) -> [UUID: T] {
        var result: [UUID: T] = [:]
        for item in items {
            let id = getID(item)
            if let existing = result[id] {
                if updatedAt(item) >= updatedAt(existing) {
                    result[id] = item
                }
            } else {
                result[id] = item
            }
        }
        return result
    }

    /// Postgres rejects upsert batches that mention the same conflict key twice.
    private func dedupeUpsertRows<T, Key: Hashable>(
        _ rows: [T],
        table: String,
        conflictKey: KeyPath<T, Key>,
        updatedAt: KeyPath<T, Date>
    ) -> [T] {
        guard !rows.isEmpty else { return rows }

        var bestByKey: [Key: T] = [:]
        var insertionOrder: [Key] = []
        var duplicateCount = 0

        for row in rows {
            let key = row[keyPath: conflictKey]
            if let existing = bestByKey[key] {
                duplicateCount += 1
                if row[keyPath: updatedAt] >= existing[keyPath: updatedAt] {
                    bestByKey[key] = row
                }
            } else {
                bestByKey[key] = row
                insertionOrder.append(key)
            }
        }

        #if DEBUG
        if duplicateCount > 0 {
            print("SyncService: removed \(duplicateCount) duplicate upsert row(s) for \(table) (conflict key); kept newest updatedAt")
        }
        #endif

        return insertionOrder.compactMap { bestByKey[$0] }
    }

    private func upsert<T: Encodable>(
        client: SupabaseClient,
        table: String,
        onConflict: String,
        rows: [T]
    ) async throws {
        guard !rows.isEmpty else { return }
        // Chunk to avoid oversized payloads.
        let chunkSize = 100
        var index = 0
        while index < rows.count {
            let end = min(index + chunkSize, rows.count)
            let chunk = Array(rows[index..<end])
            try await client.from(table)
                .upsert(chunk, onConflict: onConflict)
                .execute()
            index = end
        }
    }

    // MARK: - Pull (newest updatedAt wins)

    private func pullRemoteChanges(client: SupabaseClient, userID: UUID, context: ModelContext) async throws {
        let remoteExercises: [ExerciseDTO] = try await client.from("exercises")
            .select()
            .eq("user_id", value: userID.uuidString)
            .execute()
            .value
        let remoteSessions: [WorkoutSessionDTO] = try await client.from("workout_sessions")
            .select()
            .eq("user_id", value: userID.uuidString)
            .execute()
            .value
        let remoteSessionExercises: [WorkoutSessionExerciseDTO] = try await client.from("workout_session_exercises")
            .select()
            .eq("user_id", value: userID.uuidString)
            .execute()
            .value
        let remoteSets: [WorkoutSetDTO] = try await client.from("workout_sets")
            .select()
            .eq("user_id", value: userID.uuidString)
            .execute()
            .value
        let remotePlans: [WorkoutPlanDTO] = try await client.from("workout_plans")
            .select()
            .eq("user_id", value: userID.uuidString)
            .execute()
            .value
        let remotePlanExercises: [WorkoutPlanExerciseDTO] = try await client.from("workout_plan_exercises")
            .select()
            .eq("user_id", value: userID.uuidString)
            .execute()
            .value

        var localExercises = indexedBySyncID(
            try context.fetch(FetchDescriptor<Exercise>()),
            getID: { $0.syncID },
            updatedAt: { $0.updatedAt }
        )
        var localSessions = indexedBySyncID(
            try context.fetch(FetchDescriptor<WorkoutSession>()),
            getID: { $0.syncID },
            updatedAt: { $0.updatedAt }
        )
        var localSessionExercises = indexedBySyncID(
            try context.fetch(FetchDescriptor<WorkoutSessionExercise>()),
            getID: { $0.syncID },
            updatedAt: { $0.updatedAt }
        )
        var localSets = indexedBySyncID(
            try context.fetch(FetchDescriptor<WorkoutSet>()),
            getID: { $0.syncID },
            updatedAt: { $0.updatedAt }
        )
        var localPlans = indexedBySyncID(
            try context.fetch(FetchDescriptor<WorkoutPlan>()),
            getID: { $0.syncID },
            updatedAt: { $0.updatedAt }
        )
        var localPlanExercises = indexedBySyncID(
            try context.fetch(FetchDescriptor<WorkoutPlanExercise>()),
            getID: { $0.syncID },
            updatedAt: { $0.updatedAt }
        )

        let builtInByName = Dictionary(
            grouping: try context.fetch(FetchDescriptor<Exercise>()).filter { $0.source == .builtIn },
            by: { $0.name }
        ).compactMapValues(\.first)

        for dto in remoteExercises {
            if let deletedAt = dto.deletedAt {
                if let local = localExercises[dto.id] {
                    if local.updatedAt <= dto.updatedAt {
                        context.delete(local)
                        localExercises.removeValue(forKey: dto.id)
                    }
                }
                _ = deletedAt
                continue
            }
            if let local = localExercises[dto.id] {
                guard dto.updatedAt > local.updatedAt else { continue }
                local.name = dto.name
                local.category = dto.category
                local.searchMetadata = dto.searchMetadata
                local.sourceRawValue = dto.source
                local.isHiddenFromLibrary = dto.isHiddenFromLibrary
                local.loggingTypeRawValue = dto.loggingType
                local.updatedAt = dto.updatedAt
                local.lastSyncedAt = Date()
                local.cloudDeletedAt = nil
            } else {
                let exercise = Exercise(
                    name: dto.name,
                    category: dto.category,
                    searchMetadata: dto.searchMetadata,
                    source: .userSaved,
                    isHiddenFromLibrary: dto.isHiddenFromLibrary,
                    loggingType: dto.loggingType.flatMap(ExerciseLoggingType.init(rawValue:)),
                    syncID: dto.id,
                    updatedAt: dto.updatedAt
                )
                exercise.lastSyncedAt = Date()
                context.insert(exercise)
                localExercises[dto.id] = exercise
            }
        }

        for dto in remoteSessions {
            if let deletedAt = dto.deletedAt {
                if let local = localSessions[dto.id], local.updatedAt <= dto.updatedAt {
                    context.delete(local)
                    localSessions.removeValue(forKey: dto.id)
                }
                _ = deletedAt
                continue
            }
            if let local = localSessions[dto.id] {
                guard dto.updatedAt > local.updatedAt else { continue }
                local.name = dto.name
                local.sessionDate = dto.sessionDate
                local.startedFromPlanTemplate = dto.startedFromPlanTemplate
                local.completedAt = dto.completedAt
                local.updatedAt = dto.updatedAt
                local.lastSyncedAt = Date()
                local.cloudDeletedAt = nil
            } else {
                let session = WorkoutSession(
                    name: dto.name,
                    sessionDate: dto.sessionDate,
                    startedFromPlanTemplate: dto.startedFromPlanTemplate,
                    completedAt: dto.completedAt,
                    syncID: dto.id,
                    updatedAt: dto.updatedAt
                )
                session.lastSyncedAt = Date()
                context.insert(session)
                localSessions[dto.id] = session
            }
        }

        for dto in remoteSessionExercises {
            if let deletedAt = dto.deletedAt {
                if let local = localSessionExercises[dto.id], local.updatedAt <= dto.updatedAt {
                    context.delete(local)
                    localSessionExercises.removeValue(forKey: dto.id)
                }
                _ = deletedAt
                continue
            }
            guard let session = localSessions[dto.sessionId] else { continue }
            let linkedExercise: Exercise? = {
                if let exerciseId = dto.exerciseId {
                    return localExercises[exerciseId]
                }
                if dto.source == ExerciseSource.builtIn.rawValue,
                   let name = dto.builtInExerciseName {
                    return builtInByName[name]
                }
                return nil
            }()

            if let local = localSessionExercises[dto.id] {
                guard dto.updatedAt > local.updatedAt else { continue }
                local.exerciseOrder = dto.exerciseOrder
                local.session = session
                local.exercise = linkedExercise
                local.sourceRawValue = dto.source
                local.customExerciseName = dto.customExerciseName
                local.updatedAt = dto.updatedAt
                local.lastSyncedAt = Date()
                local.cloudDeletedAt = nil
            } else {
                let row = WorkoutSessionExercise(
                    exerciseOrder: dto.exerciseOrder,
                    session: session,
                    exercise: linkedExercise,
                    sourceRawValue: dto.source,
                    customExerciseName: dto.customExerciseName,
                    syncID: dto.id,
                    updatedAt: dto.updatedAt
                )
                row.lastSyncedAt = Date()
                context.insert(row)
                session.sessionExercises.append(row)
                localSessionExercises[dto.id] = row
            }
        }

        for dto in remoteSets {
            if let deletedAt = dto.deletedAt {
                if let local = localSets[dto.id], local.updatedAt <= dto.updatedAt {
                    context.delete(local)
                    localSets.removeValue(forKey: dto.id)
                }
                _ = deletedAt
                continue
            }
            guard let sessionExercise = localSessionExercises[dto.sessionExerciseId] else { continue }
            if let local = localSets[dto.id] {
                guard dto.updatedAt > local.updatedAt else { continue }
                local.setOrder = dto.setOrder
                local.weight = dto.weight
                local.reps = dto.reps
                local.isPendingSuggestion = dto.isPendingSuggestion
                local.restDurationSeconds = dto.restDurationSeconds
                local.durationSeconds = dto.durationSeconds
                local.distanceMeters = dto.distanceMeters
                local.sessionExercise = sessionExercise
                local.updatedAt = dto.updatedAt
                local.lastSyncedAt = Date()
                local.cloudDeletedAt = nil
            } else {
                let set = WorkoutSet(
                    setOrder: dto.setOrder,
                    weight: dto.weight,
                    reps: dto.reps,
                    isPendingSuggestion: dto.isPendingSuggestion,
                    restDurationSeconds: dto.restDurationSeconds,
                    durationSeconds: dto.durationSeconds,
                    distanceMeters: dto.distanceMeters,
                    sessionExercise: sessionExercise,
                    syncID: dto.id,
                    updatedAt: dto.updatedAt
                )
                set.lastSyncedAt = Date()
                context.insert(set)
                sessionExercise.sets.append(set)
                localSets[dto.id] = set
            }
        }

        for dto in remotePlans {
            if let deletedAt = dto.deletedAt {
                if let local = localPlans[dto.id], local.updatedAt <= dto.updatedAt {
                    context.delete(local)
                    localPlans.removeValue(forKey: dto.id)
                }
                _ = deletedAt
                continue
            }
            if let local = localPlans[dto.id] {
                guard dto.updatedAt > local.updatedAt else { continue }
                local.name = dto.name
                local.createdAt = dto.createdAt
                local.updatedAt = dto.updatedAt
                local.lastSyncedAt = Date()
                local.cloudDeletedAt = nil
            } else {
                let plan = WorkoutPlan(
                    name: dto.name,
                    createdAt: dto.createdAt,
                    syncID: dto.id,
                    updatedAt: dto.updatedAt
                )
                plan.lastSyncedAt = Date()
                context.insert(plan)
                localPlans[dto.id] = plan
            }
        }

        for dto in remotePlanExercises {
            if let deletedAt = dto.deletedAt {
                if let local = localPlanExercises[dto.id], local.updatedAt <= dto.updatedAt {
                    context.delete(local)
                    localPlanExercises.removeValue(forKey: dto.id)
                }
                _ = deletedAt
                continue
            }
            guard let plan = localPlans[dto.planId] else { continue }
            let linkedExercise: Exercise? = {
                if let exerciseId = dto.exerciseId {
                    return localExercises[exerciseId]
                }
                if dto.source == ExerciseSource.builtIn.rawValue,
                   let name = dto.builtInExerciseName {
                    return builtInByName[name]
                }
                return nil
            }()

            if let local = localPlanExercises[dto.id] {
                guard dto.updatedAt > local.updatedAt else { continue }
                local.exerciseOrder = dto.exerciseOrder
                local.exercise = linkedExercise
                local.customExerciseName = dto.customExerciseName
                local.sourceRawValue = dto.source
                local.plan = plan
                local.updatedAt = dto.updatedAt
                local.lastSyncedAt = Date()
                local.cloudDeletedAt = nil
            } else {
                let row = WorkoutPlanExercise(
                    exerciseOrder: dto.exerciseOrder,
                    exercise: linkedExercise,
                    customExerciseName: dto.customExerciseName,
                    sourceRawValue: dto.source,
                    plan: plan,
                    syncID: dto.id,
                    updatedAt: dto.updatedAt
                )
                row.lastSyncedAt = Date()
                context.insert(row)
                plan.exercises.append(row)
                localPlanExercises[dto.id] = row
            }
        }
    }

    private func upsertSyncMetadata(client: SupabaseClient, userID: UUID) async throws {
        // One row per user; conflict key is `user_id` (never batched with duplicates).
        let dto = SyncMetadataDTO(
            userId: userID,
            lastSyncedAt: Date(),
            clientDeviceId: clientDeviceID,
            updatedAt: Date()
        )
        try await upsert(client: client, table: "sync_metadata", onConflict: "user_id", rows: [dto])
    }
}
