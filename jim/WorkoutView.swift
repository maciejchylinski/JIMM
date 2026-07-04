import SwiftUI
import SwiftData

struct WorkoutView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var workoutSessionPresentationState: WorkoutSessionPresentationState
    /// Unfiltered fetch so finishing a workout immediately clears resume / New Workout gating.
    @Query(sort: \WorkoutSession.sessionDate, order: .reverse)
    private var allSessionsBySessionDate: [WorkoutSession]

    private var unfinishedSessions: [WorkoutSession] {
        allSessionsBySessionDate.filter { $0.completedAt == nil }
    }

    @State private var newSession: WorkoutSession?
    @State private var sessionWorkoutTitle = "Workout"
    @State private var showSession = false
    @Binding var externalResumeSession: WorkoutSession?

    var body: some View {
        List {
            if let active = activeUnfinishedSession {
                Section {
                    Button {
                        resumeSession(active)
                    } label: {
                        HStack(alignment: .center, spacing: UITheme.spaceM) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Resume Current Workout")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(workoutTitle(for: active))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: UITheme.iconSizeS, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .appRowStyle()
                    }
                    .buttonStyle(.plain)
                }
            }

            Section {
                if activeUnfinishedSession == nil {
                    Button {
                        startEmptySession()
                    } label: {
                        HStack(alignment: .center, spacing: UITheme.spaceM) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("New Workout")
                                    .foregroundStyle(.primary)
                                Text("Start from scratch")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: UITheme.iconSizeS, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .appRowStyle()
                    }
                    .buttonStyle(.plain)
                }

                NavigationLink {
                    RepeatWorkoutHistoryView()
                } label: {
                    HStack(alignment: .center, spacing: UITheme.spaceM) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Repeat Workout")
                                .foregroundStyle(.primary)
                            Text("Start from a finished workout")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .appRowStyle()
                }
                .buttonStyle(.plain)

                NavigationLink {
                    WorkoutProgressView()
                } label: {
                    HStack(alignment: .center, spacing: UITheme.spaceM) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Progress")
                                .foregroundStyle(.primary)
                            Text("Best results from finished workouts")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .appRowStyle()
                }
                .buttonStyle(.plain)
            }

        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(UITheme.appBackground.ignoresSafeArea())
        .navigationTitle("Workout")
        .navigationDestination(isPresented: $showSession) {
            if let session = newSession {
                WorkoutSessionView(session: session, workoutTitle: sessionWorkoutTitle)
            }
        }
        .onChange(of: showSession) { _, isPresented in
            if !isPresented {
                if let session = newSession {
                    workoutSessionPresentationState.unregisterWorkoutSessionView(for: session.persistentModelID)
                }
                newSession = nil
            }
        }
        .onChange(of: externalResumeSession?.persistentModelID) { _, _ in
            guard let session = externalResumeSession else { return }
            resumeSession(session)
            externalResumeSession = nil
        }
        .onAppear {
            guard let session = externalResumeSession else { return }
            resumeSession(session)
            externalResumeSession = nil
        }
    }

    /// Newest unfinished session by `sessionDate` (matches `@Query` sort: reverse sessionDate).
    private var activeUnfinishedSession: WorkoutSession? {
        unfinishedSessions.first
    }

    private func orderedSessionExercises(_ session: WorkoutSession) -> [WorkoutSessionExercise] {
        session.sessionExercises.sorted { $0.exerciseOrder < $1.exerciseOrder }
    }

    private func startEmptySession() {
        if let existing = try? ActiveWorkoutSession.canonicalUnfinishedSessionAfterCleanup(in: modelContext) {
            resumeSession(existing)
            return
        }
        let session = WorkoutSession(sessionDate: Date())
        modelContext.insert(session)
        do {
            try modelContext.save()
        } catch {
        }
        sessionWorkoutTitle = "Workout"
        newSession = session
        workoutSessionPresentationState.registerWorkoutSessionView(for: session.persistentModelID)
        showSession = true
    }

    private func resumeSession(_ session: WorkoutSession) {
        sessionWorkoutTitle = workoutTitle(for: session)
        newSession = session
        workoutSessionPresentationState.registerWorkoutSessionView(for: session.persistentModelID)
        showSession = true
    }

    private func workoutTitle(for session: WorkoutSession) -> String {
        let customName = session.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !customName.isEmpty {
            return customName
        }
        let ordered = orderedSessionExercises(session)
        guard let firstName = ordered.first?.displayName, !firstName.isEmpty else {
            return "Workout"
        }
        if ordered.count == 1 {
            return firstName
        }
        return "\(firstName) +\(ordered.count - 1)"
    }
}

private struct RepeatWorkoutHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WorkoutPlan.createdAt, order: .reverse)
    private var plansByCreatedAt: [WorkoutPlan]
    @Query(sort: \WorkoutSession.completedAt, order: .reverse)
    private var sessionsByCompletedAt: [WorkoutSession]
    @State private var showAllPlans = false
    @State private var createdPlanToOpen: WorkoutPlan?
    @State private var showActiveWorkoutBlockingAlert = false

    private var completedSessions: [WorkoutSession] {
        sessionsByCompletedAt.filter { $0.completedAt != nil }
    }

    private var visiblePlans: [WorkoutPlan] {
        if showAllPlans {
            return plansByCreatedAt
        }
        return Array(plansByCreatedAt.prefix(5))
    }

    private var hasMorePlansToShow: Bool {
        plansByCreatedAt.count > 5 && !showAllPlans
    }

    private var canCollapsePlans: Bool {
        plansByCreatedAt.count > 5 && showAllPlans
    }

    var body: some View {
        List {
            Section("Workout Plans") {
                Button {
                    createdPlanToOpen = WorkoutPlan.insertNewDefault(
                        existingPlanCount: plansByCreatedAt.count,
                        in: modelContext
                    )
                } label: {
                    Label("+ New Workout Plan", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(AccentPlainButtonStyle())

                if plansByCreatedAt.isEmpty {
                    Text("No plans yet. Tap + New Workout Plan to create one.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(visiblePlans) { plan in
                        NavigationLink {
                            WorkoutPlanEditorView(
                                plan: plan,
                                onStartWorkoutFromPlan: { selectedPlan in
                                    startWorkout(from: selectedPlan)
                                }
                            )
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(planTitle(for: plan))
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
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
                    }

                    if hasMorePlansToShow {
                        Button("See More") {
                            showAllPlans = true
                        }
                        .buttonStyle(AccentPlainButtonStyle())
                    } else if canCollapsePlans {
                        Button("See Less") {
                            showAllPlans = false
                        }
                        .buttonStyle(AccentPlainButtonStyle())
                    }
                }
            }

            Section("Recent Workouts") {
                if completedSessions.isEmpty {
                    Text("No finished workouts yet. Start with New Workout.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(completedSessions) { session in
                        NavigationLink {
                            RepeatWorkoutPreviewView(sourceSession: session)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(workoutTitle(for: session))
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                if let completedAt = session.completedAt {
                                    Text(completedAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(UITheme.appBackground.ignoresSafeArea())
        .navigationTitle("Repeat Workout")
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

    private func startWorkout(from plan: WorkoutPlan) {
        WorkoutPlanFlow.startWorkout(from: plan, modelContext: modelContext) {
            showActiveWorkoutBlockingAlert = true
        }
    }

    private func workoutTitle(for session: WorkoutSession) -> String {
        let saved = (session.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !saved.isEmpty {
            return saved
        }
        let ordered = session.sessionExercises.sorted { $0.exerciseOrder < $1.exerciseOrder }
        guard let firstName = ordered.first?.displayName, !firstName.isEmpty else {
            return "Workout"
        }
        if ordered.count == 1 {
            return firstName
        }
        return "\(firstName) +\(ordered.count - 1)"
    }

    private func planTitle(for plan: WorkoutPlan) -> String {
        let trimmed = plan.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Plan" : trimmed
    }

    private func planSummary(for plan: WorkoutPlan) -> String {
        let count = plan.exercises.count
        return count == 1 ? "1 exercise" : "\(count) exercises"
    }
}

private struct RepeatWorkoutPreviewView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var workoutSessionPresentationState: WorkoutSessionPresentationState
    @AppStorage("settings.units") private var unitsRawValue: String = "kg"
    let sourceSession: WorkoutSession

    @State private var newRepeatedSession: WorkoutSession?
    @State private var showRepeatedSession = false
    @State private var showActiveWorkoutBlockingAlert = false

    private var orderedExercises: [WorkoutSessionExercise] {
        sourceSession.sessionExercises.sorted { $0.exerciseOrder < $1.exerciseOrder }
    }

    var body: some View {
        List {
            Section("Workout") {
                Text(workoutTitle(for: sourceSession))
                    .font(.body.weight(.semibold))
            }

            Section("Exercises") {
                if orderedExercises.isEmpty {
                    Text("No exercises in this workout.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(orderedExercises) { sessionExercise in
                        VStack(alignment: .leading, spacing: UITheme.spaceS) {
                            Text(sessionExercise.displayName)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.primary)

                            let orderedSets = sessionExercise.sets.sorted { $0.setOrder < $1.setOrder }
                            if orderedSets.isEmpty {
                                Text("No sets recorded")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(orderedSets) { set in
                                        repeatSetPreviewRow(set, exercise: sessionExercise.exercise)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 2)
                    }
                }
            }

            Section {
                Button {
                    startRepeatedWorkout()
                } label: {
                    Text("Start Workout")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryBottomButtonStyle())
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(UITheme.appBackground.ignoresSafeArea())
        .navigationTitle("Repeat Preview")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showRepeatedSession) {
            if let session = newRepeatedSession {
                WorkoutSessionView(
                    session: session,
                    workoutTitle: workoutTitle(for: session)
                )
            }
        }
        .onChange(of: showRepeatedSession) { _, isPresented in
            if !isPresented {
                if let session = newRepeatedSession {
                    workoutSessionPresentationState.unregisterWorkoutSessionView(for: session.persistentModelID)
                }
                newRepeatedSession = nil
            }
        }
        .alert("Active workout", isPresented: $showActiveWorkoutBlockingAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("You have an active workout. Finish it before starting a new workout.")
        }
    }

    private func startRepeatedWorkout() {
        if (try? ActiveWorkoutSession.canonicalUnfinishedSessionAfterCleanup(in: modelContext)) != nil {
            showActiveWorkoutBlockingAlert = true
            return
        }
        guard let repeated = WorkoutSession.newRepeating(from: sourceSession, in: modelContext) else { return }
        newRepeatedSession = repeated
        workoutSessionPresentationState.registerWorkoutSessionView(for: repeated.persistentModelID)
        showRepeatedSession = true
    }

    private func workoutTitle(for session: WorkoutSession) -> String {
        let saved = (session.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !saved.isEmpty {
            return saved
        }
        let ordered = session.sessionExercises.sorted { $0.exerciseOrder < $1.exerciseOrder }
        guard let firstName = ordered.first?.displayName, !firstName.isEmpty else {
            return "Workout"
        }
        if ordered.count == 1 {
            return firstName
        }
        return "\(firstName) +\(ordered.count - 1)"
    }

    private var weightUnitLabel: String {
        unitsRawValue == "lb" ? "lb" : "kg"
    }

    private func repeatSetPreviewRow(_ set: WorkoutSet, exercise: Exercise?) -> some View {
        HStack(spacing: 6) {
            Text("Set \(set.setOrder)")
                .frame(width: 36, alignment: .leading)

            Text(
                WorkoutSetDisplay.formatLoggedSet(
                    set: set,
                    exercise: exercise,
                    weightUnit: weightUnitLabel
                )
            )
            .frame(maxWidth: .infinity, alignment: .trailing)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.75)

            Spacer(minLength: 0)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

#Preview {
    NavigationStack {
        WorkoutView(externalResumeSession: .constant(nil))
    }
    .environmentObject(WorkoutSessionPresentationState())
}
