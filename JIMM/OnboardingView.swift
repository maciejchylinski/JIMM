//
//  OnboardingView.swift
//  JIMM
//

import SwiftUI

/// First-launch product tour; completion is stored via `onboarding.hasCompleted` in the app root.
struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    @State private var currentPage = 0

    private enum MockupKind {
        case trainFast
        case logSets
        case restTimer
        case progress
    }

    private struct Page {
        let title: String
        let subtitle: String
        let mockup: MockupKind
    }

    private let pages: [Page] = [
        Page(
            title: "Train fast",
            subtitle: "Start a workout, repeat previous sessions, and keep logging simple.",
            mockup: .trainFast
        ),
        Page(
            title: "Log every set",
            subtitle: "Track weight, reps, time, distance, and rest without leaving the workout.",
            mockup: .logSets
        ),
        Page(
            title: "Follow your rest",
            subtitle: "Use rest timers, Lock Screen, and Dynamic Island during training.",
            mockup: .restTimer
        ),
        Page(
            title: "Track progress",
            subtitle: "See workout history, PRs, and exercise progress over time.",
            mockup: .progress
        ),
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $currentPage) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                    pageContent(page)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            bottomBar
        }
        .background(UITheme.appBackground.ignoresSafeArea())
        .tint(UITheme.accent)
        .overlay(alignment: .topTrailing) {
            Button("Skip") {
                completeOnboarding()
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, UITheme.spaceL)
            .padding(.top, UITheme.spaceM)
        }
    }

    @ViewBuilder
    private var bottomBar: some View {
        VStack(spacing: UITheme.spaceM) {
            if currentPage == pages.count - 1 {
                Button("Get Started") {
                    completeOnboarding()
                }
                .buttonStyle(PrimaryBottomButtonStyle())
            } else {
                Color.clear
                    .frame(minHeight: UITheme.tapTargetMinHeight + UITheme.actionVerticalPadding * 2)
            }
        }
        .padding(.horizontal, UITheme.spaceL)
        .padding(.bottom, UITheme.spaceXL)
        .animation(.easeInOut(duration: 0.2), value: currentPage)
    }

    private func completeOnboarding() {
        hasCompletedOnboarding = true
    }

    private func pageContent(_ page: Page) -> some View {
        VStack(spacing: UITheme.spaceL) {
            Spacer(minLength: UITheme.spaceXL)

            OnboardingPreviewFrame {
                mockup(for: page.mockup)
            }
            .padding(.horizontal, UITheme.spaceL)

            VStack(spacing: UITheme.spaceM) {
                Text(page.title)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)

                Text(page.subtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, UITheme.spaceXL)

            Spacer(minLength: UITheme.spaceL)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func mockup(for kind: MockupKind) -> some View {
        switch kind {
        case .trainFast:
            TrainFastOnboardingMockup()
        case .logSets:
            LogSetsOnboardingMockup()
        case .restTimer:
            RestTimerOnboardingMockup()
        case .progress:
            ProgressOnboardingMockup()
        }
    }
}

// MARK: - Preview frame

private struct OnboardingPreviewFrame<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(UITheme.spaceM)
            .frame(height: 212)
            .background(
                RoundedRectangle(cornerRadius: UITheme.cornerRadiusLarge, style: .continuous)
                    .fill(UITheme.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: UITheme.cornerRadiusLarge, style: .continuous)
                            .stroke(UITheme.stroke, lineWidth: 0.7)
                    )
            )
    }
}

// MARK: - Mockups

private struct TrainFastOnboardingMockup: View {
    var body: some View {
        VStack(alignment: .leading, spacing: UITheme.spaceS) {
            mockRow(title: "New Workout", subtitle: "Start from scratch") {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(UITheme.accent)
            }
            mockRow(title: "Repeat Workout", subtitle: "Start from a finished workout") {
                Image(systemName: "arrow.clockwise")
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: UITheme.spaceS) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(UITheme.controlFillMuted)
                    .frame(width: 52, height: 6)
                Text("Push Day · Yesterday")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 0)
            }
            .padding(.top, UITheme.spaceXS)
        }
    }

    private func mockRow<Trailing: View>(
        title: String,
        subtitle: String,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) -> some View {
        HStack(alignment: .center, spacing: UITheme.spaceM) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            trailing()
                .font(.system(size: 18, weight: .semibold))
        }
        .padding(.horizontal, UITheme.spaceM)
        .padding(.vertical, UITheme.spaceS)
        .background(
            RoundedRectangle(cornerRadius: UITheme.cornerRadiusSmall, style: .continuous)
                .fill(UITheme.controlFillMuted)
        )
    }
}

private struct LogSetsOnboardingMockup: View {
    var body: some View {
        VStack(alignment: .leading, spacing: UITheme.spaceS) {
            Text("Bench Press")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.4)

            setRow(label: "1", fields: ["80", "×", "8"], accent: false)
            setRow(label: "2", fields: ["82.5", "×", "6"], accent: true)

            Divider().opacity(0.35)

            Text("Rowing Machine")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)

            HStack(spacing: UITheme.spaceS) {
                fieldChip("12:30")
                Text("·")
                    .foregroundStyle(.tertiary)
                fieldChip("2.1 km")
            }
        }
    }

    private func setRow(label: String, fields: [String], accent: Bool) -> some View {
        HStack(spacing: UITheme.spaceS) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 16, alignment: .leading)
            ForEach(fields, id: \.self) { part in
                if part == "×" {
                    Text(part)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                } else {
                    fieldChip(part, highlighted: accent && part != "×")
                }
            }
            Spacer(minLength: 0)
            if accent {
                Text("PR")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(UITheme.accent)
            }
        }
    }

    private func fieldChip(_ text: String, highlighted: Bool = false) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(highlighted ? UITheme.accent : .primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(highlighted ? UITheme.accent.opacity(0.15) : UITheme.controlFillMuted)
            )
    }
}

private struct RestTimerOnboardingMockup: View {
    var body: some View {
        VStack(spacing: UITheme.spaceM) {
            Capsule()
                .fill(UITheme.controlFill)
                .frame(width: 120, height: 28)
                .overlay {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(UITheme.accent)
                            .frame(width: 8, height: 8)
                        Text("1:30")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("Rest")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)

            Text("1:30")
                .font(.system(size: 44, weight: .semibold, design: .rounded))
                .foregroundStyle(UITheme.accent)
                .monospacedDigit()

            HStack(spacing: UITheme.spaceM) {
                timerChip("Lock Screen", systemImage: "lock.fill")
                timerChip("Dynamic Island", systemImage: "platter.filled.top.and.arrow.up.iphone")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func timerChip(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.caption2.weight(.semibold))
            Text(title)
                .font(.caption2.weight(.medium))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(UITheme.controlFillMuted)
        )
    }
}

private struct ProgressOnboardingMockup: View {
    var body: some View {
        VStack(alignment: .leading, spacing: UITheme.spaceS) {
            HStack {
                Text("Bench Press")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                Text("PR 85 × 5")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(UITheme.accent)
            }

            chartPreview
                .frame(height: 88)

            HStack(spacing: UITheme.spaceM) {
                legendDot(label: "Volume", color: UITheme.accent.opacity(0.5))
                legendDot(label: "Best set", color: UITheme.accent)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private var chartPreview: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let points: [CGPoint] = [
                CGPoint(x: 0, y: h * 0.72),
                CGPoint(x: w * 0.22, y: h * 0.58),
                CGPoint(x: w * 0.45, y: h * 0.48),
                CGPoint(x: w * 0.68, y: h * 0.32),
                CGPoint(x: w, y: h * 0.22),
            ]

            ZStack {
                RoundedRectangle(cornerRadius: UITheme.cornerRadiusSmall, style: .continuous)
                    .fill(UITheme.controlFillMuted)

                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    for point in points.dropFirst() {
                        path.addLine(to: point)
                    }
                }
                .stroke(UITheme.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                if let last = points.last {
                    Circle()
                        .fill(UITheme.accent)
                        .frame(width: 8, height: 8)
                        .position(last)
                }
            }
        }
    }

    private func legendDot(label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
        }
    }
}

#Preview {
    OnboardingView(hasCompletedOnboarding: .constant(false))
}
