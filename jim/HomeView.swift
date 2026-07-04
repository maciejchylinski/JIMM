import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.activeWorkoutMiniBarScrollInset) private var activeWorkoutMiniBarScrollInset
    @EnvironmentObject private var workoutSessionPresentationState: WorkoutSessionPresentationState
    /// Fetches all sessions (no `completedAt` predicate) so finishing a workout reliably
    /// invalidates this query and updates history without waiting for a relaunch.
    @Query(sort: \WorkoutSession.sessionDate, order: .reverse)
    private var allSessionsBySessionDate: [WorkoutSession]

    private var completedSessions: [WorkoutSession] {
        allSessionsBySessionDate
            .filter { $0.completedAt != nil }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    private var completedWorkoutDaySet: Set<Date> {
        let calendar = Calendar.current
        let completedDates = completedSessions.compactMap(\.completedAt)
        return Set(completedDates.map { calendar.startOfDay(for: $0) })
    }

    @State private var repeatSession: WorkoutSession?
    @State private var repeatSessionTitle = ""
    @State private var showRepeatSession = false
    @State private var showActiveWorkoutBlockingAlert = false
    /// Bumped when a workout finishes so the history `List` re-evaluates against the store immediately (not only on @Query invalidation).
    @State private var workoutHistoryListVersion = 0

    private static let historyRowInsets = EdgeInsets(
        top: 12,
        leading: 20,
        bottom: 12,
        trailing: 16
    )

    private static let homeHistoryPreviewLimit = 15

    var body: some View {
        // Compute filtered/sorted completed history once per render. The previous form
        // called `completedSessions` (filter + sort over all sessions) and
        // `completedWorkoutDaySet` (another full scan) multiple times per body.
        let completedSessions = self.completedSessions
        let completedDaySet: Set<Date> = {
            let calendar = Calendar.current
            var set: Set<Date> = []
            set.reserveCapacity(completedSessions.count)
            for session in completedSessions {
                if let completedAt = session.completedAt {
                    set.insert(calendar.startOfDay(for: completedAt))
                }
            }
            return set
        }()

        return List {
            Section {
                HomeCompactWorkoutCalendar(
                    completedDaySet: completedDaySet,
                    completedSessions: completedSessions
                )
                .listRowInsets(Self.historyRowInsets)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            if completedSessions.isEmpty {
                Section {
                    WorkoutHistoryEmptyState()
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            } else {
                let previewSessions = Array(completedSessions.prefix(Self.homeHistoryPreviewLimit))
                homeWorkoutHistoryRows(sessions: previewSessions)
                if completedSessions.count > Self.homeHistoryPreviewLimit {
                    NavigationLink {
                        List {
                            Section {
                                homeWorkoutHistoryRows(sessions: completedSessions)
                            }
                        }
                        .listStyle(.insetGrouped)
                        .scrollContentBackground(.hidden)
                        .contentMargins(.bottom, activeWorkoutMiniBarScrollInset, for: .scrollContent)
                        .background(UITheme.appBackground.ignoresSafeArea())
                        .navigationTitle("All Workouts")
                        .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        Text("See More")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(UITheme.accent)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                }
            }
        }
        .id(workoutHistoryListVersion)
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.bottom, activeWorkoutMiniBarScrollInset, for: .scrollContent)
        .background(UITheme.appBackground.ignoresSafeArea())
        .navigationTitle("Workout History")
        .onReceive(NotificationCenter.default.publisher(for: .jimWorkoutSessionFinishedForHistory)) { _ in
            workoutHistoryListVersion &+= 1
        }
        .navigationDestination(isPresented: $showRepeatSession) {
            if let session = repeatSession {
                WorkoutSessionView(session: session, workoutTitle: repeatSessionTitle)
            }
        }
        .onChange(of: showRepeatSession) { _, isPresented in
            if !isPresented {
                if let session = repeatSession {
                    workoutSessionPresentationState.unregisterWorkoutSessionView(for: session.persistentModelID)
                }
                repeatSession = nil
            }
        }
        .alert("Active workout", isPresented: $showActiveWorkoutBlockingAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("You have an active workout. Finish it before starting a new workout.")
        }
    }

    @ViewBuilder
    private func homeWorkoutHistoryRows(sessions: [WorkoutSession]) -> some View {
        ForEach(sessions) { session in
            NavigationLink {
                WorkoutSessionView(
                    session: session,
                    workoutTitle: homeHistoryListTitle(for: session)
                )
            } label: {
                WorkoutHistoryRowView(session: session)
            }
            .listRowInsets(Self.historyRowInsets)
            .listRowSeparatorTint(Color(uiColor: .separator).opacity(0.55))
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                Button {
                    startRepeat(from: session, displayTitle: homeHistoryListTitle(for: session))
                } label: {
                    Label("Repeat", systemImage: "arrow.clockwise")
                }
                .tint(Color(uiColor: .systemGray4))
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    deleteCompletedSession(session)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    private func startRepeat(from source: WorkoutSession, displayTitle: String) {
        if (try? ActiveWorkoutSession.canonicalUnfinishedSessionAfterCleanup(in: modelContext)) != nil {
            showActiveWorkoutBlockingAlert = true
            return
        }
        guard let session = WorkoutSession.newRepeating(from: source, in: modelContext) else { return }
        repeatSessionTitle = displayTitle
        repeatSession = session
        workoutSessionPresentationState.registerWorkoutSessionView(for: session.persistentModelID)
        showRepeatSession = true
    }

    private func deleteCompletedSession(_ session: WorkoutSession) {
        modelContext.delete(session)
        try? modelContext.save()
    }
}

// MARK: - Compact calendar

private struct HomeCompactWorkoutCalendar: View {
    @AppStorage("settings.units") private var unitsRawValue: String = "kg"
    let completedDaySet: Set<Date>
    let completedSessions: [WorkoutSession]
    @State private var showExpandedCalendar = false

    private let calendar = Calendar.current
    private let monthTitleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL yyyy"
        return formatter
    }()

    private let columns = Array(repeating: GridItem(.flexible(minimum: 20, maximum: 24), spacing: 4), count: 7)

    private var today: Date {
        calendar.startOfDay(for: Date())
    }

    private var currentMonthStart: Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: today)) ?? today
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        guard symbols.count == 7 else { return ["S", "M", "T", "W", "T", "F", "S"] }
        let first = max(1, min(calendar.firstWeekday, 7)) - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    private var currentMonthSection: MonthSection {
        buildFullMonthSection(for: currentMonthStart)
    }

    private struct CurrentMonthStats {
        var workoutCount: Int
        var durationSeconds: Int
        var volumeKg: Double
    }

    /// Single-pass aggregate for the calendar summary card. The previous form computed
    /// `currentMonthSessions` three times (each filtering `completedSessions`) and then
    /// did a `flatMap(\.sessionExercises).flatMap(\.sets)` on every render — every set
    /// in every in-month session was traversed across three independent computed properties.
    private var currentMonthStats: CurrentMonthStats {
        var stats = CurrentMonthStats(workoutCount: 0, durationSeconds: 0, volumeKg: 0)
        for session in completedSessions {
            guard let completedAt = session.completedAt,
                  calendar.isDate(completedAt, equalTo: today, toGranularity: .month)
            else { continue }
            stats.workoutCount += 1
            stats.durationSeconds += max(0, Int(completedAt.timeIntervalSince(session.sessionDate)))
            for sessionExercise in session.sessionExercises {
                for set in sessionExercise.sets {
                    stats.volumeKg += WorkoutSetDisplay.volumeKg(
                        set: set,
                        exercise: sessionExercise.exercise
                    )
                }
            }
        }
        return stats
    }

    private var weeklyWorkoutStreak: Int {
        let weekStartDates: [Date] = completedSessions.compactMap { session in
            guard let completedAt = session.completedAt else { return nil }
            return calendar.dateInterval(of: .weekOfYear, for: completedAt)?.start
        }
        let weekStarts = Set(weekStartDates)

        guard
            let thisWeekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start,
            weekStarts.contains(thisWeekStart)
        else {
            return 0
        }

        var streak = 0
        var cursor = thisWeekStart
        while weekStarts.contains(cursor) {
            streak += 1
            guard let previousWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: cursor) else { break }
            cursor = previousWeek
        }
        return streak
    }

    private var expandedMonthSections: [MonthSection] {
        let currentYear = calendar.component(.year, from: today)
        return (1...12).compactMap { month in
            var components = DateComponents()
            components.year = currentYear
            components.month = month
            components.day = 1
            guard let monthStart = calendar.date(from: components) else { return nil }
            return buildFullMonthSection(for: monthStart)
        }
    }

    var body: some View {
        let monthTitle = monthTitleFormatter.string(from: currentMonthSection.monthStart)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: UITheme.spaceXS) {
                Text(monthTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: UITheme.spaceS)
                HStack(spacing: 4) {
                    if weeklyWorkoutStreak > 0 {
                        Text("\(weeklyWorkoutStreak) week streak")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        Image(systemName: "bolt.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(UITheme.accent)
                    }
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.bottom, 1)

            HStack(alignment: .center, spacing: 10) {
                calendarGrid(for: currentMonthSection)
                    .frame(width: 194, alignment: .leading)
                monthSummaryCard
                    .frame(width: 106, alignment: .center)
            }
            .frame(minHeight: 114, alignment: .center)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: UITheme.cornerRadius, style: .continuous)
                .fill(UITheme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: UITheme.cornerRadius, style: .continuous)
                .strokeBorder(UITheme.stroke, lineWidth: 0.7)
        )
        .contentShape(RoundedRectangle(cornerRadius: UITheme.cornerRadius, style: .continuous))
        .onTapGesture {
            showExpandedCalendar = true
        }
        .sheet(isPresented: $showExpandedCalendar) {
            NavigationStack {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: UITheme.spaceM) {
                            ForEach(expandedMonthSections) { section in
                                VStack(alignment: .leading, spacing: UITheme.spaceXS) {
                                    Text(monthTitleFormatter.string(from: section.monthStart))
                                        .font(.headline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    calendarGrid(for: section)
                                }
                                .padding(UITheme.spaceS)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: UITheme.cornerRadiusSmall, style: .continuous)
                                        .fill(UITheme.cardBackground)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: UITheme.cornerRadiusSmall, style: .continuous)
                                        .strokeBorder(UITheme.stroke, lineWidth: 0.7)
                                )
                                .id(section.id)
                            }
                        }
                        .padding(UITheme.spaceM)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .onAppear {
                        centerCurrentMonth(using: proxy)
                    }
                }
                .background(UITheme.appBackground.ignoresSafeArea())
                .navigationTitle("Calendar")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            showExpandedCalendar = false
                        }
                        .buttonStyle(AccentPlainButtonStyle())
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private func centerCurrentMonth(using proxy: ScrollViewProxy) {
        let currentMonthID = currentMonthSection.id
        guard expandedMonthSections.contains(where: { $0.id == currentMonthID }) else { return }
        DispatchQueue.main.async {
            proxy.scrollTo(currentMonthID, anchor: .center)
        }
    }

    private var monthSummaryCard: some View {
        let stats = currentMonthStats
        return VStack(alignment: .leading, spacing: 6) {
            summaryMetricCard(value: "\(stats.workoutCount)", label: "Workouts")
            summaryMetricCard(value: "\(formattedVolume(stats.volumeKg)) \(weightUnitLabel)", label: "Volume")
            summaryMetricCard(value: formattedDuration(stats.durationSeconds), label: "Time")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func summaryMetricCard(value: String, label: String) -> some View {
        VStack(alignment: .center, spacing: 3) {
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.82)
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.35)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(minHeight: 34)
        .background(
            RoundedRectangle(cornerRadius: UITheme.cornerRadiusSmall, style: .continuous)
                .fill(UITheme.cardBackgroundElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: UITheme.cornerRadiusSmall, style: .continuous)
                        .stroke(UITheme.stroke.opacity(0.6), lineWidth: 0.7)
                )
        )
    }

    private func formattedDuration(_ totalSeconds: Int) -> String {
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    private func formattedVolume(_ valueKg: Double) -> String {
        WorkoutSetDisplay.formatVolumeDisplay(
            kg: valueKg,
            weightUnit: unitsRawValue == "lb" ? "lb" : "kg"
        )
    }

    private var weightUnitLabel: String {
        unitsRawValue == "lb" ? "lb" : "kg"
    }

    @ViewBuilder
    private func calendarGrid(for section: MonthSection) -> some View {
        LazyVGrid(columns: columns, alignment: .center, spacing: 4) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
            }

            ForEach(Array(section.cells.enumerated()), id: \.offset) { _, day in
                if let day {
                    let normalizedDay = calendar.startOfDay(for: day)
                    let isToday = calendar.isDate(normalizedDay, inSameDayAs: today)
                    let isCompleted = completedDaySet.contains(normalizedDay)

                    ZStack {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(backgroundColor(isToday: isToday, isCompleted: isCompleted))
                        Text(day.formatted(.dateTime.day()))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(foregroundColor(isToday: isToday, isCompleted: isCompleted))
                    }
                    .frame(height: 22)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(borderColor(isToday: isToday), lineWidth: isToday ? 1.2 : 0)
                    )
                } else {
                    Color.clear
                        .frame(height: 22)
                }
            }
        }
    }

    private func backgroundColor(isToday: Bool, isCompleted: Bool) -> Color {
        if isToday {
            return UITheme.accent.opacity(isCompleted ? 0.35 : 0.18)
        }
        if isCompleted {
            return UITheme.accent.opacity(0.14)
        }
        return UITheme.controlFill
    }

    private func foregroundColor(isToday: Bool, isCompleted: Bool) -> Color {
        if isToday || isCompleted {
            return .primary
        }
        return .secondary
    }

    private func borderColor(isToday: Bool) -> Color {
        isToday ? UITheme.accent.opacity(0.85) : .clear
    }

    private func buildFullMonthSection(for monthStart: Date) -> MonthSection {
        guard
            let daysRange = calendar.range(of: .day, in: .month, for: monthStart),
            let firstDay = calendar.date(from: calendar.dateComponents([.year, .month], from: monthStart))
        else {
            return MonthSection(monthStart: monthStart, cells: [])
        }

        let monthDays = daysRange.compactMap { day -> Date? in
            calendar.date(byAdding: .day, value: day - 1, to: firstDay)
        }

        let firstWeekday = calendar.component(.weekday, from: firstDay)
        let leadingSlots = (firstWeekday - calendar.firstWeekday + 7) % 7

        var cells = Array<Date?>(repeating: nil, count: leadingSlots)
        cells.append(contentsOf: monthDays)
        let trailingSlots = (7 - (cells.count % 7)) % 7
        cells.append(contentsOf: Array<Date?>(repeating: nil, count: trailingSlots))

        return MonthSection(monthStart: monthStart, cells: cells)
    }
}

private struct MonthSection: Identifiable {
    let monthStart: Date
    let cells: [Date?]

    var id: Date { monthStart }
}

// MARK: - Empty state

private struct WorkoutHistoryEmptyState: View {
    var body: some View {
        VStack(spacing: UITheme.spaceL) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(.tertiary)
                .symbolRenderingMode(.hierarchical)
                .padding(.bottom, UITheme.spaceXS)

            VStack(spacing: UITheme.spaceS) {
                Text("No workouts yet")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)

                Text("Start a New Workout from the Workout tab. Finished workouts show here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, UITheme.spaceXL)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 44)
        .padding(.bottom, 52)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No workouts yet. Start a New Workout from the Workout tab. Finished workouts show here.")
    }
}

// MARK: - Row

private struct WorkoutHistoryRowView: View {
    @AppStorage("settings.units") private var unitsRawValue: String = "kg"
    let session: WorkoutSession

    private var completedAt: Date? {
        session.completedAt
    }

    /// Single-pass row summary. The previous form traversed `session.sessionExercises`
    /// (and the nested `sets` relationship) three separate times per row — once for
    /// exercise count, once for set count, once for volume.
    private var summaryText: String {
        let sessionExercises = session.sessionExercises
        let exerciseCount = sessionExercises.count
        var setCount = 0
        var volumeKg = 0.0
        for sessionExercise in sessionExercises {
            for set in sessionExercise.sets {
                setCount += 1
                volumeKg += WorkoutSetDisplay.volumeKg(
                    set: set,
                    exercise: sessionExercise.exercise
                )
            }
        }
        let exLabel = exerciseCount == 1 ? "1 exercise" : "\(exerciseCount) exercises"
        let setLabel = setCount == 1 ? "1 set" : "\(setCount) sets"
        return "\(exLabel) · \(setLabel) · \(formattedVolume(volumeKg)) \(weightUnitLabel)"
    }

    private var weightUnitLabel: String {
        unitsRawValue == "lb" ? "lb" : "kg"
    }

    private func formattedVolume(_ valueKg: Double) -> String {
        WorkoutSetDisplay.formatVolumeDisplay(
            kg: valueKg,
            weightUnit: unitsRawValue == "lb" ? "lb" : "kg"
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(homeHistoryListTitle(for: session))
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if let completedAt {
                HStack(alignment: .center, spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                    Text(completedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }

            Text(summaryText)
                .font(.caption.weight(.medium))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

// MARK: - Home history title (saved name first, exercise list only as fallback)

/// Title for Home history rows and navigation: `WorkoutSession.name` when set, otherwise derived from exercises.
private func homeHistoryListTitle(for session: WorkoutSession) -> String {
    let saved = (session.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    if !saved.isEmpty {
        return saved
    }
    return homeHistoryDerivedTitleFromExercises(session)
}

private func homeHistoryDerivedTitleFromExercises(_ session: WorkoutSession) -> String {
    let ordered = session.sessionExercises.sorted { $0.exerciseOrder < $1.exerciseOrder }
    guard let firstName = ordered.first?.displayName, !firstName.isEmpty else {
        return "Workout"
    }
    if ordered.count == 1 {
        return firstName
    }
    return "\(firstName) +\(ordered.count - 1)"
}

#Preview {
    NavigationStack {
        HomeView()
    }
    .environmentObject(WorkoutSessionPresentationState())
}
