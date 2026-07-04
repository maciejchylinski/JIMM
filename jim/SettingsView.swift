import SwiftUI
#if DEBUG
import SwiftData
#endif

struct SettingsView: View {
    private enum UnitsOption: String, CaseIterable, Identifiable {
        case kg
        case lb

        var id: String { rawValue }
        var title: String { rawValue.uppercased() }
    }

    private enum AppearanceOption: String, CaseIterable, Identifiable {
        case system
        case light
        case dark

        var id: String { rawValue }

        var title: String {
            switch self {
            case .system: return "Follow System"
            case .light: return "Light"
            case .dark: return "Dark"
            }
        }
    }

    @AppStorage("settings.units") private var unitsRawValue: String = UnitsOption.kg.rawValue
    @AppStorage("settings.appearance") private var appearanceRawValue: String = AppearanceOption.system.rawValue

#if DEBUG
    @Environment(\.modelContext) private var modelContext
    @AppStorage(DemoDataSeeder.seededDefaultsKey) private var demoDataSeeded = false
#endif

    var body: some View {
        List {
            Section {
                Picker("Units", selection: $unitsRawValue) {
                    ForEach(UnitsOption.allCases) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }
                .foregroundStyle(.primary)
                .tint(.secondary)

                Picker("Appearance", selection: $appearanceRawValue) {
                    ForEach(AppearanceOption.allCases) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }
                .foregroundStyle(.primary)
                .tint(.secondary)

            }

#if DEBUG
            Section {
                Button {
                    seedDemoData()
                } label: {
                    HStack {
                        Label("Seed Demo Data", systemImage: "wand.and.stars")
                            .foregroundStyle(.primary)
                        Spacer(minLength: UITheme.spaceS)
                        if demoDataSeeded {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .disabled(demoDataSeeded)
            } header: {
                Text("Developer")
            } footer: {
                Text(demoDataSeeded
                     ? "Demo data already added. It is created once; delete and reinstall the app to reseed."
                     : "Adds sample workouts, progress, and plans for portfolio screenshots. DEBUG builds only — never shipped in Release.")
            }
#endif
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(UITheme.appBackground.ignoresSafeArea())
        .navigationTitle("Settings")
        .safeAreaInset(edge: .bottom) {
            Text("Version \(appVersionText)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, UITheme.spaceS)
                .padding(.bottom, UITheme.spaceM)
                .background(Color.clear)
        }
    }

    private var appVersionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }

#if DEBUG
    private func seedDemoData() {
        DemoDataSeeder.seed(in: modelContext)
    }
#endif
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}

#if DEBUG

// MARK: - Demo data seeding (DEBUG only, manual)

/// Inserts realistic sample workout history, progress, and plans so portfolio
/// screenshots look populated. Never compiled into Release builds, and only ever
/// runs when the user taps "Seed Demo Data" in Settings.
///
/// Idempotency: a one-time `UserDefaults` flag guards against duplicate seeding,
/// so repeated taps are a no-op after the first. The seed does not delete or modify
/// any existing user data — it only inserts new records that reference built-in
/// catalog exercises.
enum DemoDataSeeder {
    static let seededDefaultsKey = "debug.demoDataSeeded"

    private struct SetSpec {
        let weight: Double
        let reps: Int
    }

    private struct ExerciseSpec {
        let candidateNames: [String]
        let sets: [SetSpec]
    }

    private struct WorkoutSpec {
        let name: String
        let daysAgo: Int
        let exercises: [ExerciseSpec]
    }

    private struct PlanSpec {
        let name: String
        let createdDaysAgo: Int
        let exercises: [[String]]
    }

    // Catalog lookup candidates (first existing match wins).
    private static let pullUp = ["Pull-Up"]
    private static let bench = ["Barbell Bench Press"]
    private static let squat = ["Back Squat", "Barbell Squat", "Squat"]
    private static let latPulldown = ["Lat Pulldown"]
    private static let shoulderPress = ["Dumbbell Shoulder Press"]
    private static let rdl = ["Romanian Deadlift"]

    private static func strengthSets(_ weight: Double, _ reps: Int, count: Int = 3) -> [SetSpec] {
        Array(repeating: SetSpec(weight: weight, reps: reps), count: count)
    }

    /// Bodyweight working sets where the top (first) set is the best, trailing sets taper off.
    private static func bodyweightSets(topReps: Int, count: Int = 3) -> [SetSpec] {
        (0 ..< count).map { index in
            SetSpec(weight: 0, reps: max(1, topReps - index))
        }
    }

    /// 8 finished workouts across ~7 weeks with deterministic progression:
    /// Pull-Up best reps 5 → 7 → 9 → 12 → 15, Bench 80×5 → 85×5 → 90×5 → 100×5,
    /// Squat 100×5 → 110×5 → 120×5.
    private static var workouts: [WorkoutSpec] {
        [
            WorkoutSpec(name: "Push Day", daysAgo: 52, exercises: [
                ExerciseSpec(candidateNames: bench, sets: strengthSets(80, 5)),
                ExerciseSpec(candidateNames: shoulderPress, sets: strengthSets(22.5, 8))
            ]),
            WorkoutSpec(name: "Pull Day", daysAgo: 45, exercises: [
                ExerciseSpec(candidateNames: pullUp, sets: bodyweightSets(topReps: 5)),
                ExerciseSpec(candidateNames: latPulldown, sets: strengthSets(50, 10))
            ]),
            WorkoutSpec(name: "Leg Day", daysAgo: 40, exercises: [
                ExerciseSpec(candidateNames: squat, sets: strengthSets(100, 5)),
                ExerciseSpec(candidateNames: rdl, sets: strengthSets(80, 8))
            ]),
            WorkoutSpec(name: "Upper Body", daysAgo: 33, exercises: [
                ExerciseSpec(candidateNames: bench, sets: strengthSets(85, 5)),
                ExerciseSpec(candidateNames: pullUp, sets: bodyweightSets(topReps: 7)),
                ExerciseSpec(candidateNames: shoulderPress, sets: strengthSets(25, 8))
            ]),
            WorkoutSpec(name: "Pull Day", daysAgo: 24, exercises: [
                ExerciseSpec(candidateNames: pullUp, sets: bodyweightSets(topReps: 9)),
                ExerciseSpec(candidateNames: latPulldown, sets: strengthSets(55, 10))
            ]),
            WorkoutSpec(name: "Full Body", daysAgo: 17, exercises: [
                ExerciseSpec(candidateNames: squat, sets: strengthSets(110, 5)),
                ExerciseSpec(candidateNames: bench, sets: strengthSets(90, 5)),
                ExerciseSpec(candidateNames: pullUp, sets: bodyweightSets(topReps: 12))
            ]),
            WorkoutSpec(name: "Upper Body", daysAgo: 9, exercises: [
                ExerciseSpec(candidateNames: bench, sets: strengthSets(100, 5)),
                ExerciseSpec(candidateNames: pullUp, sets: bodyweightSets(topReps: 15)),
                ExerciseSpec(candidateNames: latPulldown, sets: strengthSets(60, 9)),
                ExerciseSpec(candidateNames: shoulderPress, sets: strengthSets(30, 8))
            ]),
            WorkoutSpec(name: "Leg Day", daysAgo: 3, exercises: [
                ExerciseSpec(candidateNames: squat, sets: strengthSets(120, 5)),
                ExerciseSpec(candidateNames: rdl, sets: strengthSets(100, 6))
            ])
        ]
    }

    private static let plans: [PlanSpec] = [
        PlanSpec(name: "Push Day", createdDaysAgo: 50, exercises: [bench, shoulderPress]),
        PlanSpec(name: "Pull Day", createdDaysAgo: 49, exercises: [pullUp, latPulldown]),
        PlanSpec(name: "Leg Day", createdDaysAgo: 48, exercises: [squat, rdl])
    ]

    @discardableResult
    static func seed(in context: ModelContext, defaults: UserDefaults = .standard) -> Bool {
        guard !defaults.bool(forKey: seededDefaultsKey) else { return false }

        let allExercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        var exercisesByName: [String: Exercise] = [:]
        for exercise in allExercises {
            exercisesByName[exercise.name.lowercased()] = exercise
        }
        func lookup(_ candidates: [String]) -> Exercise? {
            for candidate in candidates {
                if let match = exercisesByName[candidate.lowercased()] { return match }
            }
            return nil
        }

        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        func completion(daysAgo: Int) -> Date {
            let day = calendar.date(byAdding: .day, value: -daysAgo, to: startOfToday) ?? startOfToday
            return calendar.date(bySettingHour: 18, minute: 0, second: 0, of: day) ?? day
        }

        for workout in workouts {
            let completedAt = completion(daysAgo: workout.daysAgo)
            // Make the recorded duration look realistic (~1 hour) without affecting completion ordering.
            let sessionDate = completedAt.addingTimeInterval(-3600)
            let session = WorkoutSession(
                name: workout.name,
                sessionDate: sessionDate,
                startedFromPlanTemplate: nil,
                completedAt: completedAt
            )
            context.insert(session)

            for (exerciseIndex, exerciseSpec) in workout.exercises.enumerated() {
                guard let exercise = lookup(exerciseSpec.candidateNames) else { continue }
                let sessionExercise = WorkoutSessionExercise(
                    exerciseOrder: exerciseIndex + 1,
                    session: session,
                    exercise: exercise,
                    sourceRawValue: exercise.source.rawValue,
                    customExerciseName: nil
                )
                context.insert(sessionExercise)
                session.sessionExercises.append(sessionExercise)

                for (setIndex, setSpec) in exerciseSpec.sets.enumerated() {
                    let set = WorkoutSet(
                        setOrder: setIndex + 1,
                        weight: setSpec.weight,
                        reps: setSpec.reps,
                        isPendingSuggestion: false,
                        restDurationSeconds: 90,
                        sessionExercise: sessionExercise
                    )
                    context.insert(set)
                    sessionExercise.sets.append(set)
                }
            }
        }

        for planSpec in plans {
            let plan = WorkoutPlan(
                name: planSpec.name,
                createdAt: completion(daysAgo: planSpec.createdDaysAgo)
            )
            context.insert(plan)
            for (index, candidates) in planSpec.exercises.enumerated() {
                guard let exercise = lookup(candidates) else { continue }
                let planExercise = WorkoutPlanExercise(
                    exerciseOrder: index + 1,
                    exercise: exercise,
                    customExerciseName: nil,
                    sourceRawValue: exercise.source.rawValue,
                    plan: plan
                )
                context.insert(planExercise)
                plan.exercises.append(planExercise)
            }
        }

        try? context.save()
        defaults.set(true, forKey: seededDefaultsKey)
        return true
    }
}

#endif
