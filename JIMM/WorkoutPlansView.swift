import SwiftUI
import SwiftData
import UIKit

struct WorkoutPlansView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WorkoutPlan.createdAt, order: .reverse) private var plans: [WorkoutPlan]

    @State private var createdPlanToOpen: WorkoutPlan?
    @State private var showActiveWorkoutBlockingAlert = false

    var body: some View {
        List {
            if plans.isEmpty {
                ContentUnavailableView(
                    "No plans yet",
                    systemImage: "list.bullet.clipboard",
                    description: Text("Create a plan, add exercises, then start your workout from it.")
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(plans) { plan in
                    NavigationLink {
                        WorkoutPlanEditorView(
                            plan: plan,
                            onStartWorkoutFromPlan: { selectedPlan in
                                startWorkout(from: selectedPlan)
                            }
                        )
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(displayName(for: plan))
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(planSummary(for: plan))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button {
                            startWorkout(from: plan)
                        } label: {
                            Label("Start", systemImage: "play.fill")
                        }
                        .tint(Color(uiColor: .systemGray4))
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            deletePlan(plan)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(UITheme.appBackground.ignoresSafeArea())
        .navigationTitle("Workout Plans")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    createPlan()
                } label: {
                    Image(systemName: "plus")
                }
                .font(.system(size: UITheme.iconSizeM, weight: .semibold))
                .foregroundStyle(UITheme.accent)
                .accessibilityLabel("Create plan")
            }
        }
        .navigationDestination(item: $createdPlanToOpen) { plan in
            WorkoutPlanEditorView(
                plan: plan,
                onStartWorkoutFromPlan: { selectedPlan in
                    startWorkout(from: selectedPlan)
                }
            )
        }
        .alert("Active workout", isPresented: $showActiveWorkoutBlockingAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("You have an active workout. Finish it before starting a new workout.")
        }
    }

    private func createPlan() {
        createdPlanToOpen = WorkoutPlan.insertNewDefault(existingPlanCount: plans.count, in: modelContext)
    }

    private func deletePlan(_ plan: WorkoutPlan) {
        modelContext.delete(plan)
        try? modelContext.save()
    }

    private func startWorkout(from plan: WorkoutPlan) {
        WorkoutPlanFlow.startWorkout(from: plan, modelContext: modelContext) {
            showActiveWorkoutBlockingAlert = true
        }
    }

    private func displayName(for plan: WorkoutPlan) -> String {
        let trimmed = plan.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Plan" : trimmed
    }

    private func planSummary(for plan: WorkoutPlan) -> String {
        let count = plan.exercises.count
        return count == 1 ? "1 exercise" : "\(count) exercises"
    }
}

struct WorkoutPlanEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var workoutSessionPresentationState: WorkoutSessionPresentationState
    @Bindable var plan: WorkoutPlan

    @State private var showExercisePicker = false
    @State private var startedSession: WorkoutSession?
    @State private var startedSessionTitle = "Workout"
    @State private var showStartedSession = false
    @State private var didHandleEditorExit = false
    @State private var showActiveWorkoutBlockingAlert = false
    @FocusState private var isPlanNameFieldFocused: Bool
    let onStartWorkoutFromPlan: ((WorkoutPlan) -> Void)?

    init(
        plan: WorkoutPlan,
        onStartWorkoutFromPlan: ((WorkoutPlan) -> Void)? = nil
    ) {
        self.plan = plan
        self.onStartWorkoutFromPlan = onStartWorkoutFromPlan
    }

    private var orderedExercises: [WorkoutPlanExercise] {
        plan.exercises.sorted { $0.exerciseOrder < $1.exerciseOrder }
    }

    private var hasExercises: Bool {
        !orderedExercises.isEmpty
    }

    var body: some View {
        List {
            Section("Name") {
                TextField("Plan name", text: $plan.name)
                    .textInputAutocapitalization(.words)
                    .focused($isPlanNameFieldFocused)
            }

            Section("Exercises") {
                if orderedExercises.isEmpty {
                    Text("No exercises yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(orderedExercises) { planExercise in
                        HStack(spacing: UITheme.spaceS) {
                            Image(systemName: "line.3.horizontal")
                                .foregroundStyle(.tertiary)
                            Text(planExercise.displayName)
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                        }
                    }
                    .onDelete(perform: deleteExercises)
                    .onMove(perform: moveExercises)
                }

                Button {
                    showExercisePicker = true
                } label: {
                    Label("Add Exercise", systemImage: "plus.circle.fill")
                }
                .buttonStyle(AccentPlainButtonStyle())
            }

            Section("Actions") {
                Button {
                    startWorkoutFromPlan()
                } label: {
                    Label("Start Workout", systemImage: "play.fill")
                }
                .buttonStyle(AccentPlainButtonStyle())
                .disabled(!hasExercises)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(UITheme.appBackground.ignoresSafeArea())
        .navigationTitle(editorTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
        .sheet(isPresented: $showExercisePicker) {
            NavigationStack {
                WorkoutPlanExercisePickerView(plan: plan)
            }
        }
        .navigationDestination(isPresented: $showStartedSession) {
            if let session = startedSession {
                WorkoutSessionView(session: session, workoutTitle: startedSessionTitle)
            }
        }
        .onChange(of: showStartedSession) { _, isPresented in
            if !isPresented {
                if let session = startedSession {
                    workoutSessionPresentationState.unregisterWorkoutSessionView(for: session.persistentModelID)
                }
                startedSession = nil
            }
        }
        .onDisappear {
            if showExercisePicker || showStartedSession {
                return
            }
            finalizeEditorIfNeeded()
        }
        .alert("Active workout", isPresented: $showActiveWorkoutBlockingAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("You have an active workout. Finish it before starting a new workout.")
        }
    }

    private var editorTitle: String {
        let trimmed = plan.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Plan" : trimmed
    }

    private func deleteExercises(at offsets: IndexSet) {
        var reordered = orderedExercises
        reordered.remove(atOffsets: offsets)
        for (index, item) in reordered.enumerated() {
            item.exerciseOrder = index + 1
        }
        for offset in offsets {
            let item = orderedExercises[offset]
            plan.exercises.removeAll { $0.persistentModelID == item.persistentModelID }
            modelContext.delete(item)
        }
        try? modelContext.save()
    }

    private func moveExercises(from source: IndexSet, to destination: Int) {
        var reordered = orderedExercises
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, item) in reordered.enumerated() {
            item.exerciseOrder = index + 1
        }
        try? modelContext.save()
    }

    private func normalizeExerciseOrder() {
        let reordered = orderedExercises
        for (index, item) in reordered.enumerated() {
            item.exerciseOrder = index + 1
        }
    }

    private func savePlan() {
        normalizeExerciseOrder()
        try? modelContext.save()
    }

    private func startWorkoutFromPlan() {
        guard hasExercises else { return }
        savePlan()
        if let onStartWorkoutFromPlan {
            finalizeEditorAndDismiss()
            DispatchQueue.main.async {
                onStartWorkoutFromPlan(plan)
            }
            return
        }
        if (try? ActiveWorkoutSession.canonicalUnfinishedSessionAfterCleanup(in: modelContext)) != nil {
            showActiveWorkoutBlockingAlert = true
            return
        }
        guard let session = WorkoutSession.newFromPlan(plan, in: modelContext) else { return }
        workoutSessionPresentationState.registerWorkoutSessionView(for: session.persistentModelID)
        startedSession = session
        startedSessionTitle = editorTitle
        showStartedSession = true
    }

    private func finalizeEditorAndDismiss() {
        finalizeEditorIfNeeded()
        dismiss()
    }

    private func finalizeEditorIfNeeded() {
        guard !didHandleEditorExit else { return }
        didHandleEditorExit = true
        normalizeExerciseOrder()
        if orderedExercises.isEmpty {
            modelContext.delete(plan)
        }
        try? modelContext.save()
    }

}

private struct WorkoutPlanExercisePickerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Exercise.name) private var exercises: [Exercise]

    let plan: WorkoutPlan
    @State private var searchText = ""

    /// Built-in and visible user-saved exercises; hidden user-saved are omitted (plans/history keep existing refs).
    private var visiblePickerExercises: [Exercise] {
        exercises.filter { exercise in
            guard exercise.source == .userSaved else { return true }
            return exercise.isHiddenFromLibrary != true
        }
    }

    private var filteredExercises: [Exercise] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return visiblePickerExercises }
        return visiblePickerExercises.filter { exercise in
            exercise.name.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        List {
            ForEach(filteredExercises) { exercise in
                Button {
                    addExerciseToPlan(exercise)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(exercise.name)
                                .foregroundStyle(.primary)
                            Text(exercise.category)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "plus.circle")
                            .font(.system(size: UITheme.iconSizeM, weight: .regular))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Add Exercise")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search exercises")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }

    private func addExerciseToPlan(_ exercise: Exercise) {
        let nextOrder = (plan.exercises.map(\.exerciseOrder).max() ?? 0) + 1
        let item = WorkoutPlanExercise(
            exerciseOrder: nextOrder,
            exercise: exercise,
            customExerciseName: nil,
            sourceRawValue: exercise.source.rawValue,
            plan: plan
        )
        modelContext.insert(item)
        plan.exercises.append(item)
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Shared plan creation / start (Workout tab + Repeat Workout)

extension WorkoutPlan {
    /// Inserts and saves a new plan named `Plan (existingPlanCount + 1)`.
    static func insertNewDefault(existingPlanCount: Int, in context: ModelContext) -> WorkoutPlan {
        let plan = WorkoutPlan(name: "Plan \(existingPlanCount + 1)")
        context.insert(plan)
        try? context.save()
        return plan
    }
}

enum WorkoutPlanFlow {
    /// Starts a session from the plan when no unfinished workout exists; otherwise calls `onBlocked` (e.g. show alert).
    static func startWorkout(from plan: WorkoutPlan, modelContext: ModelContext, onBlocked: () -> Void) {
        if (try? ActiveWorkoutSession.canonicalUnfinishedSessionAfterCleanup(in: modelContext)) != nil {
            onBlocked()
            return
        }
        guard let session = WorkoutSession.newFromPlan(plan, in: modelContext) else { return }
        NotificationCenter.default.post(name: .jimOpenActiveWorkoutSession, object: session)
    }
}

private extension WorkoutPlanExercise {
    var displayName: String {
        if let name = exercise?.name, !name.isEmpty {
            return name
        }
        let custom = customExerciseName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !custom.isEmpty {
            return custom
        }
        return "Exercise"
    }
}
