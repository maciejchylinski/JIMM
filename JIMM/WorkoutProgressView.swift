import SwiftUI
import SwiftData

// MARK: - Progress dashboard (completed workouts only)

struct WorkoutProgressView: View {
    @Environment(\.activeWorkoutMiniBarScrollInset) private var activeWorkoutMiniBarScrollInset
    @Query(sort: \WorkoutSession.completedAt, order: .reverse)
    private var sessionsByCompletedAt: [WorkoutSession]
    @AppStorage("settings.units") private var unitsRawValue: String = "kg"

    @State private var selectedMode: ProgressMode = .exercise
    @State private var selectedExerciseID: String?
    @State private var selectedCategoryID: String?
    @State private var selectedRange: ProgressTimeRange = .threeMonths
    @State private var showingExercisePicker = false

    private var weightUnitLabel: String {
        unitsRawValue == "lb" ? "lb" : "kg"
    }

    private var completedSessions: [WorkoutSession] {
        sessionsByCompletedAt.filter { $0.completedAt != nil }
    }

    private var catalog: WorkoutProgressCatalog {
        WorkoutProgressCatalog.build(from: completedSessions)
    }

    private var exerciseOptions: [WorkoutProgressExerciseOption] {
        catalog.exercises
    }

    private var categoryOptions: [WorkoutProgressCategoryOption] {
        catalog.categories
    }

    private var selectedExercise: WorkoutProgressExerciseOption? {
        guard let selectedExerciseID else { return nil }
        return catalog.exercise(for: selectedExerciseID)
    }

    private var selectedCategory: WorkoutProgressCategoryOption? {
        guard let selectedCategoryID else { return nil }
        return catalog.category(for: selectedCategoryID)
    }

    private var activeSessionPoints: [WorkoutProgressPoint] {
        switch selectedMode {
        case .exercise:
            guard let selectedExercise else { return [] }
            return catalog.sessionPoints(
                for: selectedExercise,
                in: completedSessions,
                weightUnit: weightUnitLabel
            )
        case .totalVolume:
            return catalog.totalVolumeSessionPoints(
                in: completedSessions,
                weightUnit: weightUnitLabel
            )
        case .muscleGroup:
            guard let selectedCategory else { return [] }
            return catalog.categoryVolumeSessionPoints(
                for: selectedCategory,
                in: completedSessions,
                weightUnit: weightUnitLabel
            )
        }
    }

    private var rangedPoints: [WorkoutProgressPoint] {
        ProgressTimeRange.filter(
            points: activeSessionPoints,
            range: selectedRange,
            anchorDate: activeSessionPoints.latestPointDate
        )
    }

    private func chartConfig(for points: [WorkoutProgressPoint]) -> ProgressChartConfig {
        ProgressChartConfig.make(
            mode: selectedMode,
            exercise: selectedExercise?.exercise,
            weightUnit: weightUnitLabel,
            points: points
        )
    }

    /// Rebuilds the chart when mode, selection, range, or plotted points change.
    private func chartContentID(
        for points: [WorkoutProgressPoint],
        config: ProgressChartConfig
    ) -> String {
        [
            selectedMode.rawValue,
            selectedExerciseID ?? "",
            selectedCategoryID ?? "",
            selectedRange.rawValue,
            config.cacheKey,
            "\(points.count)",
            points.map(\.id).joined(separator: ",")
        ].joined(separator: "|")
    }

    var body: some View {
        Group {
            if showsGlobalEmptyState {
                WorkoutProgressEmptyState(mode: selectedMode)
            } else {
                dashboardContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(UITheme.appBackground.ignoresSafeArea())
        .navigationTitle("Progress")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            ensureModeSelections()
        }
        .onChange(of: selectedMode) { _, _ in
            ensureModeSelections()
        }
        .onChange(of: completedSessions.count) { _, _ in
            ensureModeSelections()
        }
        .sheet(isPresented: $showingExercisePicker) {
            ProgressExercisePickerSheet(
                options: exerciseOptions,
                selectedID: $selectedExerciseID
            )
        }
    }

    private var showsGlobalEmptyState: Bool {
        switch selectedMode {
        case .exercise:
            return exerciseOptions.isEmpty
        case .totalVolume:
            return catalog.hasStrengthVolumeData == false
        case .muscleGroup:
            return categoryOptions.isEmpty
        }
    }

    private var dashboardContent: some View {
        let points = rangedPoints
        return ScrollView {
            VStack(alignment: .leading, spacing: UITheme.spaceL) {
                modeSelectorRow

                modeSelectorCard

                summaryCardsSection(points: points)

                rangeSelectorSection

                progressChartCard(points: points, chartEmptyMessage: chartEmptyMessage)

                recentSessionsSection(points: points)
            }
            .padding(.horizontal, UITheme.spaceL)
            .padding(.top, UITheme.spaceS)
            .padding(.bottom, UITheme.spaceXL + activeWorkoutMiniBarScrollInset)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Sections

    private var modeSelectorRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: UITheme.spaceS) {
                ForEach(ProgressMode.allCases) { mode in
                    Button {
                        selectedMode = mode
                        ensureModeSelections()
                    } label: {
                        ProgressModeChip(
                            title: mode.title,
                            isSelected: selectedMode == mode
                        )
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                }
            }
        }
    }

    @ViewBuilder
    private var modeSelectorCard: some View {
        switch selectedMode {
        case .exercise:
            exerciseSelectorCard
        case .totalVolume:
            totalVolumeHeaderCard
        case .muscleGroup:
            categorySelectorCard
        }
    }

    @ViewBuilder
    private var exerciseSelectorCard: some View {
        if exerciseOptions.isEmpty {
            EmptyView()
        } else {
            Button {
                showingExercisePicker = true
            } label: {
                exerciseSelectorLabel
            }
            .buttonStyle(.plain)
        }
    }

    private var exerciseSelectorLabel: some View {
        HStack(alignment: .center, spacing: UITheme.spaceM) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Exercise")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(selectedExercise?.name ?? exerciseOptions.first?.name ?? "Exercise")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let category = selectedExercise?.category {
                    Text(category)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .progressCardPadding()
        .background(progressCardBackground)
    }

    @ViewBuilder
    private var categorySelectorCard: some View {
        if categoryOptions.isEmpty {
            EmptyView()
        } else {
            Menu {
                ForEach(categoryOptions) { option in
                    Button {
                        selectedCategoryID = option.id
                    } label: {
                        if option.id == selectedCategoryID {
                            Label(option.name, systemImage: "checkmark")
                        } else {
                            Text(option.name)
                        }
                    }
                }
            } label: {
                categorySelectorLabel
            }
            .buttonStyle(.plain)
        }
    }

    private var categorySelectorLabel: some View {
        HStack(alignment: .center, spacing: UITheme.spaceM) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Category")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(selectedCategory?.name ?? categoryOptions.first?.name ?? "Category")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .progressCardPadding()
        .background(progressCardBackground)
    }

    private var totalVolumeHeaderCard: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Scope")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text("All Workouts")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
            Text("Strength training volume")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .progressCardPadding()
        .background(progressCardBackground)
    }

    private func summaryCardsSection(points: [WorkoutProgressPoint]) -> some View {
        let metrics = summaryMetrics(for: points)
        return VStack(alignment: .leading, spacing: UITheme.spaceS) {
            ProgressSummaryCard(
                title: metrics.hero.title,
                value: metrics.hero.value,
                layout: .hero,
                accentValue: metrics.hero.usesAccent
            )
            HStack(alignment: .top, spacing: UITheme.spaceS) {
                ProgressSummaryCard(
                    title: metrics.secondary.title,
                    value: metrics.secondary.value,
                    layout: .compact
                )
                ProgressSummaryCard(
                    title: metrics.tertiary.title,
                    value: metrics.tertiary.value,
                    layout: .compact
                )
            }
        }
    }

    private struct ProgressSummaryMetrics {
        let hero: ProgressSummaryMetric
        let secondary: ProgressSummaryMetric
        let tertiary: ProgressSummaryMetric
    }

    private struct ProgressSummaryMetric {
        let title: String
        let value: String
        var usesAccent: Bool = false
    }

    private func summaryMetrics(for points: [WorkoutProgressPoint]) -> ProgressSummaryMetrics {
        let sortedByDate = points.sorted { $0.date > $1.date }
        let last = sortedByDate.first
        let empty = WorkoutSetDisplay.emptyPlaceholder
        let sessionCountText = points.isEmpty ? empty : "\(points.count)"

        switch selectedMode {
        case .exercise:
            let best = points.bestPerformance()
            let labels = exerciseSummaryLabels
            return ProgressSummaryMetrics(
                hero: ProgressSummaryMetric(
                    title: labels.best,
                    value: best?.resultText ?? empty,
                    usesAccent: true
                ),
                secondary: ProgressSummaryMetric(
                    title: labels.last,
                    value: last?.resultText ?? empty
                ),
                tertiary: ProgressSummaryMetric(title: "Sessions", value: sessionCountText)
            )
        case .totalVolume:
            let totalKg = points.reduce(0) { $0 + $1.chartValue }
            return ProgressSummaryMetrics(
                hero: ProgressSummaryMetric(
                    title: "Total Volume",
                    value: formatProgressVolumeText(kg: totalKg),
                    usesAccent: true
                ),
                secondary: ProgressSummaryMetric(
                    title: "Last Volume",
                    value: last.map { formatProgressVolumeText(kg: $0.chartValue) } ?? empty
                ),
                tertiary: ProgressSummaryMetric(title: "Workouts", value: sessionCountText)
            )
        case .muscleGroup:
            let totalKg = points.reduce(0) { $0 + $1.chartValue }
            let bestVolume = points.max(by: { $0.chartValue < $1.chartValue })
            return ProgressSummaryMetrics(
                hero: ProgressSummaryMetric(
                    title: "Total Volume",
                    value: formatProgressVolumeText(kg: totalKg),
                    usesAccent: true
                ),
                secondary: ProgressSummaryMetric(
                    title: "Best Volume",
                    value: bestVolume.map { formatProgressVolumeText(kg: $0.chartValue) } ?? empty
                ),
                tertiary: ProgressSummaryMetric(title: "Sessions", value: sessionCountText)
            )
        }
    }

    private func formatProgressVolumeText(kg: Double) -> String {
        guard kg > 0 else { return WorkoutSetDisplay.emptyPlaceholder }
        let display = WeightUnitFormatting.formatVolume(fromStoredKg: kg, unit: weightUnitLabel)
        return "\(display) \(weightUnitLabel)"
    }

    private var exerciseSummaryLabels: (best: String, last: String) {
        switch selectedExercise?.exercise?.loggingType ?? .strength {
        case .strength:
            return ("Best Set", "Last Set")
        case .bodyweight:
            return ("Best Reps", "Last Reps")
        case .duration, .mobility:
            return ("Best Time", "Last Time")
        case .cardio:
            return ("Best Distance", "Last Distance")
        }
    }

    private var chartEmptyMessage: String {
        if !activeSessionPoints.isEmpty, rangedPoints.isEmpty {
            return "No sessions in this range."
        }
        return "Complete more sessions to see a trend."
    }

    private var rangeContextText: String? {
        let allCount = activeSessionPoints.count
        guard allCount > 0 else { return nil }

        let rangedCount = rangedPoints.count
        if rangedCount == 0 {
            return "No sessions in this range"
        }

        if selectedRange == .all {
            return ProgressCopy.sessionCountPhrase(rangedCount, prefix: "Showing")
        }

        if rangedCount == allCount {
            return "All sessions are within this range"
        }

        if rangedCount < allCount {
            return ProgressCopy.filteredSessionPhrase(
                showing: rangedCount,
                total: allCount
            )
        }

        return ProgressCopy.sessionCountPhrase(rangedCount, prefix: "Showing")
    }

    private var rangeSelectorSection: some View {
        VStack(alignment: .leading, spacing: UITheme.spaceXS) {
            rangeSelector
            if let rangeContextText {
                Text(rangeContextText)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var rangeSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: UITheme.spaceS) {
                ForEach(ProgressTimeRange.allCases) { range in
                    Button {
                        selectedRange = range
                    } label: {
                        Text(range.label)
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(ChipStyle(isSelected: selectedRange == range))
                }
            }
        }
    }

    private func progressChartCard(
        points: [WorkoutProgressPoint],
        chartEmptyMessage: String
    ) -> some View {
        let chartPoints = points.sorted { $0.date < $1.date }
        let config = chartConfig(for: chartPoints)
        let samples = chartPoints.map {
            ProgressChartSample(id: $0.id, date: $0.date, value: config.yValue(for: $0))
        }
        let hasChart = samples.count >= 2

        return VStack(alignment: .leading, spacing: UITheme.spaceM) {
            HStack(alignment: .firstTextBaseline, spacing: UITheme.spaceS) {
                Text("Trend")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(config.subtitle)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            if hasChart {
                ProgressSimpleLineChart(samples: samples, config: config)
                    .id(chartContentID(for: chartPoints, config: config))
            } else {
                VStack(spacing: UITheme.spaceS) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.title2.weight(.medium))
                        .foregroundStyle(.tertiary)
                        .symbolRenderingMode(.hierarchical)
                    Text(chartEmptyMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 160)
            }
        }
        .progressCardPadding()
        .background(progressCardBackground)
    }

    private func recentSessionsSection(points: [WorkoutProgressPoint]) -> some View {
        let recent = points.sorted { $0.date > $1.date }

        return VStack(alignment: .leading, spacing: UITheme.spaceM) {
            Text("Recent Sessions")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            if recent.isEmpty {
                Text("No sessions in this range.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .progressCardPadding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(progressCardBackground)
            } else {
                VStack(spacing: UITheme.spaceS) {
                    ForEach(recent) { point in
                        WorkoutProgressRecentSessionRow(point: point)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func ensureModeSelections() {
        switch selectedMode {
        case .exercise:
            ensureSelectedExercise()
        case .muscleGroup:
            ensureSelectedCategory()
        case .totalVolume:
            break
        }
    }

    private func ensureSelectedExercise() {
        guard !exerciseOptions.isEmpty else {
            selectedExerciseID = nil
            return
        }
        if let selectedExerciseID,
           exerciseOptions.contains(where: { $0.id == selectedExerciseID }) {
            return
        }
        selectedExerciseID = exerciseOptions.first?.id
    }

    private func ensureSelectedCategory() {
        guard !categoryOptions.isEmpty else {
            selectedCategoryID = nil
            return
        }
        if let selectedCategoryID,
           categoryOptions.contains(where: { $0.id == selectedCategoryID }) {
            return
        }
        selectedCategoryID = categoryOptions.first?.id
    }

    private var progressCardBackground: some View {
        RoundedRectangle(cornerRadius: UITheme.cornerRadius, style: .continuous)
            .fill(UITheme.cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: UITheme.cornerRadius, style: .continuous)
                    .stroke(UITheme.stroke, lineWidth: 0.7)
            )
    }
}

// MARK: - Components

private enum ProgressMode: String, CaseIterable, Identifiable {
    case totalVolume
    case exercise
    case muscleGroup

    var id: String { rawValue }

    var title: String {
        switch self {
        case .totalVolume: return "Total Volume"
        case .exercise: return "Exercise"
        case .muscleGroup: return "Category"
        }
    }
}

private struct ProgressModeChip: View {
    let title: String
    let isSelected: Bool

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(isSelected ? UITheme.accent : .secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        isSelected
                            ? UITheme.controlFillMuted
                            : UITheme.controlFill.opacity(0.85)
                    )
            )
    }
}

private struct ProgressSummaryCard: View {
    enum Layout {
        case hero
        case compact
    }

    let title: String
    let value: String
    var layout: Layout = .compact
    var accentValue: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: layout == .hero ? UITheme.spaceM : UITheme.spaceS) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .topLeading)

            Text(value)
                .font(valueFont)
                .foregroundStyle(accentValue ? UITheme.accent : .primary)
                .lineLimit(layout == .hero ? 3 : 2)
                .multilineTextAlignment(.leading)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .progressCardPadding()
        .background(
            RoundedRectangle(cornerRadius: UITheme.cornerRadius, style: .continuous)
                .fill(UITheme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: UITheme.cornerRadius, style: .continuous)
                        .stroke(UITheme.stroke, lineWidth: 0.7)
                )
        )
    }

    private var valueFont: Font {
        switch layout {
        case .hero:
            return .title3.weight(.semibold)
        case .compact:
            return .subheadline.weight(.semibold)
        }
    }
}

private struct WorkoutProgressRecentSessionRow: View {
    let point: WorkoutProgressPoint

    var body: some View {
        HStack(alignment: .center, spacing: UITheme.spaceM) {
            VStack(alignment: .leading, spacing: 3) {
                Text(point.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(point.secondaryDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Text(point.resultText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
        .progressCardPadding()
        .background(
            RoundedRectangle(cornerRadius: UITheme.cornerRadius, style: .continuous)
                .fill(UITheme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: UITheme.cornerRadius, style: .continuous)
                        .stroke(UITheme.stroke, lineWidth: 0.7)
                )
        )
    }
}

private struct WorkoutProgressEmptyState: View {
    let mode: ProgressMode

    var body: some View {
        VStack(spacing: UITheme.spaceL) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(.tertiary)
                .symbolRenderingMode(.hierarchical)
                .padding(.bottom, UITheme.spaceXS)

            VStack(spacing: UITheme.spaceS) {
                Text("No progress yet")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, UITheme.spaceL)
    }

    private var message: String {
        switch mode {
        case .exercise:
            return "Finish a workout with logged sets to see exercise progress here."
        case .totalVolume:
            return "Finish workouts with logged strength sets to see total volume here."
        case .muscleGroup:
            return "Finish workouts with strength exercises that have a category to see category progress."
        }
    }
}

private extension View {
    func progressCardPadding() -> some View {
        padding(UITheme.spaceL)
    }
}

// MARK: - Time range

private enum ProgressTimeRange: String, CaseIterable, Identifiable {
    case twoWeeks
    case oneMonth
    case threeMonths
    case sixMonths
    case oneYear
    case all

    var id: String { rawValue }

    var label: String {
        switch self {
        case .twoWeeks: return "2W"
        case .oneMonth: return "1M"
        case .threeMonths: return "3M"
        case .sixMonths: return "6M"
        case .oneYear: return "1Y"
        case .all: return "All"
        }
    }

    /// Filters `points` to those on or after the range start, measured backward from `anchorDate`.
    /// When `anchorDate` is nil (no points), returns all points unchanged. `.all` never filters.
    static func filter(
        points: [WorkoutProgressPoint],
        range: ProgressTimeRange,
        anchorDate: Date?
    ) -> [WorkoutProgressPoint] {
        guard let anchorDate, let start = range.rangeStartDate(anchoredTo: anchorDate) else {
            return points
        }
        return points.filter { $0.date >= start }
    }

    private func rangeStartDate(anchoredTo anchor: Date) -> Date? {
        let calendar = Calendar.current
        switch self {
        case .twoWeeks:
            return calendar.date(byAdding: .day, value: -14, to: anchor)
        case .oneMonth:
            return calendar.date(byAdding: .month, value: -1, to: anchor)
        case .threeMonths:
            return calendar.date(byAdding: .month, value: -3, to: anchor)
        case .sixMonths:
            return calendar.date(byAdding: .month, value: -6, to: anchor)
        case .oneYear:
            return calendar.date(byAdding: .year, value: -1, to: anchor)
        case .all:
            return nil
        }
    }
}

// MARK: - Data

private struct WorkoutProgressExerciseOption: Identifiable {
    let id: String
    let name: String
    let category: String?
    let exercise: Exercise?
}

private struct WorkoutProgressPoint: Identifiable {
    let id: String
    let date: Date
    let resultText: String
    /// Scalar used for ordering (best performance / totals). Not safe for chart axes.
    let chartValue: Double
    let secondaryDetail: String
    // Raw values for clean chart Y mapping (only the relevant ones are non-nil per mode):
    let strengthWeightKg: Double?
    let reps: Int?
    let durationSeconds: Int?
    let distanceMeters: Double?
    let volumeKg: Double?
}

private struct WorkoutProgressCategoryOption: Identifiable {
    let id: String
    let name: String
}

private struct WorkoutProgressCatalog {
    let exercises: [WorkoutProgressExerciseOption]
    let categories: [WorkoutProgressCategoryOption]
    let hasStrengthVolumeData: Bool
    private let optionsByID: [String: WorkoutProgressExerciseOption]
    private let categoriesByID: [String: WorkoutProgressCategoryOption]

    func exercise(for id: String) -> WorkoutProgressExerciseOption? {
        optionsByID[id]
    }

    func category(for id: String) -> WorkoutProgressCategoryOption? {
        categoriesByID[id]
    }

    func totalVolumeSessionPoints(
        in completedSessions: [WorkoutSession],
        weightUnit: String
    ) -> [WorkoutProgressPoint] {
        completedSessions.compactMap { session in
            Self.volumePoint(
                for: session,
                volumeKg: Self.sessionStrengthVolumeKg(in: session),
                weightUnit: weightUnit
            )
        }
        .sorted { $0.date < $1.date }
    }

    func categoryVolumeSessionPoints(
        for category: WorkoutProgressCategoryOption,
        in completedSessions: [WorkoutSession],
        weightUnit: String
    ) -> [WorkoutProgressPoint] {
        completedSessions.compactMap { session in
            let volume = Self.categoryStrengthVolumeKg(in: session, categoryID: category.id)
            return Self.volumePoint(
                for: session,
                volumeKg: volume,
                weightUnit: weightUnit,
                pointIDPrefix: "category|\(category.id)"
            )
        }
        .sorted { $0.date < $1.date }
    }

    private static func volumePoint(
        for session: WorkoutSession,
        volumeKg: (volumeKg: Double, setCount: Int),
        weightUnit: String,
        pointIDPrefix: String = "volume"
    ) -> WorkoutProgressPoint? {
        guard let completedAt = session.completedAt, volumeKg.volumeKg > 0 else { return nil }
        let setLabel = volumeKg.setCount == 1 ? "set" : "sets"
        return WorkoutProgressPoint(
            id: "\(pointIDPrefix)|\(session.persistentModelID)",
            date: completedAt,
            resultText: WorkoutSetDisplay.formatVolumeDisplay(kg: volumeKg.volumeKg, weightUnit: weightUnit),
            chartValue: volumeKg.volumeKg,
            secondaryDetail: "\(volumeKg.setCount) strength \(setLabel)",
            strengthWeightKg: nil,
            reps: nil,
            durationSeconds: nil,
            distanceMeters: nil,
            volumeKg: volumeKg.volumeKg
        )
    }

    private static func sessionStrengthVolumeKg(in session: WorkoutSession) -> (volumeKg: Double, setCount: Int) {
        WorkoutSetLoggingRules.sessionStrengthVolumeKg(in: session)
    }

    private static func categoryStrengthVolumeKg(
        in session: WorkoutSession,
        categoryID: String
    ) -> (volumeKg: Double, setCount: Int) {
        var volumeKg = 0.0
        var setCount = 0
        for sessionExercise in session.sessionExercises {
            guard let exercise = sessionExercise.exercise,
                  categoryKey(for: exercise) == categoryID,
                  WorkoutSetLoggingRules.contributesToVolume(exercise: exercise) else { continue }
            for set in sessionExercise.sets where !set.isPendingSuggestion {
                guard WorkoutSetLoggingRules.isComplete(set: set, loggingType: .strength) else { continue }
                volumeKg += WorkoutSetLoggingRules.volumeKg(set: set, exercise: exercise)
                setCount += 1
            }
        }
        return (volumeKg, setCount)
    }

    private static func categoryKey(for exercise: Exercise) -> String {
        let trimmed = exercise.category.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "General" : trimmed
    }

    func sessionPoints(
        for option: WorkoutProgressExerciseOption,
        in completedSessions: [WorkoutSession],
        weightUnit: String
    ) -> [WorkoutProgressPoint] {
        var points: [WorkoutProgressPoint] = []

        for session in completedSessions {
            guard let completedAt = session.completedAt else { continue }
            guard let match = session.sessionExercises.first(where: {
                Self.groupingKey(for: $0) == option.id
            }) else { continue }

            let loggingType = match.exercise?.loggingType ?? .strength
            let completeSets = match.sets.filter {
                !$0.isPendingSuggestion
                    && WorkoutSetLoggingRules.isComplete(set: $0, loggingType: loggingType)
            }
            guard let best = WorkoutSetLoggingRules.bestCompletedPerformance(
                among: completeSets,
                exercise: option.exercise
            ) else { continue }

            let resultText = WorkoutProgressDisplay.formatExerciseResult(
                set: best,
                exercise: option.exercise,
                weightUnit: weightUnit
            )
            guard resultText != WorkoutSetDisplay.emptyPlaceholder else { continue }

            let setLabel = completeSets.count == 1 ? "set" : "sets"
            let strengthWeightKg: Double? = loggingType == .strength ? best.weight : nil
            let bestReps: Int? = (loggingType == .strength || loggingType == .bodyweight) ? best.reps : nil
            let bestDurationSeconds: Int? = (loggingType == .duration
                                              || loggingType == .mobility
                                              || loggingType == .cardio) ? best.durationSeconds : nil
            let bestDistanceMeters: Double? = loggingType == .cardio ? best.distanceMeters : nil

            points.append(
                WorkoutProgressPoint(
                    id: "exercise|\(option.id)|\(session.persistentModelID)",
                    date: completedAt,
                    resultText: resultText,
                    chartValue: WorkoutSetLoggingRules.progressChartValue(
                        set: best,
                        exercise: option.exercise
                    ),
                    secondaryDetail: "\(completeSets.count) \(setLabel)",
                    strengthWeightKg: strengthWeightKg,
                    reps: bestReps,
                    durationSeconds: bestDurationSeconds,
                    distanceMeters: bestDistanceMeters,
                    volumeKg: nil
                )
            )
        }

        return points.sorted { $0.date < $1.date }
    }

    static func build(from completedSessions: [WorkoutSession]) -> WorkoutProgressCatalog {
        struct MutableOption {
            var name: String
            var category: String?
            var exercise: Exercise?
            var hasData = false
        }

        var options: [String: MutableOption] = [:]
        var categoryNames: Set<String> = []
        var hasStrengthVolumeData = false

        for session in completedSessions {
            let sessionVolume = Self.sessionStrengthVolumeKg(in: session)
            if sessionVolume.volumeKg > 0 {
                hasStrengthVolumeData = true
            }

            for sessionExercise in session.sessionExercises {
                let loggingType = sessionExercise.exercise?.loggingType ?? .strength
                let hasComplete = sessionExercise.sets.contains {
                    !$0.isPendingSuggestion
                        && WorkoutSetLoggingRules.isComplete(set: $0, loggingType: loggingType)
                }
                guard hasComplete else { continue }

                let key = groupingKey(for: sessionExercise)
                var option = options[key] ?? MutableOption(
                    name: sessionExercise.displayName,
                    category: categoryLabel(for: sessionExercise.exercise),
                    exercise: sessionExercise.exercise
                )
                option.hasData = true
                if option.exercise == nil, sessionExercise.exercise != nil {
                    option.exercise = sessionExercise.exercise
                    option.category = categoryLabel(for: sessionExercise.exercise)
                }
                options[key] = option

                if let exercise = sessionExercise.exercise,
                   WorkoutSetLoggingRules.contributesToVolume(exercise: exercise) {
                    let hasStrengthSet = sessionExercise.sets.contains {
                        !$0.isPendingSuggestion
                            && WorkoutSetLoggingRules.isComplete(set: $0, loggingType: .strength)
                    }
                    if hasStrengthSet {
                        categoryNames.insert(categoryKey(for: exercise))
                    }
                }
            }
        }

        let exercises = options.compactMap { key, value -> WorkoutProgressExerciseOption? in
            guard value.hasData else { return nil }
            return WorkoutProgressExerciseOption(
                id: key,
                name: value.name,
                category: value.category,
                exercise: value.exercise
            )
        }
        .sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        let categories = categoryNames.map { name in
            WorkoutProgressCategoryOption(id: name, name: name)
        }
        .sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        return WorkoutProgressCatalog(
            exercises: exercises,
            categories: categories,
            hasStrengthVolumeData: hasStrengthVolumeData,
            optionsByID: Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0) }),
            categoriesByID: Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        )
    }

    init(
        exercises: [WorkoutProgressExerciseOption],
        categories: [WorkoutProgressCategoryOption],
        hasStrengthVolumeData: Bool,
        optionsByID: [String: WorkoutProgressExerciseOption],
        categoriesByID: [String: WorkoutProgressCategoryOption]
    ) {
        self.exercises = exercises
        self.categories = categories
        self.hasStrengthVolumeData = hasStrengthVolumeData
        self.optionsByID = optionsByID
        self.categoriesByID = categoriesByID
    }

    private static func groupingKey(for sessionExercise: WorkoutSessionExercise) -> String {
        if let exercise = sessionExercise.exercise {
            return "exercise:\(exercise.persistentModelID)"
        }
        let trimmed = sessionExercise.displayName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return "custom:\(trimmed)"
    }

    private static func categoryLabel(for exercise: Exercise?) -> String? {
        guard let exercise else { return nil }
        let trimmed = exercise.category.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension Array where Element == WorkoutProgressPoint {
    var latestPointDate: Date? {
        self.map(\.date).max()
    }

    /// `progressChartValue` preserves the same ordering as set performance comparison.
    func bestPerformance() -> WorkoutProgressPoint? {
        self.max(by: { $0.chartValue < $1.chartValue })
    }
}

// MARK: - Progress chart

/// One chart, one series, one Y unit. Drives Y mapping, axis labels, and subtitle.
private enum ProgressChartYKind: Equatable {
    case strengthWeight
    case bodyweightReps
    case durationSeconds
    case cardioDistanceKm
    case cardioDurationSeconds
    case volumeKg

    var cacheKey: String {
        switch self {
        case .strengthWeight: return "strength"
        case .bodyweightReps: return "reps"
        case .durationSeconds: return "duration"
        case .cardioDistanceKm: return "cardioKm"
        case .cardioDurationSeconds: return "cardioTime"
        case .volumeKg: return "volume"
        }
    }
}

private struct ProgressChartConfig {
    let kind: ProgressChartYKind
    let weightUnit: String

    static func make(
        mode: ProgressMode,
        exercise: Exercise?,
        weightUnit: String,
        points: [WorkoutProgressPoint]
    ) -> ProgressChartConfig {
        let kind: ProgressChartYKind
        switch mode {
        case .totalVolume, .muscleGroup:
            kind = .volumeKg
        case .exercise:
            switch exercise?.loggingType ?? .strength {
            case .strength:
                kind = .strengthWeight
            case .bodyweight:
                kind = .bodyweightReps
            case .duration, .mobility:
                kind = .durationSeconds
            case .cardio:
                let hasAnyDistance = points.contains { ($0.distanceMeters ?? 0) > 0 }
                kind = hasAnyDistance ? .cardioDistanceKm : .cardioDurationSeconds
            }
        }
        return ProgressChartConfig(kind: kind, weightUnit: weightUnit)
    }

    var cacheKey: String { "\(kind.cacheKey)|\(weightUnit)" }

    /// "weight · kg", "reps", "time", "distance · km", "volume · kg" — used as chart subtitle.
    var subtitle: String {
        switch kind {
        case .strengthWeight: return "weight · \(weightUnit)"
        case .bodyweightReps: return "reps"
        case .durationSeconds, .cardioDurationSeconds: return "time"
        case .cardioDistanceKm: return "distance · km"
        case .volumeKg: return "volume · \(weightUnit)"
        }
    }

    /// Single source of truth for chart Y values, in display units.
    func yValue(for point: WorkoutProgressPoint) -> Double {
        switch kind {
        case .strengthWeight:
            let kg = point.strengthWeightKg ?? 0
            return WeightUnitFormatting.displayWeight(fromStoredKg: kg, unit: weightUnit)
        case .bodyweightReps:
            return Double(point.reps ?? 0)
        case .durationSeconds, .cardioDurationSeconds:
            return Double(point.durationSeconds ?? 0)
        case .cardioDistanceKm:
            return (point.distanceMeters ?? 0) / 1_000
        case .volumeKg:
            let kg = point.volumeKg ?? 0
            if weightUnit == "lb" {
                return kg * WeightUnitFormatting.lbPerKg
            }
            return kg
        }
    }

    func yAxisLabel(for value: Double) -> String {
        let safe = max(0, value)
        switch kind {
        case .strengthWeight:
            return ProgressChartScale.formatWeightAxisLabel(safe, unit: weightUnit)
        case .bodyweightReps:
            return ProgressNumberFormat.grouped(safe)
        case .durationSeconds, .cardioDurationSeconds:
            return WorkoutDurationFormat.display(seconds: Int(safe.rounded()))
        case .cardioDistanceKm:
            return ProgressNumberFormat.grouped(safe, maxFractionDigits: 2)
        case .volumeKg:
            return ProgressChartScale.formatVolumeAxisLabel(safe, unit: weightUnit)
        }
    }
}

private struct ProgressChartSample: Identifiable {
    let id: String
    let date: Date
    let value: Double
}

// MARK: - Custom line chart (no Swift Charts)

private struct ProgressSimpleLineChart: View {
    let samples: [ProgressChartSample]
    let config: ProgressChartConfig

    private static let plotHeight: CGFloat = 200
    private static let yLabelWidth: CGFloat = 44
    private static let xLabelRowHeight: CGFloat = 22
    private static let gridLineCount = 4
    private static let dotDiameter: CGFloat = 6
    private static let lineWidth: CGFloat = 2
    private static let plotInset: CGFloat = dotDiameter / 2 + lineWidth / 2 + 2
    private static let tightPlotWidth: CGFloat = 240

    private var sortedSamples: [ProgressChartSample] {
        samples.sorted { $0.date < $1.date }
    }

    private var yScale: ProgressChartScale.Result {
        ProgressChartScale.make(
            values: sortedSamples.map(\.value),
            kind: config.kind,
            weightUnit: config.weightUnit,
            tickCount: Self.gridLineCount
        )
    }

    private var yDomain: ClosedRange<Double> {
        yScale.domain
    }

    private var yTicks: [Double] {
        yScale.ticks
    }

    var body: some View {
        VStack(alignment: .leading, spacing: UITheme.spaceXS) {
            HStack(alignment: .top, spacing: UITheme.spaceS) {
                yAxisLabels
                    .frame(width: Self.yLabelWidth, height: Self.plotHeight)

                GeometryReader { geometry in
                    let plotRect = CGRect(
                        x: Self.plotInset,
                        y: Self.plotInset,
                        width: max(0, geometry.size.width - Self.plotInset * 2),
                        height: max(0, geometry.size.height - Self.plotInset * 2)
                    )
                    let plotPoints = plotPoints(in: plotRect)

                    ZStack {
                        gridLines(in: plotRect)
                        if plotPoints.count >= 2 {
                            linePath(plotPoints)
                        }
                        dataPointMarkers(plotPoints)
                    }
                }
                .frame(height: Self.plotHeight)
            }

            xAxisLabels
                .padding(.leading, Self.yLabelWidth + UITheme.spaceS)
                .frame(height: Self.xLabelRowHeight)
        }
        .frame(height: Self.plotHeight + Self.xLabelRowHeight + UITheme.spaceXS)
    }

    private var yAxisLabels: some View {
        GeometryReader { geometry in
            let plotHeight = geometry.size.height - Self.plotInset * 2
            let top = Self.plotInset
            ZStack(alignment: .leading) {
                ForEach(Array(yTicks.enumerated()), id: \.offset) { index, tick in
                    let fraction = yTicks.count > 1
                        ? Double(index) / Double(yTicks.count - 1)
                        : 0
                    let y = top + plotHeight * (1 - fraction)
                    Text(config.yAxisLabel(for: tick))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .position(x: Self.yLabelWidth * 0.5, y: y)
                }
            }
        }
    }

    private var xAxisLabels: some View {
        GeometryReader { geometry in
            let showMiddle = sortedSamples.count >= 3 && geometry.size.width >= Self.tightPlotWidth
            let first = sortedSamples.first?.date
            let last = sortedSamples.last?.date
            let middle = showMiddle ? sortedSamples[sortedSamples.count / 2].date : nil

            HStack {
                if let first {
                    Text(first.formatted(.dateTime.month(.abbreviated).day()))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: UITheme.spaceS)
                if let middle {
                    Text(middle.formatted(.dateTime.month(.abbreviated).day()))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: UITheme.spaceS)
                }
                if let last {
                    Text(last.formatted(.dateTime.month(.abbreviated).day()))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private func gridLines(in plotRect: CGRect) -> some View {
        let count = yTicks.count
        return ZStack {
            ForEach(0 ..< count, id: \.self) { index in
                let fraction = count > 1 ? Double(index) / Double(count - 1) : 0
                let y = plotRect.minY + plotRect.height * (1 - fraction)
                Path { path in
                    path.move(to: CGPoint(x: plotRect.minX, y: y))
                    path.addLine(to: CGPoint(x: plotRect.maxX, y: y))
                }
                .stroke(UITheme.stroke.opacity(0.45), lineWidth: 0.5)
            }
        }
    }

    private func linePath(_ points: [CGPoint]) -> some View {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: first)
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
        }
        .stroke(
            UITheme.accent,
            style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round, lineJoin: .round)
        )
    }

    private func dataPointMarkers(_ points: [CGPoint]) -> some View {
        ZStack {
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                Circle()
                    .fill(UITheme.accent)
                    .overlay {
                        Circle()
                            .strokeBorder(Color(uiColor: .systemBackground).opacity(0.85), lineWidth: 1)
                    }
                    .frame(width: Self.dotDiameter, height: Self.dotDiameter)
                    .position(point)
            }
        }
    }

    private func plotPoints(in plotRect: CGRect) -> [CGPoint] {
        guard !sortedSamples.isEmpty, plotRect.width > 0, plotRect.height > 0 else { return [] }

        let domain = yDomain
        let ySpan = domain.upperBound - domain.lowerBound
        let dates = sortedSamples.map(\.date)
        let minDate = dates.min() ?? Date()
        let maxDate = dates.max() ?? Date()
        let dateSpan = maxDate.timeIntervalSince(minDate)
        let useIndexSpacing = dateSpan <= 0

        return sortedSamples.enumerated().map { index, sample in
            let xFraction: Double
            if sortedSamples.count == 1 {
                xFraction = 0.5
            } else if useIndexSpacing {
                let count = sortedSamples.count - 1
                xFraction = Double(index) / Double(count)
            } else {
                xFraction = sample.date.timeIntervalSince(minDate) / dateSpan
            }

            let yFraction: Double
            if ySpan <= 0 {
                yFraction = 0.5
            } else {
                yFraction = (sample.value - domain.lowerBound) / ySpan
            }

            return CGPoint(
                x: plotRect.minX + plotRect.width * xFraction,
                y: plotRect.maxY - plotRect.height * yFraction
            )
        }
    }
}

// MARK: - Progress copy & number formatting

private enum ProgressCopy {
    static func sessionCountPhrase(_ count: Int, prefix: String) -> String {
        count == 1 ? "\(prefix) 1 session" : "\(prefix) \(count) sessions"
    }

    static func filteredSessionPhrase(showing: Int, total: Int) -> String {
        let showingPart = showing == 1 ? "1 session" : "\(showing) sessions"
        let totalPart = total == 1 ? "1 session" : "\(total) sessions"
        return "Showing \(showingPart) of \(totalPart)"
    }
}

private enum ProgressChartScale {
    struct Result {
        let domain: ClosedRange<Double>
        let ticks: [Double]
    }

    static func make(
        values: [Double],
        kind: ProgressChartYKind,
        weightUnit: String,
        tickCount: Int
    ) -> Result {
        guard let minValue = values.min(), let maxValue = values.max() else {
            return Result(domain: 0 ... 1, ticks: [0, 1])
        }

        let rawSpan = max(maxValue - minValue, 0)
        let stepHint = niceStep(for: max(rawSpan, max(maxValue, 1)), kind: kind, weightUnit: weightUnit)
        let padding = rawSpan > 0 ? max(rawSpan * 0.12, stepHint * 0.5) : stepHint
        let paddedMin = max(0, minValue - padding)
        let paddedMax = maxValue + padding

        let step = niceStep(for: paddedMax - paddedMin, kind: kind, weightUnit: weightUnit)
        let domainMin = floor(paddedMin / step) * step
        let domainMax = max(domainMin + step, ceil(paddedMax / step) * step)

        var ticks: [Double] = []
        var tick = domainMin
        while tick <= domainMax + 0.000_1 {
            ticks.append(tick)
            tick += step
        }

        if ticks.count > tickCount, tickCount > 1 {
            ticks = (0 ..< tickCount).map { index in
                let position = Double(index) / Double(tickCount - 1)
                let rawIndex = Int(round(position * Double(ticks.count - 1)))
                return ticks[min(max(rawIndex, 0), ticks.count - 1)]
            }
        } else if ticks.count < tickCount, tickCount > 1 {
            ticks = (0 ..< tickCount).map { index in
                domainMin + (domainMax - domainMin) * Double(index) / Double(tickCount - 1)
            }
        }

        let lower = ticks.first ?? domainMin
        let upper = ticks.last ?? domainMax
        return Result(domain: lower ... upper, ticks: ticks)
    }

    static func formatWeightAxisLabel(_ value: Double, unit: String) -> String {
        if unit == "kg", value.truncatingRemainder(dividingBy: 1) != 0 {
            return String(format: "%.1f", value)
        }
        return ProgressNumberFormat.grouped(value)
    }

    static func formatVolumeAxisLabel(_ value: Double, unit: String) -> String {
        if value >= 10_000 {
            return ProgressNumberFormat.grouped(value / 1_000) + "k"
        }
        if unit == "kg", value < 1_000, value.truncatingRemainder(dividingBy: 1) != 0 {
            return String(format: "%.1f", value)
        }
        return ProgressNumberFormat.grouped(value)
    }

    private static func niceStep(for span: Double, kind: ProgressChartYKind, weightUnit: String) -> Double {
        switch kind {
        case .strengthWeight:
            return weightStep(for: span, unit: weightUnit)
        case .volumeKg:
            return volumeStep(for: span, unit: weightUnit)
        case .bodyweightReps:
            return repStep(for: span)
        case .cardioDistanceKm:
            return distanceKmStep(for: span)
        case .durationSeconds, .cardioDurationSeconds:
            return durationStep(for: span)
        }
    }

    private static func weightStep(for span: Double, unit: String) -> Double {
        if unit == "lb" {
            if span <= 20 { return 5 }
            if span <= 50 { return 10 }
            if span <= 120 { return 20 }
            return 50
        }
        if span <= 15 { return 2.5 }
        if span <= 35 { return 5 }
        if span <= 75 { return 10 }
        return 20
    }

    private static func volumeStep(for span: Double, unit: String) -> Double {
        if unit == "lb" {
            if span <= 500 { return 100 }
            if span <= 2_500 { return 500 }
            if span <= 10_000 { return 1_000 }
            return 5_000
        }
        if span <= 250 { return 50 }
        if span <= 1_000 { return 100 }
        if span <= 5_000 { return 500 }
        return 1_000
    }

    private static func repStep(for span: Double) -> Double {
        if span <= 10 { return 2 }
        if span <= 25 { return 5 }
        if span <= 60 { return 10 }
        return 20
    }

    private static func distanceKmStep(for span: Double) -> Double {
        if span <= 2 { return 0.5 }
        if span <= 8 { return 1 }
        if span <= 20 { return 2 }
        return 5
    }

    private static func durationStep(for span: Double) -> Double {
        if span <= 120 { return 30 }
        if span <= 600 { return 60 }
        if span <= 1_800 { return 300 }
        return 600
    }
}

private enum ProgressNumberFormat {
    private static let groupedFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 0
        formatter.groupingSeparator = " "
        formatter.usesGroupingSeparator = true
        return formatter
    }()

    static func grouped(_ value: Double, maxFractionDigits: Int? = nil) -> String {
        if let maxFractionDigits {
            groupedFormatter.maximumFractionDigits = maxFractionDigits
        } else if value.truncatingRemainder(dividingBy: 1) == 0 {
            groupedFormatter.maximumFractionDigits = 0
        } else {
            groupedFormatter.maximumFractionDigits = 1
        }
        return groupedFormatter.string(from: NSNumber(value: value))
            ?? String(format: "%g", value)
    }

    static func chartAxis(_ value: Double) -> String {
        let absValue = abs(value)
        if absValue >= 10_000 {
            let scaled = value / 1_000
            return grouped(scaled) + "k"
        }
        if absValue >= 1_000 {
            return grouped(value)
        }
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", value)
        }
        return grouped(value)
    }
}

// MARK: - Exercise picker sheet

private struct ProgressExercisePickerSheet: View {
    let options: [WorkoutProgressExerciseOption]
    @Binding var selectedID: String?
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filtered: [WorkoutProgressExerciseOption] {
        guard !searchText.isEmpty else { return options }
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        return options.filter {
            $0.name.lowercased().contains(q)
            || ($0.category?.lowercased().contains(q) == true)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filtered) { option in
                    Button {
                        selectedID = option.id
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.name)
                                    .foregroundStyle(.primary)
                                if let cat = option.category {
                                    Text(cat)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 0)
                            if option.id == selectedID {
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(UITheme.accent)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.plain)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search exercises")
            .navigationTitle("Select Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Progress display formatting

private enum WorkoutProgressDisplay {
    static func formatExerciseResult(
        set: WorkoutSet,
        exercise: Exercise?,
        weightUnit: String
    ) -> String {
        let loggingType = exercise?.loggingType ?? .strength
        switch loggingType {
        case .bodyweight:
            guard set.reps > 0 else { return WorkoutSetDisplay.emptyPlaceholder }
            return "\(set.reps) reps"
        case .duration, .mobility:
            guard (set.durationSeconds ?? 0) > 0 else { return WorkoutSetDisplay.emptyPlaceholder }
            return WorkoutDurationFormat.display(seconds: set.durationSeconds ?? 0)
        case .cardio:
            return WorkoutSetDisplay.formatCompactResult(
                set: set,
                exercise: exercise,
                weightUnit: weightUnit
            )
        case .strength:
            guard set.reps > 0, set.weight > 0 else { return WorkoutSetDisplay.emptyPlaceholder }
            let weightText = WeightUnitFormatting.formatWeight(fromStoredKg: set.weight, unit: weightUnit)
            return "\(weightText) \(weightUnit) × \(set.reps) reps"
        }
    }
}
