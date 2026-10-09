import SwiftUI
import SwiftData
import Combine

struct WorkoutExerciseView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("settings.units") private var unitsRawValue: String = "kg"
    @Query(sort: \WorkoutSession.sessionDate, order: .reverse)
    private var allSessions: [WorkoutSession]

    let sessionExercise: WorkoutSessionExercise

    @State private var weightText = ""
    @State private var repsText = ""
    @State private var restStart: Date?
    @State private var restElapsedSeconds: TimeInterval = 0
    @State private var didApplyInitialPrefill = false

    @FocusState private var focusedField: Field?

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private enum Field {
        case weight
        case reps
    }

    private var orderedSets: [WorkoutSet] {
        sessionExercise.sets.sorted { $0.setOrder < $1.setOrder }
    }

    private var exerciseTitle: String {
        sessionExercise.displayName
    }

    /// Most recent set for this exercise from an earlier workout session (not the current one).
    private var previousSessionSet: WorkoutSet? {
        guard let exercise = sessionExercise.exercise,
              let currentSession = sessionExercise.session
        else { return nil }
        return lastSetFromPreviousSessions(
            exercise: exercise,
            currentSession: currentSession,
            sessions: allSessions
        )
    }

    private var restDisplayText: String {
        let s = Int(restElapsedSeconds)
        let m = s / 60
        let r = s % 60
        return String(format: "%d:%02d", m, r)
    }

    private var weightUnitLabel: String {
        unitsRawValue == "lb" ? "lb" : "kg"
    }

    var body: some View {
        Form {
            if let previous = previousSessionSet {
                Section("Previous result") {
                    Text(formatSetLine(previous))
                        .foregroundStyle(.secondary)
                }
            }

            Section("Log Set") {
                TextField("Weight (\(weightUnitLabel))", text: $weightText)
                    .keyboardType(.decimalPad)
                    .focused($focusedField, equals: .weight)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.next)

                TextField("Reps", text: $repsText)
                    .keyboardType(.numberPad)
                    .focused($focusedField, equals: .reps)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Button("Save Set") {
                    focusedField = nil
                    saveSet()
                }
                .disabled(!canSaveSet)
            }

            if restStart != nil {
                Section("Rest") {
                    Text("Rest: \(restDisplayText)")
                        .font(.title3.monospacedDigit())
                }
            }

            Section("Sets") {
                if orderedSets.isEmpty {
                    Text("No sets logged yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(orderedSets) { set in
                        Text(formatSetLine(set))
                    }
                }
            }
        }
        .navigationTitle(exerciseTitle)
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            applyInitialPrefillIfNeeded()
        }
        .onReceive(tick) { _ in
            guard let restStart else { return }
            restElapsedSeconds = Date().timeIntervalSince(restStart)
        }
    }

    private func applyInitialPrefillIfNeeded() {
        guard !didApplyInitialPrefill else { return }
        didApplyInitialPrefill = true

        if let lastCurrent = sessionExercise.sets.sorted(by: { $0.setOrder > $1.setOrder }).first {
            applyPrefill(from: lastCurrent)
        } else if let previous = previousSessionSet {
            applyPrefill(from: previous)
        }
    }

    private func applyPrefill(from set: WorkoutSet) {
        weightText = formatWeightForField(set.weight)
        repsText = "\(set.reps)"
    }

    private func lastSetFromPreviousSessions(
        exercise: Exercise,
        currentSession: WorkoutSession,
        sessions: [WorkoutSession]
    ) -> WorkoutSet? {
        let exerciseID = exercise.persistentModelID
        let currentID = currentSession.persistentModelID

        let candidates = sessions.filter { session in
            session.completedAt != nil && session.persistentModelID != currentID
        }
        .sorted {
            ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast)
        }

        for session in candidates {
            guard let match = session.sessionExercises.first(where: {
                $0.exercise?.persistentModelID == exerciseID
            }) else { continue }

            let sortedSets = match.sets.sorted { $0.setOrder > $1.setOrder }
            if let last = sortedSets.first {
                return last
            }
        }
        return nil
    }

    private var canSaveSet: Bool {
        parsedWeight != nil && parsedReps != nil
    }

    private var parsedWeight: Double? {
        let t = weightText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let v = Double(t), v >= 0 else { return nil }
        return v
    }

    private var parsedReps: Int? {
        let t = repsText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let v = Int(t), v > 0 else { return nil }
        return v
    }

    private func saveSet() {
        guard let weight = parsedWeight, let reps = parsedReps else { return }

        let nextOrder = (sessionExercise.sets.map(\.setOrder).max() ?? 0) + 1
        let newSet = WorkoutSet(
            setOrder: nextOrder,
            weight: weight,
            reps: reps,
            sessionExercise: sessionExercise
        )
        modelContext.insert(newSet)
        sessionExercise.sets.append(newSet)

        restStart = Date()
        restElapsedSeconds = 0
    }

    private func formatWeightForField(_ weight: Double) -> String {
        WeightUnitFormatting.formatWeight(fromStoredKg: weight, unit: weightUnitLabel)
    }

    private func formatSetLine(_ set: WorkoutSet) -> String {
        let weightStr = formatWeightForField(set.weight)
        return "Set \(set.setOrder) — \(weightStr) \(weightUnitLabel) × \(set.reps)"
    }
}

#Preview {
    NavigationStack {
        WorkoutExerciseView(sessionExercise: WorkoutSessionExercise(exerciseOrder: 1))
    }
}
