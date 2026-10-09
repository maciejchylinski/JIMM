import SwiftUI
import UIKit

// MARK: - Share sticker content

struct WorkoutShareStickerContent: Equatable {
    let workoutTitle: String
    let finishedDateText: String
    let durationText: String
    let volumeDisplay: String
    let volumeUnit: String
    let exerciseCount: Int
}

// MARK: - Transparent overlay sticker (export only)

struct WorkoutShareStickerView: View {
    let content: WorkoutShareStickerContent

    private static let accent = UITheme.accent
    private static let statChipFill = Color.white.opacity(0.11)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            titleBlock
            heroVolumeBlock
            secondaryStatsRow
            signatureLabel
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 32)
        .background(Color.clear)
    }

    // MARK: Header

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(content.workoutTitle)
                .font(.system(size: 32, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Text(content.finishedDateText)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.72))
        }
    }

    // MARK: Hero stat

    private var heroVolumeBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(content.volumeDisplay)
                    .font(.system(size: 54, weight: .bold, design: .rounded))
                    .foregroundStyle(Self.accent)
                    .minimumScaleFactor(0.75)
                    .lineLimit(1)
                Text(content.volumeUnit)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.92))
            }

            Text("TOTAL VOLUME")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white.opacity(0.62))
                .tracking(1.1)
        }
        .padding(.top, 28)
    }

    // MARK: Secondary stats

    private var secondaryStatsRow: some View {
        HStack(alignment: .top, spacing: 16) {
            overlayStatGroup(
                value: content.durationText,
                label: "DURATION"
            )
            overlayStatGroup(
                value: "\(content.exerciseCount)",
                label: content.exerciseCount == 1 ? "EXERCISE" : "EXERCISES"
            )
        }
        .padding(.top, 26)
    }

    private func overlayStatGroup(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.8)
                .lineLimit(1)
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white.opacity(0.6))
                .tracking(0.9)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Self.statChipFill)
        )
    }

    // MARK: Signature

    private var signatureLabel: some View {
        Text("JIMM")
            .font(.caption2.weight(.medium))
            .foregroundStyle(.white.opacity(0.34))
            .padding(.top, 22)
    }
}

// MARK: - PNG export

enum WorkoutShareStickerExporter {
    private static let renderWidth: CGFloat = 360

    @MainActor
    static func temporaryPNGFileURL(from content: WorkoutShareStickerContent) -> URL? {
        let sticker = WorkoutShareStickerView(content: content)
            .frame(width: renderWidth, alignment: .leading)

        let renderer = ImageRenderer(content: sticker)
        renderer.isOpaque = false
        renderer.scale = 3

        guard let cgImage = renderer.cgImage else { return nil }
        guard let pngData = UIImage(cgImage: cgImage).pngData() else { return nil }

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("workout-share-\(UUID().uuidString).png", isDirectory: false)
        do {
            try pngData.write(to: fileURL, options: .atomic)
            return fileURL
        } catch {
            return nil
        }
    }
}

// MARK: - Native share sheet

struct WorkoutShareSheetItem: Identifiable {
    let id = UUID()
    let fileURL: URL
}

struct WorkoutShareSheet: UIViewControllerRepresentable {
    let fileURL: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview("Share sticker") {
    ZStack {
        LinearGradient(
            colors: [Color(red: 0.15, green: 0.2, blue: 0.35), Color(red: 0.45, green: 0.28, blue: 0.22)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        WorkoutShareStickerView(
            content: WorkoutShareStickerContent(
                workoutTitle: "PUSH A",
                finishedDateText: "May 15, 2026",
                durationText: "1 h 12 min",
                volumeDisplay: "12,450",
                volumeUnit: "kg",
                exerciseCount: 6
            )
        )
    }
    .ignoresSafeArea()
}
