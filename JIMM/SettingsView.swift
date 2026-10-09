import SwiftUI

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
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
