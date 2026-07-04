import SwiftUI

/// Layout constants for the global active-workout mini card (`ContentView.safeAreaInset`).
enum ActiveWorkoutMiniBarLayout {
    static let tabBarClearance: CGFloat = 49
    /// Card row (title + metrics); matches `ActiveWorkoutMiniCard` vertical padding 13×2 + content.
    private static let cardContentHeight: CGFloat = 58
    private static let cardVerticalPadding: CGFloat = 26
    private static let insetTopPadding: CGFloat = UITheme.spaceS
    /// Gap below the last scroll row; tab bar clearance is not included (handled by the tab bar safe area).
    private static let scrollBreathingRoom: CGFloat = UITheme.spaceM

    /// Extra scroll/list bottom inset when the mini card is shown (conservative, avoids double-counting tab bar).
    static var scrollContentInset: CGFloat {
        cardContentHeight + cardVerticalPadding + insetTopPadding + scrollBreathingRoom
    }
}

private struct ActiveWorkoutMiniBarScrollInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    /// Non-zero when the tab-level active workout mini card may cover scroll content.
    var activeWorkoutMiniBarScrollInset: CGFloat {
        get { self[ActiveWorkoutMiniBarScrollInsetKey.self] }
        set { self[ActiveWorkoutMiniBarScrollInsetKey.self] = newValue }
    }
}

enum UITheme {
    static let spaceXS: CGFloat = 4
    static let spaceS: CGFloat = 8
    static let spaceM: CGFloat = 12
    static let spaceL: CGFloat = 16
    static let spaceXL: CGFloat = 24
    static let cornerRadiusSmall: CGFloat = 10
    static let cornerRadius: CGFloat = 14
    static let cornerRadiusLarge: CGFloat = 18
    /// Rounded “main chrome” at the bottom of the app (tab bar styling token + active workout accessory).
    static let mainBottomBarChromeCornerRadius: CGFloat = 22
    /// Content row height inside that chrome (tab-bar–like tap target).
    static let mainBottomBarChromeMinHeight: CGFloat = 50
    /// Hairline stroke on main bottom chrome (tab bar / workout accessory).
    static let mainBottomBarChromeStrokeOpacity: Double = 0.38
    static let tapTargetMinHeight: CGFloat = 44
    static let actionVerticalPadding: CGFloat = 13
    static let iconSizeS: CGFloat = 14
    static let iconSizeM: CGFloat = 16
    static let accent = Color(uiColor: .systemOrange)
    static let appBackground = Color(
        uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 0.01, green: 0.01, blue: 0.01, alpha: 1)
                : UIColor.systemGroupedBackground
        }
    )
    static let cardBackground = Color(
        uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 0.09, green: 0.09, blue: 0.10, alpha: 1)
                : UIColor.secondarySystemGroupedBackground
        }
    )
    static let cardBackgroundElevated = Color(
        uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 0.12, green: 0.12, blue: 0.13, alpha: 1)
                : UIColor.tertiarySystemGroupedBackground
        }
    )
    static let stroke = Color(
        uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(white: 1, alpha: 0.12)
                : UIColor.separator.withAlphaComponent(0.32)
        }
    )
    static let controlFill = Color(
        uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 0.16, green: 0.16, blue: 0.17, alpha: 1)
                : UIColor.secondarySystemFill
        }
    )
    static let controlFillMuted = Color(
        uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 0.13, green: 0.13, blue: 0.14, alpha: 1)
                : UIColor.tertiarySystemFill
        }
    )
}

struct CardSurfaceModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(UITheme.spaceL)
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

struct AppRowModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.vertical, UITheme.spaceS)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
    }
}

struct PrimaryBottomButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(minHeight: UITheme.tapTargetMinHeight)
            .padding(.vertical, UITheme.actionVerticalPadding)
            .background(
                RoundedRectangle(cornerRadius: UITheme.cornerRadius, style: .continuous)
                    .fill(UITheme.accent.opacity(configuration.isPressed ? 0.8 : 1))
            )
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: UITheme.tapTargetMinHeight)
            .padding(.vertical, UITheme.actionVerticalPadding)
            .background(
                RoundedRectangle(cornerRadius: UITheme.cornerRadius, style: .continuous)
                    .fill(UITheme.controlFill.opacity(configuration.isPressed ? 0.8 : 1))
            )
    }
}

struct AccentPlainButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(UITheme.accent.opacity(configuration.isPressed ? 0.8 : 1))
    }
}

struct ChipStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
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
                    .opacity(configuration.isPressed ? 0.8 : 1)
            )
    }
}

extension View {
    func cardSurface() -> some View {
        modifier(CardSurfaceModifier())
    }

    func appRowStyle() -> some View {
        modifier(AppRowModifier())
    }
}
