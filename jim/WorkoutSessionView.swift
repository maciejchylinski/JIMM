import SwiftUI
import SwiftData
import Combine
import UIKit

// MARK: - Set entry keypad session

private enum SetEntryField: String {
    case weight
    case reps
    case duration
    case distance
}

/// How a set row captures logged performance (strength, bodyweight, duration, or cardio).
private enum SetRowLoggingMode {
    case strength
    case bodyweight
    case duration
    case cardio

    static func from(exercise: Exercise?) -> SetRowLoggingMode {
        switch exercise?.loggingType {
        case .bodyweight: return .bodyweight
        case .duration, .mobility: return .duration
        case .cardio: return .cardio
        default: return .strength
        }
    }

    var exerciseLoggingType: ExerciseLoggingType {
        switch self {
        case .strength: return .strength
        case .bodyweight: return .bodyweight
        case .duration: return .duration
        case .cardio: return .cardio
        }
    }
}

enum WorkoutDurationFormat {
    /// e.g. `0:30`, `1:00`, `10:05`
    static func display(seconds: Int) -> String {
        let clamped = max(0, seconds)
        let minutes = clamped / 60
        let remainder = clamped % 60
        return String(format: "%d:%02d", minutes, remainder)
    }

    /// Digit-only buffer as mm:ss entry: last two digits are seconds (max 59), prefix is minutes.
    static func seconds(fromDigitBuffer digits: String) -> Int {
        let trimmed = digits.filter(\.isNumber)
        guard !trimmed.isEmpty, let _ = Int(trimmed) else { return 0 }
        if trimmed.count <= 2 {
            return Int(trimmed) ?? 0
        }
        let secDigits = trimmed.suffix(2)
        let minDigits = trimmed.dropLast(2)
        let secondsPart = min(Int(secDigits) ?? 0, 59)
        let minutesPart = Int(minDigits) ?? 0
        return minutesPart * 60 + secondsPart
    }

    /// Reconstructs the digit buffer used while editing from stored seconds.
    static func digitBuffer(fromSeconds seconds: Int) -> String {
        guard seconds > 0 else { return "" }
        let minutes = seconds / 60
        let remainder = seconds % 60
        if minutes == 0 {
            return String(remainder)
        }
        return "\(minutes)\(String(format: "%02d", remainder))"
    }
}

enum WorkoutDistanceFormat {
    /// e.g. `1.0 km`, `3.25 km` (metric display; stored as meters).
    static func displayKilometers(meters: Double) -> String {
        let km = meters / 1000.0
        if km == 0 {
            return "0.0 km"
        }
        if abs(km.truncatingRemainder(dividingBy: 1)) < 0.000_001 {
            return String(format: "%.1f km", km)
        }
        if (km * 100).rounded() == (km * 100) {
            return String(format: "%.2f km", km)
        }
        return String(format: "%.1f km", km)
    }

    /// Compact previous cell suffix, e.g. `3.2 km`.
    static func displayCompactKilometers(meters: Double) -> String {
        let km = meters / 1000.0
        if km == 0 {
            return "0.0 km"
        }
        let roundedOne = (km * 10).rounded() / 10
        if abs(km - roundedOne) < 0.05 {
            return String(format: "%.1f km", roundedOne)
        }
        return String(format: "%.2f km", km)
    }

    static func kmText(fromMeters meters: Double?) -> String {
        guard let meters, meters > 0 else { return "" }
        let km = meters / 1000.0
        if km.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.1f", km)
        }
        if (km * 100).rounded() == (km * 100) {
            return String(format: "%.2f", km)
        }
        return String(format: "%g", km)
    }
}

private enum SetEntryKeyCommand: String {
    case digit
    case dot
    case multiply
    case backspace
    case previous
    case done
}

private struct SetEntryPreviousValue {
    let weight: Double
    let reps: Int
    let durationSeconds: Int?
    let distanceMeters: Double?
}

@MainActor
@Observable
private final class SetEntryKeypadSession {
    private(set) var activeSetID: PersistentIdentifier?
    private(set) var activeSessionExerciseID: PersistentIdentifier?
    private(set) var activeField: SetEntryField?
    private(set) var canUsePrevious = false
    private var commandHandler: ((SetEntryKeyCommand, String?) -> Void)?
    private var dismissHandler: (() -> Void)?
    /// Fired when a set field gains focus (including weight → reps via ×).
    var onFocusChanged: ((PersistentIdentifier, PersistentIdentifier) -> Void)?

    func focus(
        setID: PersistentIdentifier,
        sessionExerciseID: PersistentIdentifier,
        field: SetEntryField,
        canUsePrevious: Bool,
        onCommand: @escaping (SetEntryKeyCommand, String?) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        if let activeSetID, activeSetID != setID {
            dismissHandler?()
        }
        activeSetID = setID
        activeSessionExerciseID = sessionExerciseID
        activeField = field
        self.canUsePrevious = canUsePrevious
        commandHandler = onCommand
        dismissHandler = onDismiss
        onFocusChanged?(setID, sessionExerciseID)
    }

    func blur(setID: PersistentIdentifier) {
        guard activeSetID == setID else { return }
        activeSetID = nil
        activeSessionExerciseID = nil
        activeField = nil
        canUsePrevious = false
        commandHandler = nil
        dismissHandler = nil
    }

    func send(_ command: SetEntryKeyCommand, value: String? = nil) {
        commandHandler?(command, value)
    }

    func dismiss() {
        dismissHandler?()
    }
}

private struct SetEntryKeypadPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.45 : 1)
    }
}

// MARK: - Active workout visual theme

private enum WorkoutLogTheme {
    static let background = UITheme.appBackground
    static let surface = UITheme.cardBackground
    static let surfaceStroke = UITheme.stroke
    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary
    static let textMuted = Color(uiColor: .tertiaryLabel)
    static let accent = UITheme.accent
    /// Column widths: Set + Previous fixed; Spacer flexes; kg × reps cluster fixed at trailing edge.
    static let colSet: CGFloat = 28
    /// Trailing space for delete-mode control (matches set confirm checkmark tap target).
    static let colDelete: CGFloat = 44
    /// Narrow column; values scale down. Inputs keep priority width (`colKgReps`).
    static let colPrevious: CGFloat = 56
    static let colKgReps: CGFloat = 178
    static let colTableSpacing: CGFloat = 8
    /// Minimum height for kg/reps fields (gym-friendly tap targets)
    static let setInputMinHeight: CGFloat = 44
    /// Horizontal spacing inside kg × reps cluster
    static let setInputClusterSpacing: CGFloat = 10
}

private struct WorkoutBottomAccessoryCenterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.55 : 1)
    }
}

struct WorkoutSessionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var workoutSessionPresentationState: WorkoutSessionPresentationState
    @EnvironmentObject private var restTimerLiveActivityManager: RestTimerLiveActivityManager
    @Query(sort: \WorkoutSession.sessionDate, order: .reverse)
    private var allSessions: [WorkoutSession]

    let session: WorkoutSession
    let workoutTitle: String

    @State private var showAddExercisePanel = false
    @State private var isExerciseReorderMode = false
    /// Briefly blocks outside-tap reorder exit right after a drag-reorder completes.
    @State private var suppressExerciseReorderExitUntil = Date.distantPast
    @State private var showFinishConfirmation = false
    @State private var showIncompleteSetsFinishWarning = false
    @State private var showSaveAsTemplatePrompt = false
    @State private var saveAsTemplateNameDraft = ""
    @State private var showWorkoutFinishSummary = false
    @State private var showDiscardConfirmation = false
    @State private var repeatTargetSession: WorkoutSession?
    @State private var repeatTargetTitle = "Workout"
    @State private var showRepeatTarget = false
    @State private var isEditingWorkoutName = false
    @State private var workoutNameDraft = ""
    @State private var isWorkoutNameFocused = false
    @AppStorage("settings.units") private var unitsRawValue: String = "kg"
    @State private var setEntryKeypadSession = SetEntryKeypadSession()
    @State private var activeSetEntryID: PersistentIdentifier?
    @State private var activeSessionExerciseID: PersistentIdentifier?
    @State private var exerciseScrollTargetID: PersistentIdentifier?
    @State private var exerciseScrollRequest: UInt = 0
    @State private var setDeleteModeExerciseID: PersistentIdentifier?

    private var orderedSessionExercises: [WorkoutSessionExercise] {
        session.sessionExercises.sorted { $0.exerciseOrder < $1.exerciseOrder }
    }

    private var canEditStructure: Bool {
        session.completedAt == nil
    }

    private var hasMeaningfulLoggedContent: Bool {
        session.sessionExercises.contains { !$0.sets.isEmpty }
    }

    /// Pending suggestion rows or sets that fail logging-type completion rules.
    private var hasIncompleteSets: Bool {
        session.sessionExercises.contains { exercise in
            exercise.sets.contains {
                WorkoutSetLoggingRules.isIncompleteForFinish(
                    set: $0,
                    loggingType: exercise.exercise?.loggingType
                )
            }
        }
    }

    private func normalizeIncompleteSetsForFinish() {
        for sessionExercise in session.sessionExercises {
            for set in sessionExercise.sets
                where WorkoutSetLoggingRules.isIncompleteForFinish(
                    set: set,
                    loggingType: sessionExercise.exercise?.loggingType
                ) {
                set.weight = 0
                set.reps = 0
                set.durationSeconds = nil
                set.distanceMeters = nil
                set.isPendingSuggestion = false
            }
        }
        modelContext.processPendingChanges()
    }

    private var displayWorkoutTitle: String {
        let custom = session.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !custom.isEmpty { return custom }
        return workoutTitle
    }

    private var sessionDateText: String {
        session.sessionDate.formatted(date: .abbreviated, time: .shortened)
    }

    private var fixedCompletedDurationSeconds: TimeInterval? {
        guard let completedAt = session.completedAt else { return nil }
        return max(0, completedAt.timeIntervalSince(session.sessionDate))
    }

    private var finishedSummaryDurationText: String {
        guard let end = session.completedAt else { return "—" }
        let totalSeconds = max(0, Int(end.timeIntervalSince(session.sessionDate)))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d h %d min", hours, minutes)
        }
        if minutes > 0 {
            return String(format: "%d min %d sec", minutes, seconds)
        }
        return String(format: "%d sec", seconds)
    }

    private var finishedSummaryExerciseCount: Int {
        orderedSessionExercises.count
    }

    private var finishedSummarySetCount: Int {
        orderedSessionExercises.reduce(0) { $0 + $1.sets.count }
    }

    /// Σ(weight × reps) where `weight` is always stored in kilograms. Non-strength sets are excluded.
    private var finishedSummaryVolumeKg: Double {
        orderedSessionExercises.reduce(0) { total, sessionExercise in
            total + sessionExercise.sets.reduce(0) { setTotal, set in
                setTotal + WorkoutSetDisplay.volumeKg(set: set, exercise: sessionExercise.exercise)
            }
        }
    }

    private var finishedSummaryVolumeDisplay: String {
        WorkoutSetDisplay.formatVolumeDisplay(
            kg: finishedSummaryVolumeKg,
            weightUnit: unitsRawValue == "lb" ? "lb" : "kg"
        )
    }

    private var finishedSummaryVolumeUnit: String {
        unitsRawValue == "lb" ? "lb" : "kg"
    }

    private var finishedSummaryDateText: String {
        guard let completedAt = session.completedAt else { return "—" }
        return completedAt.formatted(date: .abbreviated, time: .omitted)
    }

    private var finishedSummaryShareStickerContent: WorkoutShareStickerContent {
        WorkoutShareStickerContent(
            workoutTitle: displayWorkoutTitle,
            finishedDateText: finishedSummaryDateText,
            durationText: finishedSummaryDurationText,
            volumeDisplay: finishedSummaryVolumeDisplay,
            volumeUnit: finishedSummaryVolumeUnit,
            exerciseCount: finishedSummaryExerciseCount
        )
    }

    /// Newest unfinished session that should drive live timer updates.
    private var activeUnfinishedSessionID: PersistentIdentifier? {
        allSessions.first(where: { $0.completedAt == nil })?.persistentModelID
    }

    /// Live timer only for the current active unfinished workout.
    private var isLiveWorkoutTimer: Bool {
        guard session.completedAt == nil else { return false }
        return session.persistentModelID == activeUnfinishedSessionID
    }

    private var isSetEntryKeypadVisible: Bool {
        setEntryKeypadSession.activeSetID != nil
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
        List {
            sessionHeaderBlock
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 20)
                .moveDisabled(true)
                .background {
                    if isExerciseReorderMode,
                       !isSetEntryKeypadVisible,
                       !isEditingWorkoutName,
                       !isWorkoutNameFocused {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture {
                                exitExerciseReorderMode()
                            }
                    } else if setDeleteModeExerciseID != nil,
                              !isSetEntryKeypadVisible,
                              !isEditingWorkoutName,
                              !isWorkoutNameFocused {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture {
                                exitSetDeleteMode()
                            }
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

            if orderedSessionExercises.isEmpty {
                emptyWorkoutBlock
                    .padding(.horizontal, 16)
                    .moveDisabled(true)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            } else {
                if canEditStructure, !isExerciseReorderMode {
                    exerciseReorderControlRow
                        .moveDisabled(true)
                }

                Section {
                    ForEach(orderedSessionExercises) { sessionExercise in
                        exerciseSectionView(sessionExercise)
                            .id(sessionExercise.persistentModelID)
                            .moveDisabled(!canEditStructure || !isExerciseReorderMode)
                            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 12, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                    .onMove(perform: moveExercises)
                }

                if isExerciseReorderMode {
                    Color.clear
                        .frame(maxWidth: .infinity, minHeight: 120)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            exitExerciseReorderMode()
                        }
                        .accessibilityLabel("Exit reorder mode")
                        .accessibilityAddTraits(.isButton)
                        .moveDisabled(true)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                } else if setDeleteModeExerciseID != nil {
                    Color.clear
                        .frame(maxWidth: .infinity, minHeight: 120)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            exitSetDeleteMode()
                        }
                        .accessibilityLabel("Exit delete set mode")
                        .accessibilityAddTraits(.isButton)
                        .moveDisabled(true)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
            }
        }
        .environment(\.editMode, .constant(isExerciseReorderMode ? .active : .inactive))
        .onChange(of: exerciseScrollRequest) { _, _ in
            guard let exerciseID = exerciseScrollTargetID else { return }
            scrollToExercise(exerciseID, using: scrollProxy)
        }
        }
        .environment(setEntryKeypadSession)
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .contentMargins(
            .bottom,
            isSetEntryKeypadVisible ? 16 : 0,
            for: .scrollContent
        )
        .simultaneousGesture(
            TapGesture().onEnded {
                if isWorkoutNameFocused && isEditingWorkoutName {
                    finishWorkoutNameEditing()
                }
                if isSetEntryKeypadVisible {
                    dismissKeyboard()
                }
            }
        )
        .background(WorkoutLogTheme.background)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(WorkoutLogTheme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarLeading) {
                Button {
                    dismissFromNavigationUnpublishingPresentation()
                } label: {
                    Image(systemName: "chevron.backward")
                        .font(.system(size: 17, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(WorkoutLogTheme.accent)
                .accessibilityLabel("Back")

                if canEditStructure {
                    Button("Discard", role: .destructive) {
                        showDiscardConfirmation = true
                    }
                    .fontWeight(.semibold)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if canEditStructure {
                    if isExerciseReorderMode {
                        Button("Done") {
                            finishExerciseReorderMode()
                        }
                        .fontWeight(.semibold)
                        .foregroundStyle(WorkoutLogTheme.accent)
                    } else {
                        Button("Finish") {
                            if hasIncompleteSets {
                                showIncompleteSetsFinishWarning = true
                            } else {
                                showFinishConfirmation = true
                            }
                        }
                        .fontWeight(.semibold)
                        .foregroundStyle(WorkoutLogTheme.accent)
                    }
                } else {
                    Button("Repeat Workout") {
                        repeatWorkout()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(WorkoutLogTheme.accent)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isSetEntryKeypadVisible {
                SetEntryKeypad(
                    isPreviousEnabled: setEntryKeypadSession.canUsePrevious,
                    onDigit: { setEntryKeypadSession.send(.digit, value: $0) },
                    onDot: { setEntryKeypadSession.send(.dot) },
                    onMultiply: { setEntryKeypadSession.send(.multiply) },
                    onBackspace: { setEntryKeypadSession.send(.backspace) },
                    onPrevious: { setEntryKeypadSession.send(.previous) },
                    onDone: { setEntryKeypadSession.send(.done) }
                )
            } else if session.completedAt == nil && !showAddExercisePanel {
                HStack(alignment: .center, spacing: UITheme.spaceS) {
                    workoutBottomAccessoryTimerArea(
                        label: "Rest",
                        contentAlignment: .leading
                    ) {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(
                                workoutSessionPresentationState.restTimerText(
                                    for: session.persistentModelID,
                                    now: context.date
                                )
                            )
                        }
                    }
                    Button {
                        var transaction = Transaction()
                        transaction.animation = nil
                        withTransaction(transaction) {
                            showAddExercisePanel = true
                        }
                    } label: {
                        Label {
                            Text("Exercise")
                                .font(.subheadline.weight(.semibold))
                        } icon: {
                            Image(systemName: "plus")
                                .font(.system(size: UITheme.iconSizeM, weight: .semibold))
                        }
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(WorkoutLogTheme.accent)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: UITheme.mainBottomBarChromeMinHeight)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(WorkoutBottomAccessoryCenterButtonStyle())
                    .accessibilityLabel("Add Exercise")
                    workoutBottomAccessoryTimerArea(
                        label: "Workout",
                        contentAlignment: .trailing
                    ) {
                        WorkoutElapsedTimerText(
                            sessionDate: session.sessionDate,
                            fixedCompletedDurationSeconds: fixedCompletedDurationSeconds,
                            isLive: isLiveWorkoutTimer
                        )
                    }
                }
                .frame(minHeight: UITheme.mainBottomBarChromeMinHeight)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: UITheme.mainBottomBarChromeCornerRadius, style: .continuous)
                        .fill(UITheme.cardBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: UITheme.mainBottomBarChromeCornerRadius, style: .continuous)
                        .stroke(
                            UITheme.stroke.opacity(UITheme.mainBottomBarChromeStrokeOpacity),
                            lineWidth: 0.65
                        )
                )
                .padding(.horizontal, UITheme.spaceL)
                .padding(.top, 6)
                .padding(.bottom, 10)
            }
        }
        .fullScreenCover(isPresented: $showAddExercisePanel) {
            SessionAddExercisePickerView(
                session: session,
                isPresented: $showAddExercisePanel
            )
        }
        .alert(
            "Finish this workout?",
            isPresented: $showFinishConfirmation
        ) {
            Button("Finish Workout") {
                finishWorkout()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will complete your workout session.")
        }
        .alert(
            "Unfinished sets",
            isPresented: $showIncompleteSetsFinishWarning
        ) {
            Button("Finish Anyway") {
                normalizeIncompleteSetsForFinish()
                finishWorkout()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Some sets are incomplete. Finish them or leave them empty before completing this workout."
            )
        }
        .alert(
            "Discard this workout?",
            isPresented: $showDiscardConfirmation
        ) {
            Button("Discard Workout", role: .destructive) {
                discardWorkout()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
        .alert(
            "Save as Template?",
            isPresented: $showSaveAsTemplatePrompt
        ) {
            TextField("Template name", text: $saveAsTemplateNameDraft)
            Button("Save as Template") {
                saveFinishedWorkoutAsTemplate(named: saveAsTemplateNameDraft)
                unregisterThisWorkoutSessionFromPresentation()
                dismiss()
            }
            Button("Skip") {
                unregisterThisWorkoutSessionFromPresentation()
                dismiss()
            }
        } message: {
            Text("Save this workout structure as a reusable template. You can edit the name before saving.")
        }
        .sheet(isPresented: $showWorkoutFinishSummary) {
            WorkoutFinishSummaryView(
                workoutTitle: displayWorkoutTitle,
                shareStickerContent: finishedSummaryShareStickerContent,
                durationText: finishedSummaryDurationText,
                exerciseCount: finishedSummaryExerciseCount,
                setCount: finishedSummarySetCount,
                volumeDisplay: finishedSummaryVolumeDisplay,
                volumeUnit: finishedSummaryVolumeUnit,
                onDone: dismissWorkoutFinishSummary
            )
        }
        .navigationDestination(isPresented: $showRepeatTarget) {
            if let repeatTargetSession {
                WorkoutSessionView(
                    session: repeatTargetSession,
                    workoutTitle: repeatTargetTitle
                )
            }
        }
        .onChange(of: showRepeatTarget) { _, isPresented in
            if !isPresented {
                repeatTargetSession = nil
            }
        }
        .onAppear {
            workoutSessionPresentationState.registerWorkoutSessionView(for: session.persistentModelID)
            setEntryKeypadSession.onFocusChanged = { setID, sessionExerciseID in
                activeSetEntryID = setID
                activeSessionExerciseID = sessionExerciseID
                exerciseScrollTargetID = sessionExerciseID
                exerciseScrollRequest &+= 1
            }
            syncWorkoutNameDraftWhenNotEditing()
            publishLiveActivityIfResting()
        }
        .onChange(of: setEntryKeypadSession.activeSetID) { _, setID in
            if setID == nil {
                activeSetEntryID = nil
                activeSessionExerciseID = nil
                exerciseScrollTargetID = nil
            }
        }
        .onDisappear {
            if session.completedAt == nil {
                commitWorkoutNameDraftIfNeeded()
            }
            workoutSessionPresentationState.unregisterWorkoutSessionView(for: session.persistentModelID)
        }
        .onChange(of: session.completedAt) { _, completedAt in
            if completedAt != nil {
                clearRestTimerAndLiveActivity()
            }
        }
        .onChange(of: session.name) { _, _ in
            syncWorkoutNameDraftWhenNotEditing()
        }
    }

    private func scrollToExercise(_ exerciseID: PersistentIdentifier, using scrollProxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                scrollProxy.scrollTo(exerciseID, anchor: .center)
            }
        }
    }

    /// Removes this session from global presentation tracking so the tab mini bar can show immediately.
    /// Safe to call multiple times. `onDisappear` also unregisters as a fallback (e.g. interactive pop).
    private func unregisterThisWorkoutSessionFromPresentation() {
        workoutSessionPresentationState.unregisterWorkoutSessionView(for: session.persistentModelID)
    }

    /// User explicitly leaves this screen via the toolbar back control: unregister first, then pop.
    private func dismissFromNavigationUnpublishingPresentation() {
        dismissKeyboard()
        unregisterThisWorkoutSessionFromPresentation()
        dismiss()
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
        setEntryKeypadSession.dismiss()
    }

    private func finishExerciseReorderMode() {
        guard isExerciseReorderMode else { return }
        withAnimation(.easeInOut(duration: 0.16)) {
            isExerciseReorderMode = false
        }
    }

    private func enterExerciseReorderMode() {
        dismissKeyboard()
        exitSetDeleteMode()
        withAnimation(.easeInOut(duration: 0.16)) {
            isExerciseReorderMode = true
        }
    }

    private func exitExerciseReorderMode() {
        guard isExerciseReorderMode else { return }
        guard Date() >= suppressExerciseReorderExitUntil else { return }
        finishExerciseReorderMode()
    }

    private var sessionHeaderBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: UITheme.spaceS) {
                Group {
                    if canEditStructure {
                        if isEditingWorkoutName {
                            SelectAllWorkoutTitleTextField(
                                text: $workoutNameDraft,
                                isFocused: $isWorkoutNameFocused,
                                placeholder: "Workout name",
                                onCommit: finishWorkoutNameEditing
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .onChange(of: isWorkoutNameFocused) { _, focused in
                                if !focused && isEditingWorkoutName {
                                    finishWorkoutNameEditing()
                                }
                            }
                        } else {
                            Button {
                                beginWorkoutNameEditing()
                            } label: {
                                HStack(spacing: 6) {
                                    Text(displayWorkoutTitle)
                                        .font(.title3.weight(.bold))
                                        .foregroundStyle(WorkoutLogTheme.textPrimary)
                                        .lineLimit(2)
                                    Image(systemName: "pencil.line")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(WorkoutLogTheme.textSecondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        Text(displayWorkoutTitle)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(WorkoutLogTheme.textPrimary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

            }

            HStack(alignment: .firstTextBaseline) {
                Text("Started")
                    .font(.caption)
                    .foregroundStyle(WorkoutLogTheme.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.6)
                Spacer()
                Text(sessionDateText)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(WorkoutLogTheme.textPrimary)
            }

            HStack(alignment: .firstTextBaseline) {
                Text("Time")
                    .font(.caption)
                    .foregroundStyle(WorkoutLogTheme.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.6)
                Spacer()
                WorkoutElapsedTimerText(
                    sessionDate: session.sessionDate,
                    fixedCompletedDurationSeconds: fixedCompletedDurationSeconds,
                    isLive: isLiveWorkoutTimer,
                    font: .system(size: 28, weight: .medium, design: .rounded)
                )
                .foregroundStyle(WorkoutLogTheme.textPrimary)
            }
        }
    }

    /// Scrollable List row above exercises; enters reorder mode (Done lives in the toolbar).
    private var exerciseReorderControlRow: some View {
        HStack {
            Spacer()
            Button("Reorder") {
                enterExerciseReorderMode()
            }
            .buttonStyle(AccentPlainButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.top, 2)
        .padding(.bottom, 8)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private func beginWorkoutNameEditing() {
        dismissKeyboard()
        workoutNameDraft = displayWorkoutTitle
        isEditingWorkoutName = true
        DispatchQueue.main.async {
            isWorkoutNameFocused = true
        }
    }

    private func finishWorkoutNameEditing() {
        commitWorkoutNameDraftIfNeeded()
        isEditingWorkoutName = false
        isWorkoutNameFocused = false
        workoutNameDraft = displayWorkoutTitle
    }

    private func syncWorkoutNameDraftWhenNotEditing() {
        guard !isEditingWorkoutName, !isWorkoutNameFocused else { return }
        workoutNameDraft = displayWorkoutTitle
    }

    private func commitWorkoutNameDraftIfNeeded() {
        let trimmed = workoutNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let newName: String? = trimmed.isEmpty ? nil : trimmed
        if session.name != newName {
            session.name = newName
            modelContext.processPendingChanges()
            try? modelContext.save()
        }
    }

    private var emptyWorkoutBlock: some View {
        VStack(spacing: 12) {
            Image(systemName: "figure.run")
                .font(.title2)
                .foregroundStyle(WorkoutLogTheme.textMuted)
            Text("Empty Workout")
                .font(.headline)
                .foregroundStyle(WorkoutLogTheme.textPrimary)
            Text("Add your first exercise to start logging sets.")
                .font(.subheadline)
                .foregroundStyle(WorkoutLogTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func addSet(to sessionExercise: WorkoutSessionExercise) {
        let nextOrder = (sessionExercise.sets.map(\.setOrder).max() ?? 0) + 1
        let seeded = seededPendingValues(for: sessionExercise, setOrder: nextOrder)
        let fields = pendingSetFields(
            for: sessionExercise.exercise?.loggingType,
            seeded: seeded
        )
        let newSet = WorkoutSet(
            setOrder: nextOrder,
            weight: fields.weight,
            reps: fields.reps,
            isPendingSuggestion: true,
            durationSeconds: fields.durationSeconds,
            distanceMeters: fields.distanceMeters,
            sessionExercise: sessionExercise
        )
        modelContext.insert(newSet)
        sessionExercise.sets.append(newSet)
        modelContext.processPendingChanges()
        try? modelContext.save()
    }

    private func seededPendingValues(
        for sessionExercise: WorkoutSessionExercise,
        setOrder: Int
    ) -> (weight: Double, reps: Int, durationSeconds: Int?, distanceMeters: Double?) {
        guard let exerciseID = sessionExercise.exercise?.persistentModelID else {
            return (0, 0, nil, nil)
        }
        let currentSessionID = session.persistentModelID
        let previousSessions = allSessions
            .filter { $0.completedAt != nil && $0.persistentModelID != currentSessionID }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }

        for previousSession in previousSessions {
            let matchingExercise = previousSession.sessionExercises
                .filter { $0.exercise?.persistentModelID == exerciseID }
                .sorted { $0.exerciseOrder < $1.exerciseOrder }
                .first
            guard let matchingExercise else { continue }
            let previousSet = matchingExercise.sets.first { $0.setOrder == setOrder }
            if let previousSet {
                return (
                    previousSet.weight,
                    previousSet.reps,
                    previousSet.durationSeconds,
                    previousSet.distanceMeters
                )
            }
        }
        return (0, 0, nil, nil)
    }

    private func finishWorkout() {
        guard hasMeaningfulLoggedContent else {
            clearRestTimerAndLiveActivity()
            unregisterThisWorkoutSessionFromPresentation()
            modelContext.delete(session)
            try? modelContext.save()
            dismiss()
            return
        }
        session.completedAt = Date()
        clearRestTimerAndLiveActivity()
        modelContext.processPendingChanges()
        try? modelContext.save()
        showWorkoutFinishSummary = true
    }

    private func dismissWorkoutFinishSummary() {
        showWorkoutFinishSummary = false
        let offerTemplate = shouldOfferSaveAsTemplate
        DispatchQueue.main.async {
            if offerTemplate {
                saveAsTemplateNameDraft = displayWorkoutTitle
                showSaveAsTemplatePrompt = true
            } else {
                unregisterThisWorkoutSessionFromPresentation()
                dismiss()
            }
        }
    }

    private var shouldOfferSaveAsTemplate: Bool {
        guard session.completedAt != nil else { return false }
        guard session.startedFromPlanTemplate != true else { return false }
        return !orderedSessionExercises.isEmpty
    }

    private func saveFinishedWorkoutAsTemplate(named rawName: String) {
        let exercises = orderedSessionExercises
        guard !exercises.isEmpty else { return }

        let trimmedName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackName = displayWorkoutTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let templateName = !trimmedName.isEmpty
            ? trimmedName
            : (fallbackName.isEmpty ? "Workout" : fallbackName)
        let plan = WorkoutPlan(name: templateName)
        modelContext.insert(plan)

        for (index, sessionExercise) in exercises.enumerated() {
            let templateExercise = WorkoutPlanExercise(
                exerciseOrder: index + 1,
                exercise: sessionExercise.exercise,
                customExerciseName: sessionExercise.customExerciseName,
                sourceRawValue: sessionExercise.sourceRawValue,
                plan: plan
            )
            modelContext.insert(templateExercise)
            plan.exercises.append(templateExercise)
        }
        modelContext.processPendingChanges()
        try? modelContext.save()
    }

    private func liveActivitySetSummaryLine(set: WorkoutSet, exercise: Exercise?) -> String {
        let unit = unitsRawValue == "lb" ? "lb" : "kg"
        let formatted = WorkoutSetDisplay.formatLoggedSet(set: set, exercise: exercise, weightUnit: unit)
        guard formatted != WorkoutSetDisplay.emptyPlaceholder else {
            return "Set \(set.setOrder)"
        }
        return "Set \(set.setOrder) · \(formatted)"
    }

    private func buildLiveActivityPayload() -> RestTimerLiveActivityPayload? {
        guard workoutSessionPresentationState.activeRestSessionID == session.persistentModelID,
              let restStart = workoutSessionPresentationState.activeRestStartDate else { return nil }
        let sourceExerciseID = workoutSessionPresentationState.activeRestSourceSessionExerciseID
        let sourceSetOrder = workoutSessionPresentationState.activeRestSourceSetOrder
        let nextTitle: String
        let nextSubtitle: String
        if let sourceExerciseID {
            nextTitle = liveActivityNextActionTitle(
                sourceExerciseID: sourceExerciseID,
                sourceSetOrder: sourceSetOrder
            )
            nextSubtitle = liveActivityNextActionSubtitle(
                sourceExerciseID: sourceExerciseID,
                sourceSetOrder: sourceSetOrder
            )
        } else {
            nextTitle = workoutSessionPresentationState.liveActivityExerciseName
            nextSubtitle = ""
        }
        return RestTimerLiveActivityPayload(
            restStartDate: restStart,
            workoutSessionStartDate: session.sessionDate,
            exerciseName: nextTitle,
            setSummary: liveActivitySetSummaryLine(
                lastSetSummary: workoutSessionPresentationState.liveActivitySetSummary,
                nextSetHint: nextSubtitle
            )
        )
    }

    private func liveActivitySetSummaryLine(lastSetSummary: String, nextSetHint: String) -> String {
        let last = lastSetSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        let hint = nextSetHint.trimmingCharacters(in: .whitespacesAndNewlines)
        switch (last.isEmpty, hint.isEmpty) {
        case (false, false):
            return "\(last) · \(hint)"
        case (false, true):
            return last
        case (true, false):
            return hint
        case (true, true):
            return ""
        }
    }

    /// Same rules as `ContentView.miniBarExerciseNameDuringRest`: next set, next exercise, else just-finished.
    private func liveActivityNextActionTitle(
        sourceExerciseID: PersistentIdentifier,
        sourceSetOrder: Int?
    ) -> String {
        let orderedExercises = session.sessionExercises.sorted { $0.exerciseOrder < $1.exerciseOrder }
        guard let sourceExerciseIndex = orderedExercises.firstIndex(where: { $0.persistentModelID == sourceExerciseID }) else {
            return liveActivityFallbackExerciseTitle()
        }
        let sourceExercise = orderedExercises[sourceExerciseIndex]
        let exerciseName = sourceExercise.displayName.trimmingCharacters(in: .whitespacesAndNewlines)

        if let sourceSetOrder {
            let sortedSets = sourceExercise.sets.sorted { $0.setOrder < $1.setOrder }
            if let sourceSetIndex = sortedSets.firstIndex(where: { $0.setOrder == sourceSetOrder }),
               sourceSetIndex + 1 < sortedSets.count {
                let nextSetOrder = sortedSets[sourceSetIndex + 1].setOrder
                if !exerciseName.isEmpty {
                    return "\(exerciseName) · Set \(nextSetOrder)"
                }
            }
        }

        if sourceExerciseIndex + 1 < orderedExercises.count {
            let nextName = orderedExercises[sourceExerciseIndex + 1].displayName
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !nextName.isEmpty {
                return nextName
            }
        }

        if !exerciseName.isEmpty {
            return exerciseName
        }
        return liveActivityFallbackExerciseTitle()
    }

    private func liveActivityFallbackExerciseTitle() -> String {
        let ordered = session.sessionExercises.sorted { $0.exerciseOrder < $1.exerciseOrder }
        if let name = ordered.first?.displayName.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return name
        }
        let customName = session.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !customName.isEmpty {
            return customName
        }
        return workoutTitle
    }

    /// Previous-workout compact for the upcoming set in the same exercise, when applicable.
    private func liveActivityNextActionSubtitle(
        sourceExerciseID: PersistentIdentifier,
        sourceSetOrder: Int?
    ) -> String {
        guard let sourceSetOrder else { return "" }
        let orderedExercises = session.sessionExercises.sorted { $0.exerciseOrder < $1.exerciseOrder }
        guard let sourceExercise = orderedExercises.first(where: { $0.persistentModelID == sourceExerciseID }),
              let exercise = sourceExercise.exercise else { return "" }

        let sortedSets = sourceExercise.sets.sorted { $0.setOrder < $1.setOrder }
        guard let sourceSetIndex = sortedSets.firstIndex(where: { $0.setOrder == sourceSetOrder }),
              sourceSetIndex + 1 < sortedSets.count else { return "" }

        let nextSetOrder = sortedSets[sourceSetIndex + 1].setOrder
        guard let (_, previousSessionExercise) = PreviousWorkoutLookup.previousSessionWithSets(
            for: exercise,
            excluding: session,
            allSessions: allSessions
        ) else { return "" }

        guard let previousSet = previousSessionExercise.sets.first(where: { $0.setOrder == nextSetOrder }) else {
            return ""
        }

        let unit = unitsRawValue == "lb" ? "lb" : "kg"
        let compact = PreviousWorkoutLookup.formatPreviousCompact(
            weight: previousSet.weight,
            reps: previousSet.reps,
            unit: unit,
            loggingType: exercise.loggingType,
            durationSeconds: previousSet.durationSeconds,
            distanceMeters: previousSet.distanceMeters
        )
        guard compact != WorkoutSetDisplay.emptyPlaceholder else { return "" }
        return "Prev \(compact)"
    }

    private func publishLiveActivityIfResting() {
        guard let payload = buildLiveActivityPayload() else { return }
        restTimerLiveActivityManager.sync(payload: payload)
    }

    private func clearRestTimerAndLiveActivity() {
        workoutSessionPresentationState.clearRestTimer(for: session.persistentModelID)
        restTimerLiveActivityManager.sync(payload: nil)
    }

    private func triggerRestTimerAfterConfirming(set: WorkoutSet, sessionExercise: WorkoutSessionExercise) {
        guard isLiveWorkoutTimer else { return }
        workoutSessionPresentationState.startRestTimer(
            for: session.persistentModelID,
            sourceSessionExerciseID: sessionExercise.persistentModelID,
            sourceSetOrder: set.setOrder,
            exerciseName: sessionExercise.displayName,
            setSummary: liveActivitySetSummaryLine(set: set, exercise: sessionExercise.exercise)
        )
        publishLiveActivityIfResting()
    }

    private func discardWorkout() {
        clearRestTimerAndLiveActivity()
        unregisterThisWorkoutSessionFromPresentation()
        modelContext.delete(session)
        try? modelContext.save()
        dismiss()
    }

    private func deleteExercise(_ sessionExercise: WorkoutSessionExercise) {
        session.sessionExercises.removeAll { item in
            item.persistentModelID == sessionExercise.persistentModelID
        }
        modelContext.delete(sessionExercise)

        let reordered = session.sessionExercises.sorted { $0.exerciseOrder < $1.exerciseOrder }
        for (index, item) in reordered.enumerated() {
            item.exerciseOrder = index + 1
        }
        modelContext.processPendingChanges()
        try? modelContext.save()
    }

    private func deleteSet(_ set: WorkoutSet, from sessionExercise: WorkoutSessionExercise) {
        deleteSets([set], from: sessionExercise)
    }

    private func deleteSets(_ sets: [WorkoutSet], from sessionExercise: WorkoutSessionExercise) {
        guard !sets.isEmpty else { return }
        let ids = Set(sets.map(\.persistentModelID))
        sessionExercise.sets.removeAll { ids.contains($0.persistentModelID) }
        for set in sets {
            modelContext.delete(set)
        }

        let reordered = sessionExercise.sets.sorted { $0.setOrder < $1.setOrder }
        for (index, item) in reordered.enumerated() {
            item.setOrder = index + 1
        }
        modelContext.processPendingChanges()
        try? modelContext.save()
    }

    private func moveExercises(from source: IndexSet, to destination: Int) {
        var reordered = orderedSessionExercises
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, item) in reordered.enumerated() {
            item.exerciseOrder = index + 1
        }
        modelContext.processPendingChanges()
        try? modelContext.save()
        suppressExerciseReorderExitUntil = Date().addingTimeInterval(0.35)
    }

    private func enterSetDeleteMode(for sessionExercise: WorkoutSessionExercise) {
        setEntryKeypadSession.dismiss()
        setDeleteModeExerciseID = sessionExercise.persistentModelID
    }

    private func exitSetDeleteMode() {
        setDeleteModeExerciseID = nil
    }

    @ViewBuilder
    private func exerciseSectionView(_ sessionExercise: WorkoutSessionExercise) -> some View {
        ActiveExerciseLogSection(
            sessionExercise: sessionExercise,
            canEditStructure: canEditStructure,
            isSetDeleteMode: setDeleteModeExerciseID == sessionExercise.persistentModelID,
            currentSession: session,
            allSessions: allSessions,
            addSet: { addSet(to: sessionExercise) },
            deleteSet: { set in deleteSet(set, from: sessionExercise) },
            onSetConfirmed: { set in triggerRestTimerAfterConfirming(set: set, sessionExercise: sessionExercise) },
            onEnterSetDeleteMode: { enterSetDeleteMode(for: sessionExercise) },
            onExitSetDeleteMode: exitSetDeleteMode,
            onEnterExerciseReorderMode: enterExerciseReorderMode
        )
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if canEditStructure && !isExerciseReorderMode && setDeleteModeExerciseID == nil {
                Button(role: .destructive) {
                    deleteExercise(sessionExercise)
                } label: {
                    Text("Delete")
                }
            }
        }
    }

    private func repeatWorkout() {
        guard session.completedAt != nil else { return }

        if (try? ActiveWorkoutSession.canonicalUnfinishedSessionAfterCleanup(in: modelContext)) != nil {
            workoutSessionPresentationState.showActiveWorkoutBlockingAlert = true
            return
        }

        guard let repeated = WorkoutSession.newRepeating(from: session, in: modelContext) else { return }
        repeatTargetSession = repeated
        repeatTargetTitle = titleForSession(repeated, fallback: displayWorkoutTitle)
        workoutSessionPresentationState.registerWorkoutSessionView(for: repeated.persistentModelID)
        showRepeatTarget = true
    }

    private func titleForSession(_ target: WorkoutSession, fallback: String) -> String {
        let custom = target.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !custom.isEmpty {
            return custom
        }
        let ordered = target.sessionExercises.sorted { $0.exerciseOrder < $1.exerciseOrder }
        guard let firstName = ordered.first?.displayName, !firstName.isEmpty else {
            return fallback
        }
        if ordered.count == 1 {
            return firstName
        }
        return "\(firstName) +\(ordered.count - 1)"
    }

    private func workoutBottomAccessoryTimerArea<Value: View>(
        label: String,
        contentAlignment: HorizontalAlignment,
        @ViewBuilder value: () -> Value
    ) -> some View {
        let vStackAlignment = contentAlignment
        let frameAlignment: Alignment =
            contentAlignment == .leading ? .leading : .trailing
        return VStack(alignment: vStackAlignment, spacing: 3) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(WorkoutLogTheme.textSecondary)
                .textCase(.uppercase)
                .tracking(0.28)
                .lineLimit(1)
            value()
                .font(.subheadline.weight(.medium).monospacedDigit())
                .foregroundStyle(Color(uiColor: .label))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, minHeight: UITheme.mainBottomBarChromeMinHeight, alignment: frameAlignment)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Isolated workout elapsed timer

private struct WorkoutElapsedTimerText: View {
    let sessionDate: Date
    let fixedCompletedDurationSeconds: TimeInterval?
    let isLive: Bool
    var font: Font = .subheadline.weight(.medium)

    @State private var elapsedSeconds: TimeInterval = 0
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var displayText: String {
        let totalSeconds = Int(elapsedSeconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var body: some View {
        Text(displayText)
            .font(font)
            .monospacedDigit()
            .onAppear {
                syncElapsedSeconds()
            }
            .onChange(of: isLive) { _, _ in
                syncElapsedSeconds()
            }
            .onChange(of: fixedCompletedDurationSeconds) { _, _ in
                syncElapsedSeconds()
            }
            .onReceive(timer) { _ in
                guard isLive else { return }
                elapsedSeconds = max(0, Date().timeIntervalSince(sessionDate))
            }
    }

    private func syncElapsedSeconds() {
        elapsedSeconds = fixedCompletedDurationSeconds ?? max(0, Date().timeIntervalSince(sessionDate))
    }
}

// MARK: - Add exercise picker

/// Logging choices shown when creating a user-saved custom exercise.
private enum CustomExerciseLoggingPickerOption: String, CaseIterable, Identifiable {
    case strength
    case bodyweight
    case duration
    case cardio
    case mobility

    var id: String { rawValue }

    var label: String {
        switch self {
        case .strength: return "Weight × Reps"
        case .bodyweight: return "Reps only"
        case .duration: return "Time"
        case .cardio: return "Time + Distance"
        case .mobility: return "Mobility / Time"
        }
    }

    var exerciseLoggingType: ExerciseLoggingType {
        ExerciseLoggingType(rawValue: rawValue) ?? .strength
    }
}

private struct SessionAddExercisePickerView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Exercise.name) private var allExercises: [Exercise]
    @Query(sort: \WorkoutSession.sessionDate, order: .reverse) private var allSessions: [WorkoutSession]
    @Query(sort: \WorkoutPlan.createdAt, order: .reverse) private var allPlans: [WorkoutPlan]

    let session: WorkoutSession
    @Binding var isPresented: Bool

    @State private var exerciseName = ""
    @State private var selectedCategory: String?
    @State private var showCustomExerciseSheet = false
    @State private var customFormName = ""
    @State private var customFormCategory = "Full Body"
    @State private var customFormLoggingOption: CustomExerciseLoggingPickerOption = .strength
    @State private var customFormLoggingTypeManuallySet = false
    @State private var isMyExercisesExpanded = false
    @State private var isSearchVisible = false
    @FocusState private var isNameFieldFocused: Bool
    @State private var isMyExercisesSelectionMode = false
    @State private var selectedMyExerciseIDs: Set<PersistentIdentifier> = []
    @State private var showBatchDeleteConfirmation = false

    private static let exercisePickerRowMinHeight: CGFloat = 50
    private static let exercisePickerPlusButtonSide: CGFloat = 44

    private var trimmedExerciseName: String {
        ExerciseSearchMatching.trimmedQuery(exerciseName)
    }

    /// Selectable library exercises (built-in + user-saved). Session-only entries are excluded.
    private var libraryExercises: [Exercise] {
        allExercises.filter { exercise in
            guard exercise.source != .sessionOnly else { return false }
            if exercise.source == .builtIn { return true }
            return exercise.isHiddenFromLibrary != true
        }
    }

    private var userSavedExercises: [Exercise] {
        libraryExercises
            .filter { $0.source == .userSaved }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var builtInExercises: [Exercise] {
        libraryExercises
            .filter { $0.source == .builtIn }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private let topCategories: [String] = [
        "All",
        "Chest",
        "Back",
        "Shoulders",
        "Biceps",
        "Triceps",
        "Legs",
        "Glutes",
        "Core",
        "Cardio",
        "Full Body",
        "Olympic / Power",
        "Mobility"
    ]

    private static let libraryCategories: [String] = [
        "Chest",
        "Back",
        "Shoulders",
        "Biceps",
        "Triceps",
        "Legs",
        "Glutes",
        "Core",
        "Cardio",
        "Full Body",
        "Olympic / Power",
        "Mobility"
    ]

    /// Heavy: re-ranks the entire catalog. Call once per render and cache the result —
    /// the prior computed-property form was hit ~3 × catalog-size times per body.
    private func computeSearchRankByID() -> [PersistentIdentifier: Int]? {
        guard !trimmedExerciseName.isEmpty else { return nil }
        let allMatches = ExerciseSearchMatching.rankedSuggestions(
            in: libraryExercises,
            query: exerciseName,
            limit: libraryExercises.count
        )
        return Dictionary(uniqueKeysWithValues: allMatches.enumerated().map { ($1.persistentModelID, $0) })
    }

    private func sortExercisesBySearchRank(
        _ exercises: [Exercise],
        rankByID: [PersistentIdentifier: Int]?
    ) -> [Exercise] {
        guard let rankByID else { return exercises }
        return exercises.sorted {
            let leftRank = rankByID[$0.persistentModelID] ?? Int.max
            let rightRank = rankByID[$1.persistentModelID] ?? Int.max
            if leftRank != rightRank { return leftRank < rightRank }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private var hasExactMatch: Bool {
        ExerciseSearchMatching.hasExactMatch(in: libraryExercises, query: exerciseName)
    }

    private var recentExercises: [Exercise] {
        var seen = Set<PersistentIdentifier>()
        var ordered: [Exercise] = []
        for priorSession in allSessions {
            for sessionExercise in priorSession.sessionExercises.sorted(by: { $0.exerciseOrder < $1.exerciseOrder }) {
                guard let exercise = sessionExercise.exercise else { continue }
                if exercise.isHiddenFromLibrary == true { continue }
                let id = exercise.persistentModelID
                guard !seen.contains(id) else { continue }
                seen.insert(id)
                ordered.append(exercise)
                if ordered.count >= 10 {
                    return ordered
                }
            }
        }
        return ordered
    }

    private var allExercisesAlphabetical: [Exercise] {
        builtInExercises
    }

    private var myExercisesPreviewLimit: Int { 3 }

    var body: some View {
        // Compute the ranked-search result once per render and pass it explicitly into the
        // per-element matcher. The old form re-ran the ranked search for every exercise in
        // every filter pass (`matchesCurrentFilters` re-read the computed `matchingIDs`).
        let cachedSearchRankByID = computeSearchRankByID()
        let cachedMatchingIDs = cachedSearchRankByID.map { Set($0.keys) }
        let filteredUserSavedExercises = sortExercisesBySearchRank(
            userSavedExercises.filter { matchesCurrentFilters($0, matchingIDs: cachedMatchingIDs) },
            rankByID: cachedSearchRankByID
        )
        let filteredRecentExercises = sortExercisesBySearchRank(
            recentExercises.filter { matchesCurrentFilters($0, matchingIDs: cachedMatchingIDs) },
            rankByID: cachedSearchRankByID
        )
        let filteredAllExercises = sortExercisesBySearchRank(
            allExercisesAlphabetical.filter { matchesCurrentFilters($0, matchingIDs: cachedMatchingIDs) },
            rankByID: cachedSearchRankByID
        )
        let visibleUserSavedExercises: [Exercise] = isMyExercisesExpanded
            ? filteredUserSavedExercises
            : Array(filteredUserSavedExercises.prefix(myExercisesPreviewLimit))
        let canExpandMyExercises = filteredUserSavedExercises.count > myExercisesPreviewLimit

        return VStack(alignment: .leading, spacing: 12) {
            header

            if isSearchVisible {
                TextField("Exercise name", text: $exerciseName)
                    .focused($isNameFieldFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(12)
                    .background(UITheme.controlFill)
                    .clipShape(RoundedRectangle(cornerRadius: UITheme.cornerRadiusSmall, style: .continuous))
                    .foregroundStyle(WorkoutLogTheme.textPrimary)
                    .tint(WorkoutLogTheme.accent)
                    .padding(.horizontal, 16)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(topCategories, id: \.self) { category in
                        let isSelected =
                            (category == "All" && selectedCategory == nil) ||
                            selectedCategory == category
                        Button {
                            if category == "All" {
                                selectedCategory = nil
                            } else {
                                selectedCategory = isSelected ? nil : category
                            }
                        } label: {
                            Text(category)
                        }
                        .buttonStyle(ChipStyle(isSelected: isSelected))
                    }
                }
                .padding(.horizontal, 16)
            }

            if !trimmedExerciseName.isEmpty && !hasExactMatch {
                Button {
                    presentCustomExerciseSheet()
                } label: {
                    Text("Create \"\(trimmedExerciseName)\"")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(PrimaryBottomButtonStyle())
                .padding(.horizontal, 16)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !filteredUserSavedExercises.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("My Exercises")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(WorkoutLogTheme.textSecondary)
                                    .textCase(.uppercase)
                                    .tracking(0.45)
                                Spacer(minLength: 0)
                                if !isMyExercisesSelectionMode {
                                    Menu {
                                        Button("Delete Exercises") {
                                            enterMyExercisesSelectionMode()
                                        }
                                    } label: {
                                        Image(systemName: "ellipsis.circle")
                                            .font(.system(size: UITheme.iconSizeM, weight: .semibold))
                                            .foregroundStyle(WorkoutLogTheme.textSecondary)
                                            .frame(width: Self.exercisePickerPlusButtonSide, height: Self.exercisePickerPlusButtonSide)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("My Exercises options")
                                }
                            }

                            exerciseList(
                                exercises: visibleUserSavedExercises,
                                isMyExercisesSection: true
                            )

                            if canExpandMyExercises {
                                Button(isMyExercisesExpanded ? "See Less" : "See More") {
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        isMyExercisesExpanded.toggle()
                                    }
                                }
                                .font(.subheadline.weight(.semibold))
                                .buttonStyle(.plain)
                                .foregroundStyle(WorkoutLogTheme.accent)
                            }
                        }
                    }

                    if !filteredRecentExercises.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Recent")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(WorkoutLogTheme.textSecondary)
                                .textCase(.uppercase)
                                .tracking(0.45)
                            exerciseList(exercises: filteredRecentExercises)
                        }
                    }

                    if !filteredAllExercises.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("All Exercises")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(WorkoutLogTheme.textSecondary)
                                .textCase(.uppercase)
                                .tracking(0.45)
                            exerciseList(exercises: filteredAllExercises)
                        }
                    }

                    if filteredRecentExercises.isEmpty && filteredAllExercises.isEmpty {
                        Text("No matching exercises.")
                            .font(.subheadline)
                            .foregroundStyle(WorkoutLogTheme.textSecondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                isNameFieldFocused = false
                dismissKeyboard()
            }
        }
        .padding(.top, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(WorkoutLogTheme.background.ignoresSafeArea())
        .simultaneousGesture(
            TapGesture().onEnded {
                guard isSearchVisible else { return }
                isNameFieldFocused = false
                dismissKeyboard()
            }
        )
        .onChange(of: isPresented) { _, open in
            if !open { resetSearchState() }
        }
        .onDisappear {
            resetSearchState()
        }
        .sheet(isPresented: $showCustomExerciseSheet) {
            customExerciseCreationSheet
        }
        .alert(
            "Delete selected exercises?",
            isPresented: $showBatchDeleteConfirmation
        ) {
            Button("Delete", role: .destructive) {
                deleteSelectedMyExercisesAfterConfirmation()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They will be removed from My Exercises. Existing workouts and plans will keep them.")
        }
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    private var header: some View {
        ZStack {
            Text(isMyExercisesSelectionMode ? "Delete Exercises" : "Add an Exercise")
                .font(.headline.weight(.semibold))
                .foregroundStyle(WorkoutLogTheme.textPrimary)
                .lineLimit(1)

            HStack {
                Button("Cancel") {
                    if isMyExercisesSelectionMode {
                        exitMyExercisesSelectionMode()
                    } else {
                        closePicker()
                    }
                }
                .font(.body)
                .foregroundStyle(WorkoutLogTheme.accent)

                Spacer()

                if isMyExercisesSelectionMode {
                    Button("Delete", role: .destructive) {
                        requestDeleteSelectedMyExercises()
                    }
                    .font(.body.weight(.semibold))
                    .disabled(selectedMyExerciseIDs.isEmpty)
                } else {
                    Button {
                        toggleSearch()
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: UITheme.iconSizeM, weight: .semibold))
                            .foregroundStyle(WorkoutLogTheme.accent)
                            .frame(width: UITheme.tapTargetMinHeight, height: UITheme.tapTargetMinHeight)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func closePicker() {
        dismissKeyboard()
        isPresented = false
    }

    private func toggleSearch() {
        isSearchVisible.toggle()
        if isSearchVisible {
            DispatchQueue.main.async {
                isNameFieldFocused = true
            }
        } else {
            isNameFieldFocused = false
            dismissKeyboard()
            exerciseName = ""
        }
    }

    private func resetSearchState() {
        isNameFieldFocused = false
        dismissKeyboard()
        exerciseName = ""
        isSearchVisible = false
        exitMyExercisesSelectionMode()
    }

    private func enterMyExercisesSelectionMode() {
        dismissKeyboard()
        isNameFieldFocused = false
        isSearchVisible = false
        selectedMyExerciseIDs = []
        isMyExercisesSelectionMode = true
    }

    private func exitMyExercisesSelectionMode() {
        isMyExercisesSelectionMode = false
        selectedMyExerciseIDs = []
    }

    private func addExerciseToSession(_ exercise: Exercise) {
        let nextOrder = (session.sessionExercises.map(\.exerciseOrder).max() ?? 0) + 1
        let sessionExercise = WorkoutSessionExercise(
            exerciseOrder: nextOrder,
            session: session,
            exercise: exercise,
            sourceRawValue: exercise.source.rawValue
        )
        modelContext.insert(sessionExercise)
        session.sessionExercises.append(sessionExercise)

        let previousSets = latestCompletedSets(for: exercise)
        if !previousSets.isEmpty {
            for (index, previousSet) in previousSets.enumerated() {
                let fields = pendingSetFields(
                    for: exercise.loggingType,
                    seeded: (
                        previousSet.weight,
                        previousSet.reps,
                        previousSet.durationSeconds,
                        previousSet.distanceMeters
                    )
                )
                let pendingSet = WorkoutSet(
                    setOrder: index + 1,
                    weight: fields.weight,
                    reps: fields.reps,
                    isPendingSuggestion: true,
                    durationSeconds: fields.durationSeconds,
                    distanceMeters: fields.distanceMeters,
                    sessionExercise: sessionExercise
                )
                modelContext.insert(pendingSet)
                sessionExercise.sets.append(pendingSet)
            }
        } else {
            let fields = pendingSetFields(for: exercise.loggingType, seeded: (0, 0, nil, nil))
            let pendingSet = WorkoutSet(
                setOrder: 1,
                weight: fields.weight,
                reps: fields.reps,
                isPendingSuggestion: true,
                durationSeconds: fields.durationSeconds,
                distanceMeters: fields.distanceMeters,
                sessionExercise: sessionExercise
            )
            modelContext.insert(pendingSet)
            sessionExercise.sets.append(pendingSet)
        }

        // Persist seeded pending rows immediately so visual pending state survives lifecycle changes.
        modelContext.processPendingChanges()
        try? modelContext.save()

        exerciseName = ""
        isPresented = false
    }

    private func saveCustomExerciseAndAdd() {
        let name = customFormName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let exercise = Exercise(
            name: name,
            category: customFormCategory,
            source: .userSaved,
            loggingType: customFormLoggingOption.exerciseLoggingType
        )
        modelContext.insert(exercise)
        addExerciseToSession(exercise)
        dismissCustomExerciseSheet()
    }

    private func addSessionOnlyExercise(named rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        let nextOrder = (session.sessionExercises.map(\.exerciseOrder).max() ?? 0) + 1
        let sessionExercise = WorkoutSessionExercise(
            exerciseOrder: nextOrder,
            session: session,
            exercise: nil,
            sourceRawValue: ExerciseSource.sessionOnly.rawValue,
            customExerciseName: name
        )
        modelContext.insert(sessionExercise)
        session.sessionExercises.append(sessionExercise)

        // Session-only exercises have no library history; seed one pending 0 × 0 row.
        let pendingSet = WorkoutSet(
            setOrder: 1,
            weight: 0,
            reps: 0,
            isPendingSuggestion: true,
            sessionExercise: sessionExercise
        )
        modelContext.insert(pendingSet)
        sessionExercise.sets.append(pendingSet)

        modelContext.processPendingChanges()
        try? modelContext.save()
        exerciseName = ""
        dismissCustomExerciseSheet()
        isPresented = false
    }

    private var customExerciseCreationSheet: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Exercise name", text: $customFormName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .foregroundStyle(WorkoutLogTheme.textPrimary)

                    Picker("Category", selection: $customFormCategory) {
                        ForEach(Self.libraryCategories, id: \.self) { category in
                            Text(category).tag(category)
                        }
                    }
                    .foregroundStyle(WorkoutLogTheme.textPrimary)
                    .onChange(of: customFormCategory) { _, newCategory in
                        applyCategoryDefaultLoggingType(for: newCategory)
                    }

                    Picker("Logging", selection: $customFormLoggingOption) {
                        ForEach(CustomExerciseLoggingPickerOption.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .foregroundStyle(WorkoutLogTheme.textPrimary)
                    .onChange(of: customFormLoggingOption) { _, _ in
                        customFormLoggingTypeManuallySet = true
                    }
                }

                Section {
                    Text("Choose whether this custom exercise is session-only or saved to your library.")
                        .font(.subheadline)
                        .foregroundStyle(WorkoutLogTheme.textSecondary)
                }

                Section {
                    Button("Use Only This Workout") {
                        addSessionOnlyExercise(named: customFormName)
                    }
                    .foregroundStyle(WorkoutLogTheme.textPrimary)

                    Button("Save to My Exercises") {
                        saveCustomExerciseAndAdd()
                    }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(WorkoutLogTheme.accent)
                    .disabled(customFormName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(WorkoutLogTheme.background.ignoresSafeArea())
            .navigationTitle("Add custom exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismissCustomExerciseSheet()
                    }
                    .foregroundStyle(WorkoutLogTheme.accent)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func presentCustomExerciseSheet() {
        customFormName = trimmedExerciseName
        customFormCategory = defaultCustomExerciseCategory()
        customFormLoggingOption = Self.defaultLoggingOption(for: customFormCategory)
        customFormLoggingTypeManuallySet = false
        showCustomExerciseSheet = true
    }

    private func dismissCustomExerciseSheet() {
        showCustomExerciseSheet = false
        customFormName = ""
        customFormLoggingTypeManuallySet = false
    }

    private func defaultCustomExerciseCategory() -> String {
        if let selectedCategory, selectedCategory != "All" {
            return selectedCategory
        }
        return "Full Body"
    }

    private static func defaultLoggingOption(for category: String) -> CustomExerciseLoggingPickerOption {
        switch category {
        case "Cardio": return .cardio
        case "Mobility": return .mobility
        default: return .strength
        }
    }

    private func applyCategoryDefaultLoggingType(for category: String) {
        guard !customFormLoggingTypeManuallySet else { return }
        customFormLoggingOption = Self.defaultLoggingOption(for: category)
    }

    private func latestCompletedSets(for exercise: Exercise) -> [WorkoutSet] {
        let exerciseID = exercise.persistentModelID
        let currentSessionID = session.persistentModelID
        let previousSessions = allSessions
            .filter { $0.completedAt != nil && $0.persistentModelID != currentSessionID }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }

        for previousSession in previousSessions {
            let matchingExercise = previousSession.sessionExercises
                .filter { $0.exercise?.persistentModelID == exerciseID }
                .sorted { $0.exerciseOrder < $1.exerciseOrder }
                .first
            guard let matchingExercise else { continue }
            let sets = matchingExercise.sets.sorted { $0.setOrder < $1.setOrder }
            if !sets.isEmpty {
                return sets
            }
        }
        return []
    }

    private func matchesCurrentFilters(
        _ exercise: Exercise,
        matchingIDs: Set<PersistentIdentifier>?
    ) -> Bool {
        if let selectedCategory, selectedCategory != "All",
           exercise.category.caseInsensitiveCompare(selectedCategory) != .orderedSame {
            return false
        }
        if let matchingIDs {
            return matchingIDs.contains(exercise.persistentModelID)
        }
        return true
    }

    /// My Exercises uses section-level delete mode: unused exercises are deleted; used ones are hidden from library lists only.
    @ViewBuilder
    private func exerciseList(
        exercises: [Exercise],
        isMyExercisesSection: Bool = false
    ) -> some View {
        let selectionActive = isMyExercisesSection && isMyExercisesSelectionMode
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(exercises.enumerated()), id: \.element.persistentModelID) { index, exercise in
                let isUserSaved = exercise.source == .userSaved
                let isSelected = selectedMyExerciseIDs.contains(exercise.persistentModelID)

                HStack(spacing: 0) {
                    if selectionActive, isUserSaved {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 22, weight: .regular))
                            .foregroundStyle(isSelected ? WorkoutLogTheme.accent : WorkoutLogTheme.textMuted)
                            .frame(width: 36, alignment: .leading)
                            .accessibilityLabel(isSelected ? "Selected" : "Not selected")
                    }

                    HStack(spacing: 10) {
                        Text(exercise.name)
                            .font(.body)
                            .foregroundStyle(WorkoutLogTheme.textPrimary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                        Spacer(minLength: 8)
                        if !selectionActive || !isMyExercisesSection {
                            Button {
                                addExerciseToSession(exercise)
                            } label: {
                                Image(systemName: "plus.circle")
                                    .font(.system(size: UITheme.iconSizeM, weight: .semibold))
                                    .foregroundStyle(WorkoutLogTheme.textSecondary)
                                    .frame(
                                        width: Self.exercisePickerPlusButtonSide,
                                        height: Self.exercisePickerPlusButtonSide
                                    )
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Add \(exercise.name)")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: Self.exercisePickerRowMinHeight, alignment: .center)
                .padding(.vertical, 6)
                .padding(.leading, selectionActive && isUserSaved ? 10 : 12)
                .padding(.trailing, 10)
                .background {
                    if selectionActive, isUserSaved, isSelected {
                        WorkoutLogTheme.accent.opacity(0.08)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if selectionActive, isUserSaved {
                        toggleMyExerciseSelection(exercise)
                    } else if !selectionActive {
                        addExerciseToSession(exercise)
                    }
                }

                if index < exercises.count - 1 {
                    Divider()
                        .background(WorkoutLogTheme.surfaceStroke.opacity(0.8))
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: UITheme.cornerRadiusSmall, style: .continuous)
                .fill(UITheme.cardBackgroundElevated)
        )
        .clipShape(RoundedRectangle(cornerRadius: UITheme.cornerRadiusSmall, style: .continuous))
    }

    /// True if this exercise is referenced by any workout session or saved plan (prevents orphaning history/plans).
    private func isExerciseUsedInWorkoutsOrPlans(_ exercise: Exercise) -> Bool {
        let id = exercise.persistentModelID
        for workoutSession in allSessions {
            if workoutSession.sessionExercises.contains(where: { $0.exercise?.persistentModelID == id }) {
                return true
            }
        }
        for plan in allPlans {
            if plan.exercises.contains(where: { $0.exercise?.persistentModelID == id }) {
                return true
            }
        }
        return false
    }

    private func toggleMyExerciseSelection(_ exercise: Exercise) {
        guard exercise.source == .userSaved else { return }
        let id = exercise.persistentModelID
        if selectedMyExerciseIDs.contains(id) {
            selectedMyExerciseIDs.remove(id)
        } else {
            selectedMyExerciseIDs.insert(id)
        }
    }

    private func requestDeleteSelectedMyExercises() {
        guard !selectedMyExerciseIDs.isEmpty else { return }
        let selected = allExercises.filter {
            selectedMyExerciseIDs.contains($0.persistentModelID) && $0.source == .userSaved
        }
        guard !selected.isEmpty else { return }
        showBatchDeleteConfirmation = true
    }

    private func deleteSelectedMyExercisesAfterConfirmation() {
        let selected = allExercises.filter {
            selectedMyExerciseIDs.contains($0.persistentModelID) && $0.source == .userSaved
        }
        guard !selected.isEmpty else { return }
        for exercise in selected {
            if isExerciseUsedInWorkoutsOrPlans(exercise) {
                exercise.isHiddenFromLibrary = true
            } else {
                modelContext.delete(exercise)
            }
        }
        modelContext.processPendingChanges()
        try? modelContext.save()
        exitMyExercisesSelectionMode()
    }
}

// MARK: - Exercise section

private struct ActiveExerciseLogSection: View {
    @Environment(SetEntryKeypadSession.self) private var keypadSession
    @AppStorage("settings.units") private var unitsRawValue: String = "kg"
    let sessionExercise: WorkoutSessionExercise
    let canEditStructure: Bool
    let isSetDeleteMode: Bool
    let currentSession: WorkoutSession
    let allSessions: [WorkoutSession]
    let addSet: () -> Void
    let deleteSet: (WorkoutSet) -> Void
    let onSetConfirmed: (WorkoutSet) -> Void
    let onEnterSetDeleteMode: () -> Void
    let onExitSetDeleteMode: () -> Void
    let onEnterExerciseReorderMode: () -> Void
    @State private var pendingDeleteSetID: PersistentIdentifier?
    @State private var pendingDeleteSetOrder: Int?
    @State private var pendingDeleteSessionExerciseID: PersistentIdentifier?
    /// At most one PR marker per exercise — always the best qualifying confirmed set in this workout.
    @State private var personalRecordSetID: PersistentIdentifier?

    private var exerciseName: String {
        sessionExercise.displayName
    }

    private var sortedSets: [WorkoutSet] {
        sessionExercise.sets.sorted { $0.setOrder < $1.setOrder }
    }

    private var loggingMode: SetRowLoggingMode {
        SetRowLoggingMode.from(exercise: sessionExercise.exercise)
    }

    private var previousContext: (session: WorkoutSession, sessionExercise: WorkoutSessionExercise)? {
        guard let exercise = sessionExercise.exercise else { return nil }
        return PreviousWorkoutLookup.previousSessionWithSets(
            for: exercise,
            excluding: currentSession,
            allSessions: allSessions
        )
    }

    private var weightUnitLabel: String {
        unitsRawValue == "lb" ? "lb" : "kg"
    }

    var body: some View {
        // Cache the previous-session lookup once per render. Previously this was recomputed
        // for the date label *and* once per set row, each time also re-sorting the previous
        // session's sets — O(sets × sessions) per body. Caching once + indexing by setOrder
        // makes per-row previous lookups O(1).
        let cachedPreviousContext = previousContext
        let previousSetsByOrder: [Int: WorkoutSet] = {
            guard let context = cachedPreviousContext else { return [:] }
            var map: [Int: WorkoutSet] = [:]
            for set in context.sessionExercise.sets {
                map[set.setOrder] = set
            }
            return map
        }()
        // `sortedSets` was being re-sorted for every row's separator check; cache the result.
        let sortedSets = self.sortedSets
        let lastSetID = sortedSets.last?.persistentModelID

        return VStack(alignment: .leading, spacing: 0) {
            exerciseHeaderRow

            VStack(alignment: .leading, spacing: 0) {
                tableHeaderRow

                Rectangle()
                    .fill(WorkoutLogTheme.surfaceStroke)
                    .frame(height: 1)
                    .padding(.top, 8)
                    .padding(.bottom, 6)

                if let completedAt = cachedPreviousContext?.session.completedAt {
                    Text(PreviousWorkoutLookup.compactLastSessionDateLabel(completedAt: completedAt))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(WorkoutLogTheme.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 2)
                        .padding(.bottom, 10)
                }

                if sortedSets.isEmpty {
                    Text("No sets yet.")
                        .font(.caption)
                        .foregroundStyle(WorkoutLogTheme.textMuted)
                        .padding(.vertical, 6)
                } else {
                    VStack(spacing: 0) {
                        ForEach(sortedSets) { set in
                            Group {
                                setRowContent(
                                    set: set,
                                    previousSetsByOrder: previousSetsByOrder
                                )
                            }

                            if set.persistentModelID != lastSetID {
                                Rectangle()
                                    .fill(WorkoutLogTheme.surfaceStroke.opacity(0.55))
                                    .frame(height: 1)
                                    .padding(.vertical, 8)
                            }
                        }
                    }
                }

                if canEditStructure, !isSetDeleteMode {
                    Button(action: addSet) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.caption.weight(.semibold))
                            Text("Add set")
                                .font(.caption)
                        }
                        .foregroundStyle(WorkoutLogTheme.accent.opacity(0.95))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 10)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: UITheme.cornerRadius, style: .continuous)
                    .fill(WorkoutLogTheme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: UITheme.cornerRadius, style: .continuous)
                            .stroke(WorkoutLogTheme.surfaceStroke, lineWidth: 1)
                    )
            )
            .onChange(of: isSetDeleteMode) { _, isActive in
                if !isActive {
                    clearPendingDeleteState()
                }
            }
            .alert(
                pendingDeleteAlertTitle,
                isPresented: Binding(
                    get: { pendingDeleteSetID != nil },
                    set: { shouldShow in
                        if !shouldShow { clearPendingDeleteState() }
                    }
                )
            ) {
                Button("Delete", role: .destructive) {
                    confirmPendingDelete()
                }
                Button("Cancel", role: .cancel) {
                    clearPendingDeleteState()
                }
            } message: {
                Text("This cannot be undone.")
            }
        }
    }

    private var exerciseHeaderRow: some View {
        HStack(alignment: .center, spacing: 6) {
            Text(exerciseName)
                .font(.body.weight(.semibold))
                .foregroundStyle(WorkoutLogTheme.textPrimary)
                .lineLimit(2)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(WorkoutLogTheme.textMuted)

            Spacer(minLength: 8)

            if canEditStructure {
                if isSetDeleteMode {
                    Button {
                        exitSetDeleteMode()
                    } label: {
                        Text("Done")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(WorkoutLogTheme.accent)
                    }
                    .buttonStyle(.plain)
                } else {
                    Menu {
                        Button("Reorder Exercises") {
                            onEnterExerciseReorderMode()
                        }

                        Button("Delete Set", role: .destructive) {
                            enterSetDeleteMode()
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.body)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(WorkoutLogTheme.textMuted)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Exercise options")
                }
            }
        }
        .padding(.bottom, 10)
    }

    private var pendingDeleteAlertTitle: String {
        guard let pendingDeleteSetOrder else { return "" }
        return "Delete Set \(pendingDeleteSetOrder)?"
    }

    @ViewBuilder
    private func setRowContent(
        set: WorkoutSet,
        previousSetsByOrder: [Int: WorkoutSet]
    ) -> some View {
        let row = setLogRow(
            set: set,
            previousSetsByOrder: previousSetsByOrder
        )

        if isSetDeleteMode {
            HStack(alignment: .center, spacing: WorkoutLogTheme.colTableSpacing) {
                row
                setDeleteControl(for: set)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            row
        }
    }

    private func setDeleteControl(for set: WorkoutSet) -> some View {
        Button {
            requestDeleteSet(set)
        } label: {
            Image(systemName: "minus.circle.fill")
                .font(.title3)
                .frame(minWidth: WorkoutLogTheme.colDelete, minHeight: WorkoutLogTheme.colDelete)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(WorkoutLogTheme.accent)
        .accessibilityLabel("Delete set \(set.setOrder)")
    }

    private func setLogRow(
        set: WorkoutSet,
        previousSetsByOrder: [Int: WorkoutSet]
    ) -> some View {
        let previousSet = previousSetsByOrder[set.setOrder]
        let previousCompactDisplay = previousCompactCell(prevSet: previousSet)
        return SetLogRowView(
            set: set,
            exercise: sessionExercise.exercise,
            sessionExerciseID: sessionExercise.persistentModelID,
            loggingMode: loggingMode,
            previousCompactDisplay: previousCompactDisplay,
            previousEntryValue: previousEntryValue(
                for: set,
                sortedSets: sortedSets,
                historicalPreviousSet: previousSet,
                historicalCompactDisplay: previousCompactDisplay
            ),
            isEditable: canEditStructure,
            allowsInteraction: canEditStructure && !isSetDeleteMode,
            showsInputAppearance: canEditStructure,
            showPersonalRecordIndicator: personalRecordSetID == set.persistentModelID,
            onSetConfirmed: { handleSetConfirmed(set) }
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func previousEntryValue(
        for set: WorkoutSet,
        sortedSets: [WorkoutSet],
        historicalPreviousSet: WorkoutSet?,
        historicalCompactDisplay: String
    ) -> SetEntryPreviousValue? {
        if let currentWorkoutValue = previousCompletedSetValue(before: set, in: sortedSets) {
            return currentWorkoutValue
        }
        return historicalPreviousEntryValue(
            prevSet: historicalPreviousSet,
            compactDisplay: historicalCompactDisplay
        )
    }

    private func previousCompletedSetValue(before set: WorkoutSet, in sortedSets: [WorkoutSet]) -> SetEntryPreviousValue? {
        let loggingType = loggingMode.exerciseLoggingType
        guard let previousSet = sortedSets
            .filter({ $0.setOrder < set.setOrder })
            .sorted(by: { $0.setOrder > $1.setOrder })
            .first(where: {
                !$0.isPendingSuggestion
                    && WorkoutSetLoggingRules.isComplete(set: $0, loggingType: loggingType)
            })
        else { return nil }

        return setEntryPreviousValue(from: previousSet)
    }

    private func enterSetDeleteMode() {
        keypadSession.dismiss()
        clearPendingDeleteState()
        onEnterSetDeleteMode()
    }

    private func exitSetDeleteMode() {
        clearPendingDeleteState()
        onExitSetDeleteMode()
    }

    private func clearPendingDeleteState() {
        pendingDeleteSetID = nil
        pendingDeleteSetOrder = nil
        pendingDeleteSessionExerciseID = nil
    }

    private func requestDeleteSet(_ set: WorkoutSet) {
        pendingDeleteSetID = set.persistentModelID
        pendingDeleteSetOrder = set.setOrder
        pendingDeleteSessionExerciseID = sessionExercise.persistentModelID
    }

    private func confirmPendingDelete() {
        guard
            let setID = pendingDeleteSetID,
            pendingDeleteSessionExerciseID == sessionExercise.persistentModelID,
            let set = sessionExercise.sets.first(where: { $0.persistentModelID == setID })
        else {
            clearPendingDeleteState()
            return
        }

        if keypadSession.activeSetID == setID {
            keypadSession.dismiss()
        }

        deleteSet(set)
        refreshPersonalRecordMarker()
        clearPendingDeleteState()

        if sessionExercise.sets.isEmpty {
            exitSetDeleteMode()
        }
    }

    private var tableHeaderRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: WorkoutLogTheme.colTableSpacing) {
            Text("Set")
                .frame(width: WorkoutLogTheme.colSet, alignment: .leading)
            Text("Previous")
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .frame(width: WorkoutLogTheme.colPrevious, alignment: .center)
            Spacer(minLength: 0)
            if canEditStructure {
                tableTrailingHeader
            } else {
                readOnlyTableTrailingHeader
            }
            if isSetDeleteMode {
                Color.clear
                    .frame(width: WorkoutLogTheme.colDelete)
            }
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(WorkoutLogTheme.textSecondary)
        .textCase(.uppercase)
        .tracking(0.4)
    }

    @ViewBuilder
    private var readOnlyTableTrailingHeader: some View {
        switch sessionExercise.exercise?.loggingType {
        case .cardio:
            HStack(spacing: WorkoutLogTheme.setInputClusterSpacing) {
                Text("Time")
                    .frame(maxWidth: .infinity, alignment: .trailing)
                Text("Distance")
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(width: WorkoutLogTheme.colKgReps, alignment: .trailing)
        default:
            Text(WorkoutSetDisplay.readOnlyTrailingHeaderLabel(
                exercise: sessionExercise.exercise,
                weightUnit: weightUnitLabel
            ))
                .multilineTextAlignment(.trailing)
                .frame(width: WorkoutLogTheme.colKgReps, alignment: .trailing)
        }
    }

    @ViewBuilder
    private var tableTrailingHeader: some View {
        switch loggingMode {
        case .cardio:
            HStack(spacing: WorkoutLogTheme.setInputClusterSpacing) {
                Text("Time")
                    .frame(maxWidth: .infinity, alignment: .trailing)
                Text("Distance")
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(width: WorkoutLogTheme.colKgReps, alignment: .trailing)
        default:
            Text(setTableTrailingHeader)
                .multilineTextAlignment(.trailing)
                .frame(width: WorkoutLogTheme.colKgReps, alignment: .trailing)
        }
    }

    private var setTableTrailingHeader: String {
        switch loggingMode {
        case .duration: return "Duration"
        case .bodyweight: return "Reps"
        case .strength: return "\(weightUnitLabel) × reps"
        case .cardio: return ""
        }
    }

    /// Value-only previous result, e.g. `80 × 8`, `20`, `1:00`, or `20:00 · 3.2 km`, or em dash when none.
    /// Caller passes the previous set looked up from the cached `previousSetsByOrder` dict
    /// so the relationship traversal happens once per render, not once per visible row.
    private func previousCompactCell(prevSet: WorkoutSet?) -> String {
        guard let prevSet else { return WorkoutSetDisplay.emptyPlaceholder }
        return WorkoutSetDisplay.formatCompactResult(
            set: prevSet,
            exercise: sessionExercise.exercise,
            weightUnit: weightUnitLabel
        )
    }

    private func historicalPreviousEntryValue(prevSet: WorkoutSet?, compactDisplay: String) -> SetEntryPreviousValue? {
        guard let prevSet, compactDisplay != WorkoutSetDisplay.emptyPlaceholder else { return nil }
        return setEntryPreviousValue(from: prevSet)
    }

    private func setEntryPreviousValue(from set: WorkoutSet) -> SetEntryPreviousValue {
        let fields = pendingSetFields(
            for: sessionExercise.exercise?.loggingType,
            seeded: (
                set.weight,
                set.reps,
                set.durationSeconds,
                set.distanceMeters
            )
        )
        return SetEntryPreviousValue(
            weight: fields.weight,
            reps: fields.reps,
            durationSeconds: fields.durationSeconds,
            distanceMeters: fields.distanceMeters
        )
    }

    private func confirmedSetsForPR(including triggeringSet: WorkoutSet? = nil) -> [WorkoutSet] {
        let loggingType = sessionExercise.exercise?.loggingType ?? .strength
        let qualifies: (WorkoutSet) -> Bool = { set in
            WorkoutSetLoggingRules.qualifiesForPR(set: set, loggingType: loggingType)
        }
        var sets = sortedSets.filter { !$0.isPendingSuggestion && qualifies($0) }
        if let triggeringSet, qualifies(triggeringSet),
           !sets.contains(where: { $0.persistentModelID == triggeringSet.persistentModelID }) {
            sets.append(triggeringSet)
        }
        return sets
    }

    private func refreshPersonalRecordMarker(triggeringSet: WorkoutSet? = nil) {
        let previousID = personalRecordSetID
        let triggeringID = triggeringSet?.persistentModelID
        let best = PreviousWorkoutLookup.bestQualifyingPersonalRecordSet(
            among: confirmedSetsForPR(including: triggeringSet),
            for: sessionExercise,
            excluding: currentSession,
            allSessions: allSessions
        )
        let newID = best?.persistentModelID
        personalRecordSetID = newID

        guard let triggeringID, let newID, newID != previousID, triggeringID == newID else { return }
        Self.firePersonalRecordHaptic()
    }

    private static func firePersonalRecordHaptic() {
        DispatchQueue.main.async {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.prepare()
            generator.impactOccurred()
        }
    }

    private func handleSetConfirmed(_ confirmedSet: WorkoutSet) {
        refreshPersonalRecordMarker(triggeringSet: confirmedSet)
        onSetConfirmed(confirmedSet)
    }
}

// MARK: - Set row

private struct SetLogRowView: View {
    @Environment(SetEntryKeypadSession.self) private var keypadSession
    @AppStorage("settings.units") private var unitsRawValue: String = "kg"
    @Bindable var set: WorkoutSet
    let exercise: Exercise?
    let sessionExerciseID: PersistentIdentifier
    let loggingMode: SetRowLoggingMode
    /// Previous session value only, e.g. `80 × 8`, `20`, or `1:00`, or `—` if none.
    let previousCompactDisplay: String
    let previousEntryValue: SetEntryPreviousValue?
    let isEditable: Bool
    /// When false, inputs keep active styling but ignore taps (e.g. delete-set mode).
    let allowsInteraction: Bool
    /// When true, show the same field layout as active logging (inputs disabled if `isEditable` is false).
    let showsInputAppearance: Bool
    let showPersonalRecordIndicator: Bool
    let onSetConfirmed: () -> Void
    @State private var hasInitialized = false
    @State private var weightText = ""
    @State private var repsText = ""
    @State private var durationDigitBuffer = ""
    @State private var distanceKmText = ""
    @State private var isSyncingFromModel = false
    @State private var focusedField: SetEntryField?
    @State private var replaceFocusedValueOnNextDigit = false

    private var entryColor: Color {
        if displayedAsPending {
            return Color(uiColor: .systemGray2)
        }
        return WorkoutLogTheme.textPrimary
    }

    private var displayedAsPending: Bool {
        self.set.isPendingSuggestion && showsInputAppearance
    }

    private var readOnlyLoggedValue: some View {
        Text(
            WorkoutSetDisplay.formatLoggedSet(
                set: set,
                exercise: exercise,
                weightUnit: unitsRawValue == "lb" ? "lb" : "kg"
            )
        )
        .font(.body.weight(.medium).monospacedDigit())
        .foregroundStyle(entryColor)
        .multilineTextAlignment(.trailing)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityLabel("Logged result")
    }

    @ViewBuilder
    private var setInputCluster: some View {
        HStack(spacing: WorkoutLogTheme.setInputClusterSpacing) {
            switch loggingMode {
            case .duration:
                fieldButton(
                    valueText: durationDisplayText,
                    placeholder: "time",
                    accessibilityLabel: "Duration",
                    field: .duration
                )
            case .cardio:
                fieldButton(
                    valueText: durationDisplayText,
                    placeholder: "time",
                    accessibilityLabel: "Time",
                    field: .duration
                )

                fieldButton(
                    valueText: distanceDisplayText,
                    placeholder: "km",
                    accessibilityLabel: "Distance in kilometers",
                    field: .distance
                )
            case .bodyweight:
                fieldButton(
                    valueText: repsText,
                    placeholder: "reps",
                    accessibilityLabel: "Repetitions",
                    field: .reps
                )
            case .strength:
                fieldButton(
                    valueText: weightText,
                    placeholder: weightUnitPlaceholder,
                    accessibilityLabel: weightAccessibilityLabel,
                    field: .weight
                )

                Text("×")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(WorkoutLogTheme.textMuted)
                    .frame(minWidth: 12)
                    .padding(.horizontal, 2)

                fieldButton(
                    valueText: repsText,
                    placeholder: "reps",
                    accessibilityLabel: "Repetitions",
                    field: .reps
                )
            }

            if displayedAsPending, allowsInteraction {
                Button {
                    confirmPendingSet()
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color(uiColor: .systemGray2))
                .padding(.leading, 4)
                .accessibilityLabel("Accept suggested set")
                .accessibilityHint("Confirms this set and starts rest timer")
            }
        }
    }

    private var weightAccessibilityLabel: String {
        unitsRawValue == "lb" ? "Weight in pounds" : "Weight in kilograms"
    }

    private var weightUnitPlaceholder: String {
        unitsRawValue == "lb" ? "lb" : "kg"
    }

    private var durationDisplayText: String {
        if !durationDigitBuffer.isEmpty {
            return WorkoutDurationFormat.display(
                seconds: WorkoutDurationFormat.seconds(fromDigitBuffer: durationDigitBuffer)
            )
        }
        return formattedDuration(set.durationSeconds)
    }

    private var distanceDisplayText: String {
        let trimmed = distanceKmText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, let km = Double(trimmed), km >= 0 {
            return WorkoutDistanceFormat.displayKilometers(meters: km * 1000)
        }
        return formattedDistanceKm(set.distanceMeters)
    }

    private var previousColumnForeground: Color {
        previousCompactDisplay == "—" ? WorkoutLogTheme.textMuted : WorkoutLogTheme.textSecondary
    }

    private var weightUnit: String {
        unitsRawValue == "lb" ? "lb" : "kg"
    }

    private func convertStoredKgToDisplay(_ kg: Double) -> Double {
        WeightUnitFormatting.displayWeight(fromStoredKg: kg, unit: weightUnit)
    }

    private func convertDisplayToStoredKg(_ displayWeight: Double) -> Double {
        WeightUnitFormatting.storedKg(fromDisplayWeight: displayWeight, unit: weightUnit)
    }

    var body: some View {
        HStack(alignment: .center, spacing: WorkoutLogTheme.colTableSpacing) {
            Text("\(set.setOrder)")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(entryColor)
                .frame(width: WorkoutLogTheme.colSet, alignment: .leading)
                .monospacedDigit()
                .overlay(alignment: .topTrailing) {
                    if showPersonalRecordIndicator {
                        Text("PR")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(WorkoutLogTheme.accent.opacity(0.92))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(WorkoutLogTheme.accent.opacity(0.12))
                            )
                            .offset(x: 14, y: -6)
                            .accessibilityLabel("Personal record")
                    }
                }

            Text(previousCompactDisplay)
                .font(.caption2.weight(.medium))
                .foregroundStyle(previousColumnForeground)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .frame(width: WorkoutLogTheme.colPrevious, alignment: .center)
                .accessibilityLabel("Previous result \(previousCompactDisplay)")

            Spacer(minLength: 0)

            if showsInputAppearance {
                setInputCluster
                    .allowsHitTesting(allowsInteraction)
                    .frame(width: WorkoutLogTheme.colKgReps, alignment: .trailing)
                    .layoutPriority(1)
            } else {
                readOnlyLoggedValue
                    .frame(width: WorkoutLogTheme.colKgReps, alignment: .trailing)
                    .layoutPriority(1)
            }
        }
        .padding(.vertical, 6)
        .onAppear {
            syncFromModel()
            hasInitialized = true
        }
        .onChange(of: set.weight) { oldValue, newValue in
            guard hasInitialized, newValue != oldValue else { return }
            if effectiveFocusedField != .weight {
                weightText = formattedWeight(newValue)
            }
        }
        .onChange(of: set.reps) { oldValue, newValue in
            guard hasInitialized, newValue != oldValue else { return }
            if effectiveFocusedField != .reps {
                repsText = formattedReps(newValue)
            }
        }
        .onChange(of: set.durationSeconds) { oldValue, newValue in
            guard hasInitialized, newValue != oldValue else { return }
            if effectiveFocusedField != .duration {
                durationDigitBuffer = WorkoutDurationFormat.digitBuffer(fromSeconds: newValue ?? 0)
            }
        }
        .onChange(of: set.distanceMeters) { oldValue, newValue in
            guard hasInitialized, newValue != oldValue else { return }
            if effectiveFocusedField != .distance {
                distanceKmText = WorkoutDistanceFormat.kmText(fromMeters: newValue)
            }
        }
        .onChange(of: keypadSession.activeSetID) { _, activeSetID in
            if activeSetID != set.persistentModelID {
                if focusedField != nil {
                    clearFocusWithoutBroadcast()
                }
            } else if let activeField = keypadSession.activeField {
                focusedField = activeField
            }
        }
        .onChange(of: keypadSession.activeField) { _, activeField in
            guard keypadSession.activeSetID == set.persistentModelID else { return }
            if let activeField {
                focusedField = activeField
                replaceFocusedValueOnNextDigit = true
            }
        }
    }

    private func isFieldKeypadFocused(_ field: SetEntryField) -> Bool {
        keypadSession.activeSetID == set.persistentModelID && keypadSession.activeField == field
    }

    private func activateField(_ field: SetEntryField) {
        guard allowsInteraction else { return }

        if keypadSession.activeSetID == set.persistentModelID,
           let currentField = keypadSession.activeField,
           currentField != field {
            commitDraft(for: currentField)
        }

        focusedField = field
        replaceFocusedValueOnNextDigit = true
        keypadSession.focus(
            setID: set.persistentModelID,
            sessionExerciseID: sessionExerciseID,
            field: field,
            canUsePrevious: previousEntryValue != nil,
            onCommand: { command, value in
                handleKeypadCommand(command, value: value)
            },
            onDismiss: {
                performCloseKeypad()
            }
        )
    }

    private func commitDraft(for field: SetEntryField) {
        switch field {
        case .weight:
            commitWeightDraftIfValid()
        case .reps:
            commitRepsDraftIfValid()
        case .duration:
            commitDurationDraftIfValid()
        case .distance:
            commitDistanceDraftIfValid()
        }
    }

    private var effectiveFocusedField: SetEntryField? {
        guard keypadSession.activeSetID == set.persistentModelID else { return nil }
        return keypadSession.activeField ?? focusedField
    }

    private func fieldButton(
        valueText: String,
        placeholder: String,
        accessibilityLabel: String,
        field: SetEntryField
    ) -> some View {
        let isEmpty = valueText.isEmpty
        return Button {
            activateField(field)
        } label: {
            Text(isEmpty ? placeholder : valueText)
                .font(.body.weight(.medium).monospacedDigit())
                .foregroundStyle(isEmpty ? WorkoutLogTheme.textMuted : entryColor)
                .frame(minWidth: 48, maxWidth: .infinity, minHeight: WorkoutLogTheme.setInputMinHeight, alignment: .trailing)
                .padding(.horizontal, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(UITheme.controlFillMuted)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(
                                    isFieldKeypadFocused(field) ? WorkoutLogTheme.accent.opacity(0.65) : .clear,
                                    lineWidth: 1
                                )
                        )
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private func appendDigit(_ digit: String) {
        guard allowsInteraction, let field = effectiveFocusedField else { return }
        switch field {
        case .weight:
            if replaceFocusedValueOnNextDigit {
                weightText = digit
                replaceFocusedValueOnNextDigit = false
            } else {
                weightText = appendedCharacter(to: weightText, character: digit)
            }
        case .reps:
            if replaceFocusedValueOnNextDigit {
                repsText = digit
                replaceFocusedValueOnNextDigit = false
            } else {
                repsText = appendedCharacter(to: repsText, character: digit)
            }
        case .duration:
            if replaceFocusedValueOnNextDigit {
                durationDigitBuffer = digit
                replaceFocusedValueOnNextDigit = false
            } else {
                durationDigitBuffer = appendedCharacter(to: durationDigitBuffer, character: digit)
            }
        case .distance:
            if replaceFocusedValueOnNextDigit {
                distanceKmText = digit
                replaceFocusedValueOnNextDigit = false
            } else {
                distanceKmText = appendedCharacter(to: distanceKmText, character: digit)
            }
        }
    }

    private func appendDot() {
        guard allowsInteraction else { return }
        switch effectiveFocusedField {
        case .weight:
            guard loggingMode == .strength else { return }
            guard !weightText.contains(".") else { return }
            if replaceFocusedValueOnNextDigit {
                weightText = "0."
                replaceFocusedValueOnNextDigit = false
            } else {
                weightText = weightText.isEmpty ? "0." : "\(weightText)."
            }
        case .distance:
            guard loggingMode == .cardio else { return }
            guard !distanceKmText.contains(".") else { return }
            distanceKmText = distanceKmText.isEmpty ? "0." : "\(distanceKmText)."
        default:
            return
        }
    }

    private func moveToRepsFromWeight() {
        guard allowsInteraction else { return }
        if loggingMode == .cardio {
            guard effectiveFocusedField == .duration else { return }
            commitDurationDraftIfValid()
            activateField(.distance)
            return
        }
        guard loggingMode == .strength else { return }
        guard effectiveFocusedField == .weight else { return }
        commitWeightDraftIfValid()
        activateField(.reps)
    }

    private func backspace() {
        guard allowsInteraction, let field = effectiveFocusedField else { return }
        switch field {
        case .weight:
            if !weightText.isEmpty {
                weightText.removeLast()
            }
            if weightText.isEmpty {
                replaceFocusedValueOnNextDigit = true
            }
        case .reps:
            if !repsText.isEmpty {
                repsText.removeLast()
            }
            if repsText.isEmpty {
                replaceFocusedValueOnNextDigit = true
            }
        case .duration:
            if !durationDigitBuffer.isEmpty {
                durationDigitBuffer.removeLast()
            }
            if durationDigitBuffer.isEmpty {
                replaceFocusedValueOnNextDigit = true
            }
        case .distance:
            if !distanceKmText.isEmpty {
                distanceKmText.removeLast()
            }
            if distanceKmText.isEmpty {
                replaceFocusedValueOnNextDigit = true
            }
        }
    }

    private func closeKeypad() {
        performCloseKeypad()
    }

    private func performCloseKeypad() {
        forceCommitDraftValues()
        normalizeDraftTextFromModel()
        focusedField = nil
        replaceFocusedValueOnNextDigit = false
        keypadSession.blur(setID: set.persistentModelID)
    }

    private func clearFocusWithoutBroadcast() {
        forceCommitDraftValues()
        normalizeDraftTextFromModel()
        focusedField = nil
        replaceFocusedValueOnNextDigit = false
    }

    private func appendedCharacter(to current: String, character: String) -> String {
        if current == "0" {
            return character
        }
        return current + character
    }

    private func syncFromModel() {
        isSyncingFromModel = true
        defer { isSyncingFromModel = false }
        normalizeNonStrengthStoredValues()
        weightText = formattedWeight(set.weight)
        repsText = formattedReps(set.reps)
        durationDigitBuffer = WorkoutDurationFormat.digitBuffer(fromSeconds: set.durationSeconds ?? 0)
        distanceKmText = WorkoutDistanceFormat.kmText(fromMeters: set.distanceMeters)
    }

    private func normalizeNonStrengthStoredValues() {
        switch loggingMode {
        case .bodyweight, .duration, .cardio:
            if set.weight != 0 { set.weight = 0 }
        case .strength:
            break
        }
        if loggingMode == .duration || loggingMode == .cardio, set.reps != 0 {
            set.reps = 0
        }
    }

    private func commitWeightDraftIfValid() {
        if loggingMode != .strength {
            if set.weight != 0 {
                set.weight = 0
            }
            return
        }
        guard !isSyncingFromModel else { return }
        let trimmed = weightText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            if set.weight != 0 {
                set.weight = 0
            }
            return
        }
        guard let value = Double(trimmed), value >= 0 else { return }
        let valueKg = convertDisplayToStoredKg(value)
        if set.weight != valueKg {
            set.weight = valueKg
        }
    }

    private func commitRepsDraftIfValid() {
        if loggingMode == .duration || loggingMode == .cardio {
            if set.reps != 0 {
                set.reps = 0
            }
            return
        }
        guard !isSyncingFromModel else { return }
        let trimmed = repsText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            if set.reps != 0 {
                set.reps = 0
            }
            return
        }
        guard let value = Int(trimmed), value >= 0 else { return }
        if set.reps != value {
            set.reps = value
        }
    }

    private func commitDurationDraftIfValid() {
        guard loggingMode == .duration || loggingMode == .cardio, !isSyncingFromModel else { return }
        let seconds = WorkoutDurationFormat.seconds(fromDigitBuffer: durationDigitBuffer)
        let stored = seconds > 0 ? seconds : nil
        if set.durationSeconds != stored {
            set.durationSeconds = stored
        }
        if set.weight != 0 {
            set.weight = 0
        }
        if set.reps != 0 {
            set.reps = 0
        }
    }

    private func commitDistanceDraftIfValid() {
        guard loggingMode == .cardio, !isSyncingFromModel else { return }
        let trimmed = distanceKmText.trimmingCharacters(in: .whitespacesAndNewlines)
        let stored: Double?
        if trimmed.isEmpty {
            stored = nil
        } else if let km = Double(trimmed), km >= 0 {
            stored = km > 0 ? km * 1000 : nil
        } else {
            return
        }
        if set.distanceMeters != stored {
            set.distanceMeters = stored
        }
        if set.weight != 0 {
            set.weight = 0
        }
        if set.reps != 0 {
            set.reps = 0
        }
    }

    private func formattedDuration(_ seconds: Int?) -> String {
        let value = seconds ?? 0
        guard value > 0 else { return showsInputAppearance ? "" : WorkoutDurationFormat.display(seconds: 0) }
        return WorkoutDurationFormat.display(seconds: value)
    }

    private func formattedDistanceKm(_ meters: Double?) -> String {
        guard let meters, meters > 0 else { return showsInputAppearance ? "" : WorkoutDistanceFormat.displayKilometers(meters: 0) }
        return WorkoutDistanceFormat.displayKilometers(meters: meters)
    }

    private func formattedWeight(_ weight: Double) -> String {
        guard weight > 0 else { return showsInputAppearance ? "" : "0" }
        return WeightUnitFormatting.formatWeight(fromStoredKg: weight, unit: weightUnit)
    }

    private func formattedReps(_ reps: Int) -> String {
        guard reps > 0 else { return showsInputAppearance ? "" : "0" }
        return String(reps)
    }

    private func confirmPendingSet() {
        guard allowsInteraction, set.isPendingSuggestion else { return }
        performCloseKeypad()
        normalizeNonStrengthStoredValues()
        set.isPendingSuggestion = false
        if WorkoutSetLoggingRules.isComplete(set: set, loggingType: loggingMode.exerciseLoggingType) {
            onSetConfirmed()
        }
    }

    private func forceCommitDraftValues() {
        guard !isSyncingFromModel else { return }

        switch loggingMode {
        case .duration:
            commitDurationDraftIfValid()
        case .cardio:
            commitDurationDraftIfValid()
            commitDistanceDraftIfValid()
        case .bodyweight:
            if set.weight != 0 {
                set.weight = 0
            }
            commitRepsDraftIfValid()
        case .strength:
            let trimmedWeight = weightText.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedWeight.isEmpty {
                if set.weight != 0 {
                    set.weight = 0
                }
            } else if let weightValue = Double(trimmedWeight), weightValue >= 0 {
                let weightKg = convertDisplayToStoredKg(weightValue)
                if set.weight != weightKg {
                    set.weight = weightKg
                }
            }
            commitRepsDraftIfValid()
        }
    }

    private func normalizeDraftTextFromModel() {
        isSyncingFromModel = true
        defer { isSyncingFromModel = false }
        weightText = formattedWeight(set.weight)
        repsText = formattedReps(set.reps)
        durationDigitBuffer = WorkoutDurationFormat.digitBuffer(fromSeconds: set.durationSeconds ?? 0)
        distanceKmText = WorkoutDistanceFormat.kmText(fromMeters: set.distanceMeters)
    }

    private func handleKeypadCommand(_ command: SetEntryKeyCommand, value: String?) {
        switch command {
        case .digit:
            if let value, value.count == 1 {
                appendDigit(value)
            }
        case .dot:
            appendDot()
        case .multiply:
            moveToRepsFromWeight()
        case .backspace:
            backspace()
        case .previous:
            fillFromPreviousEntryValue()
        case .done:
            closeKeypad()
        }
    }

    private func fillFromPreviousEntryValue() {
        guard allowsInteraction, let previousEntryValue else { return }

        switch loggingMode {
        case .strength:
            weightText = formattedWeight(previousEntryValue.weight)
            repsText = formattedReps(previousEntryValue.reps)
            durationDigitBuffer = ""
            distanceKmText = ""
            set.weight = previousEntryValue.weight
            set.reps = previousEntryValue.reps
            set.durationSeconds = nil
            set.distanceMeters = nil
        case .bodyweight:
            weightText = ""
            repsText = formattedReps(previousEntryValue.reps)
            durationDigitBuffer = ""
            distanceKmText = ""
            set.weight = 0
            set.reps = previousEntryValue.reps
            set.durationSeconds = nil
            set.distanceMeters = nil
        case .duration:
            weightText = ""
            repsText = ""
            durationDigitBuffer = WorkoutDurationFormat.digitBuffer(fromSeconds: previousEntryValue.durationSeconds ?? 0)
            distanceKmText = ""
            set.weight = 0
            set.reps = 0
            set.durationSeconds = previousEntryValue.durationSeconds
            set.distanceMeters = nil
        case .cardio:
            weightText = ""
            repsText = ""
            durationDigitBuffer = WorkoutDurationFormat.digitBuffer(fromSeconds: previousEntryValue.durationSeconds ?? 0)
            distanceKmText = WorkoutDistanceFormat.kmText(fromMeters: previousEntryValue.distanceMeters)
            set.weight = 0
            set.reps = 0
            set.durationSeconds = previousEntryValue.durationSeconds
            set.distanceMeters = previousEntryValue.distanceMeters
        }

        replaceFocusedValueOnNextDigit = true
    }
}

private struct SetEntryKeypad: View {
    private static let panelHeight: CGFloat = 304
    private static let keyHeight: CGFloat = 50
    private static let panelBackground = Color(
        uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 0.08, green: 0.08, blue: 0.09, alpha: 1)
                : UIColor.secondarySystemBackground
        }
    )
    let isPreviousEnabled: Bool
    let onDigit: (String) -> Void
    let onDot: () -> Void
    let onMultiply: () -> Void
    let onBackspace: () -> Void
    let onPrevious: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: UITheme.spaceM) {
            HStack {
                Button("Previous") { onPrevious() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isPreviousEnabled ? WorkoutLogTheme.accent : WorkoutLogTheme.textMuted)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(UITheme.controlFill)
                    )
                    .buttonStyle(SetEntryKeypadPressStyle())
                    .disabled(!isPreviousEnabled)

                Spacer(minLength: 0)

                Button("Done") { onDone() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WorkoutLogTheme.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(UITheme.controlFill)
                    )
                    .buttonStyle(SetEntryKeypadPressStyle())
            }

            HStack(spacing: UITheme.spaceS) {
                keypadButton("1") { onDigit("1") }
                keypadButton("2") { onDigit("2") }
                keypadButton("3") { onDigit("3") }
                utilityButton(systemName: "delete.left") { onBackspace() }
            }
            HStack(spacing: UITheme.spaceS) {
                keypadButton("4") { onDigit("4") }
                keypadButton("5") { onDigit("5") }
                keypadButton("6") { onDigit("6") }
                utilityButton("×") { onMultiply() }
            }
            HStack(spacing: UITheme.spaceS) {
                keypadButton("7") { onDigit("7") }
                keypadButton("8") { onDigit("8") }
                keypadButton("9") { onDigit("9") }
                utilityButton(".") { onDot() }
            }
            HStack(spacing: UITheme.spaceS) {
                Color.clear
                    .frame(maxWidth: .infinity, minHeight: Self.keyHeight)
                keypadButton("0") { onDigit("0") }
                Color.clear
                    .frame(maxWidth: .infinity, minHeight: Self.keyHeight)
                Color.clear
                    .frame(maxWidth: .infinity, minHeight: Self.keyHeight)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, UITheme.spaceL)
        .padding(.top, UITheme.spaceS)
        .padding(.bottom, UITheme.spaceM)
        .frame(maxWidth: .infinity)
        .frame(height: Self.panelHeight, alignment: .top)
        .background(Self.panelBackground)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(WorkoutLogTheme.surfaceStroke.opacity(0.65))
                .frame(height: 1)
        }
    }

    private func keypadButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: Self.keyHeight, maxHeight: Self.keyHeight)
                .foregroundStyle(WorkoutLogTheme.textPrimary)
                .background(keypadKeyBackground(muted: true))
                .contentShape(Rectangle())
        }
        .buttonStyle(SetEntryKeypadPressStyle())
    }

    private func utilityButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.title3.weight(.medium))
                .frame(maxWidth: .infinity, minHeight: Self.keyHeight, maxHeight: Self.keyHeight)
                .foregroundStyle(WorkoutLogTheme.textSecondary)
                .background(keypadKeyBackground(muted: false))
                .contentShape(Rectangle())
        }
        .buttonStyle(SetEntryKeypadPressStyle())
    }

    private func utilityButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.title3.weight(.medium))
                .frame(maxWidth: .infinity, minHeight: Self.keyHeight, maxHeight: Self.keyHeight)
                .foregroundStyle(WorkoutLogTheme.textSecondary)
                .background(keypadKeyBackground(muted: false))
                .contentShape(Rectangle())
        }
        .buttonStyle(SetEntryKeypadPressStyle())
    }

    private func keypadKeyBackground(muted: Bool) -> some View {
        RoundedRectangle(cornerRadius: UITheme.cornerRadiusSmall, style: .continuous)
            .fill(muted ? UITheme.controlFillMuted : UITheme.controlFill)
            .overlay(
                RoundedRectangle(cornerRadius: UITheme.cornerRadiusSmall, style: .continuous)
                    .stroke(
                        WorkoutLogTheme.surfaceStroke.opacity(muted ? 0.35 : 0.28),
                        lineWidth: muted ? 0.6 : 0.6
                    )
            )
    }
}

// MARK: - Pending set seeding

private typealias SeededPendingValues = (
    weight: Double,
    reps: Int,
    durationSeconds: Int?,
    distanceMeters: Double?
)

/// Maps raw previous-session values to pending-row fields by logging type (mirrors `addSet`).
private func pendingSetFields(
    for loggingType: ExerciseLoggingType?,
    seeded: SeededPendingValues
) -> SeededPendingValues {
    let type = loggingType ?? .strength
    let isBodyweight = type == .bodyweight
    let isDuration = type == .duration || type == .mobility
    let isCardio = type == .cardio
    return (
        weight: (isBodyweight || isDuration || isCardio) ? 0 : seeded.weight,
        reps: (isDuration || isCardio) ? 0 : seeded.reps,
        durationSeconds: (isDuration || isCardio) ? seeded.durationSeconds : nil,
        distanceMeters: isCardio ? seeded.distanceMeters : nil
    )
}

// MARK: - Lookup

private enum PreviousWorkoutLookup {
    static func previousSessionWithSets(
        for exercise: Exercise,
        excluding currentSession: WorkoutSession,
        allSessions: [WorkoutSession]
    ) -> (session: WorkoutSession, sessionExercise: WorkoutSessionExercise)? {
        let exerciseID = exercise.persistentModelID
        let currentID = currentSession.persistentModelID

        let candidates = allSessions.filter { session in
            session.completedAt != nil && session.persistentModelID != currentID
        }
        .sorted {
            ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast)
        }

        for session in candidates {
            guard let match = session.sessionExercises.first(where: {
                $0.exercise?.persistentModelID == exerciseID
            }),
                  !match.sets.isEmpty
            else { continue }
            return (session, match)
        }
        return nil
    }

    /// e.g. "Last: 24 Apr" or "Last: 24 Apr 2026" when the year differs from `now`.
    static func compactLastSessionDateLabel(completedAt: Date, now: Date = .now) -> String {
        let cal = Calendar.current
        let ySession = cal.component(.year, from: completedAt)
        let yNow = cal.component(.year, from: now)
        if ySession != yNow {
            return "Last: \(completedAt.formatted(.dateTime.day().month(.abbreviated).year()))"
        }
        return "Last: \(completedAt.formatted(.dateTime.day().month(.abbreviated)))"
    }

    /// Compact previous cell: `80 × 8`, reps only, or duration only.
    static func formatPreviousCompact(
        weight: Double,
        reps: Int,
        unit: String,
        loggingType: ExerciseLoggingType = .strength,
        durationSeconds: Int? = nil,
        distanceMeters: Double? = nil
    ) -> String {
        return WorkoutSetDisplay.formatCompactResult(
            weight: weight,
            reps: reps,
            weightUnit: unit,
            loggingType: loggingType,
            durationSeconds: durationSeconds,
            distanceMeters: distanceMeters
        )
    }

    static func isPersonalRecord(
        set: WorkoutSet,
        for sessionExercise: WorkoutSessionExercise,
        excluding currentSession: WorkoutSession,
        allSessions: [WorkoutSession]
    ) -> Bool {
        let loggingType = sessionExercise.exercise?.loggingType ?? .strength
        let currentID = currentSession.persistentModelID

        switch loggingType {
        case .duration:
            guard let duration = set.durationSeconds, duration > 0 else { return false }
            var previousBestDuration = 0
            for session in allSessions where session.completedAt != nil && session.persistentModelID != currentID {
                for historicalExercise in session.sessionExercises where matchesExercise(sessionExercise, historicalExercise) {
                    for historicalSet in historicalExercise.sets {
                        let historicalDuration = historicalSet.durationSeconds ?? 0
                        if historicalDuration > 0 {
                            previousBestDuration = max(previousBestDuration, historicalDuration)
                        }
                    }
                }
            }
            if previousBestDuration == 0 { return true }
            return duration > previousBestDuration

        case .bodyweight:
            guard WorkoutSetLoggingRules.isComplete(set: set, loggingType: .bodyweight) else { return false }
            var previousBestReps = 0
            for session in allSessions where session.completedAt != nil && session.persistentModelID != currentID {
                for historicalExercise in session.sessionExercises where matchesExercise(sessionExercise, historicalExercise) {
                    for historicalSet in historicalExercise.sets where historicalSet.reps > 0 {
                        previousBestReps = max(previousBestReps, historicalSet.reps)
                    }
                }
            }
            if previousBestReps == 0 { return true }
            return set.reps > previousBestReps

        case .cardio:
            guard WorkoutSetLoggingRules.isComplete(set: set, loggingType: .cardio) else { return false }
            let duration = set.durationSeconds ?? 0
            let distance = set.distanceMeters ?? 0

            let epsilon = 0.000_001
            var previousBestDistance: Double = 0
            var previousBestDurationAtDistance: Int = 0

            for session in allSessions where session.completedAt != nil && session.persistentModelID != currentID {
                for historicalExercise in session.sessionExercises where matchesExercise(sessionExercise, historicalExercise) {
                    for historicalSet in historicalExercise.sets {
                        let historicalDistance = historicalSet.distanceMeters ?? 0
                        let historicalDuration = historicalSet.durationSeconds ?? 0
                        guard historicalDistance > 0 || historicalDuration > 0 else { continue }
                        if historicalDistance > previousBestDistance + epsilon {
                            previousBestDistance = historicalDistance
                            previousBestDurationAtDistance = historicalDuration
                        } else if abs(historicalDistance - previousBestDistance) <= epsilon {
                            previousBestDurationAtDistance = max(previousBestDurationAtDistance, historicalDuration)
                        }
                    }
                }
            }

            if previousBestDistance <= 0 && previousBestDurationAtDistance <= 0 {
                return true
            }
            if distance > previousBestDistance + epsilon {
                return true
            }
            if abs(distance - previousBestDistance) <= epsilon && duration > previousBestDurationAtDistance {
                return true
            }
            return false

        case .mobility:
            guard let duration = set.durationSeconds, duration > 0 else { return false }
            var previousBestMobilityDuration = 0
            for session in allSessions where session.completedAt != nil && session.persistentModelID != currentID {
                for historicalExercise in session.sessionExercises where matchesExercise(sessionExercise, historicalExercise) {
                    for historicalSet in historicalExercise.sets {
                        let historicalDuration = historicalSet.durationSeconds ?? 0
                        if historicalDuration > 0 {
                            previousBestMobilityDuration = max(previousBestMobilityDuration, historicalDuration)
                        }
                    }
                }
            }
            if previousBestMobilityDuration == 0 { return true }
            return duration > previousBestMobilityDuration

        case .strength:
            guard WorkoutSetLoggingRules.isComplete(set: set, loggingType: .strength) else { return false }

            let epsilon = 0.000_001
            var previousBestWeight: Double?
            var previousBestRepsAtBestWeight = 0

            for session in allSessions where session.completedAt != nil && session.persistentModelID != currentID {
                for historicalExercise in session.sessionExercises where matchesExercise(sessionExercise, historicalExercise) {
                    for historicalSet in historicalExercise.sets
                        where WorkoutSetLoggingRules.isComplete(set: historicalSet, loggingType: .strength) {
                        if let bestWeight = previousBestWeight {
                            if historicalSet.weight > bestWeight + epsilon {
                                previousBestWeight = historicalSet.weight
                                previousBestRepsAtBestWeight = historicalSet.reps
                            } else if abs(historicalSet.weight - bestWeight) <= epsilon {
                                previousBestRepsAtBestWeight = max(previousBestRepsAtBestWeight, historicalSet.reps)
                            }
                        } else {
                            previousBestWeight = historicalSet.weight
                            previousBestRepsAtBestWeight = historicalSet.reps
                        }
                    }
                }
            }

            guard let previousBestWeight else {
                return true
            }
            if set.weight > previousBestWeight + epsilon {
                return true
            }
            if abs(set.weight - previousBestWeight) <= epsilon && set.reps > previousBestRepsAtBestWeight {
                return true
            }
            return false
        }
    }

    /// Best confirmed set in this workout that beats completed history; higher weight, then reps; ties keep earlier `setOrder`.
    static func bestQualifyingPersonalRecordSet(
        among confirmedSets: [WorkoutSet],
        for sessionExercise: WorkoutSessionExercise,
        excluding currentSession: WorkoutSession,
        allSessions: [WorkoutSession]
    ) -> WorkoutSet? {
        let ordered = confirmedSets.sorted { $0.setOrder < $1.setOrder }
        var best: WorkoutSet?
        for set in ordered where isPersonalRecord(
            set: set,
            for: sessionExercise,
            excluding: currentSession,
            allSessions: allSessions
        ) {
            if let incumbent = best {
                if WorkoutSetLoggingRules.isStrictlyBetterWorkoutPerformance(
                    candidate: set,
                    than: incumbent,
                    loggingType: sessionExercise.exercise?.loggingType ?? .strength
                ) {
                    best = set
                }
            } else {
                best = set
            }
        }
        return best
    }

    private static func matchesExercise(_ lhs: WorkoutSessionExercise, _ rhs: WorkoutSessionExercise) -> Bool {
        if let lhsID = lhs.exercise?.persistentModelID, let rhsID = rhs.exercise?.persistentModelID {
            return lhsID == rhsID
        }

        let lhsSource = lhs.source
        let rhsSource = rhs.source
        guard lhsSource == .sessionOnly, rhsSource == .sessionOnly else { return false }

        let lhsName = lhs.customExerciseName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rhsName = rhs.customExerciseName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !lhsName.isEmpty, !rhsName.isEmpty else { return false }
        return lhsName.caseInsensitiveCompare(rhsName) == .orderedSame
    }

}

// MARK: - Workout title field

private struct SelectAllWorkoutTitleTextField: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    var placeholder: String
    var onCommit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        textField.delegate = context.coordinator
        textField.placeholder = placeholder
        textField.font = Self.uiFont
        textField.textColor = .label
        textField.textAlignment = .natural
        textField.borderStyle = .none
        textField.backgroundColor = .clear
        textField.returnKeyType = .done
        textField.autocorrectionType = .default
        textField.autocapitalizationType = .words
        textField.addTarget(
            context.coordinator,
            action: #selector(Coordinator.editingChanged),
            for: .editingChanged
        )
        return textField
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        context.coordinator.parent = self
        if isFocused, !uiView.isFirstResponder {
            uiView.becomeFirstResponder()
        } else if !isFocused, uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
        if !uiView.isFirstResponder, uiView.text != text {
            uiView.text = text
        }
    }

    private static var uiFont: UIFont {
        let base = UIFont.preferredFont(forTextStyle: .title3)
        let descriptor = base.fontDescriptor.withSymbolicTraits(.traitBold)
            ?? base.fontDescriptor
        return UIFont(descriptor: descriptor, size: 0)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: SelectAllWorkoutTitleTextField

        init(_ parent: SelectAllWorkoutTitleTextField) {
            self.parent = parent
        }

        @objc func editingChanged(_ sender: UITextField) {
            parent.text = sender.text ?? ""
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            parent.isFocused = true
            DispatchQueue.main.async {
                textField.selectAll(nil)
            }
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            parent.isFocused = false
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            parent.onCommit()
            return true
        }
    }
}

// MARK: - Finish summary

private struct WorkoutFinishSummaryView: View {
    let workoutTitle: String
    let shareStickerContent: WorkoutShareStickerContent
    let durationText: String
    let exerciseCount: Int
    let setCount: Int
    let volumeDisplay: String
    let volumeUnit: String
    let onDone: () -> Void

    @State private var shareSheetItem: WorkoutShareSheetItem?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Duration", value: durationText)
                    LabeledContent("Exercises", value: "\(exerciseCount)")
                    LabeledContent("Sets", value: "\(setCount)")
                    LabeledContent("Total volume", value: "\(volumeDisplay) \(volumeUnit)")
                } header: {
                    Text(workoutTitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(UITheme.appBackground.ignoresSafeArea())
            .navigationTitle("Workout complete")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: presentWorkoutShareSheet) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone)
                        .buttonStyle(AccentPlainButtonStyle())
                }
            }
        }
        .presentationDetents([.medium, .large])
        .sheet(item: $shareSheetItem) { item in
            WorkoutShareSheet(fileURL: item.fileURL)
        }
    }

    private func presentWorkoutShareSheet() {
        guard let fileURL = WorkoutShareStickerExporter.temporaryPNGFileURL(from: shareStickerContent) else {
            return
        }
        shareSheetItem = WorkoutShareSheetItem(fileURL: fileURL)
    }
}

#Preview {
    NavigationStack {
        WorkoutSessionView(
            session: WorkoutSession(sessionDate: Date()),
            workoutTitle: "PUSH A"
        )
        .environmentObject(WorkoutSessionPresentationState())
        .environmentObject(RestTimerLiveActivityManager())
    }
}
