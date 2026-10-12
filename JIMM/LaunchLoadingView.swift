//
//  LaunchLoadingView.swift
//  JIMM
//

import SwiftUI

/// Branded cold-start splash (transparent logo + JIMM wordmark).
struct LaunchLoadingView: View {
    private static let logoToWordmarkSpacing: CGFloat = 28
    private static let wordmarkToTaglineSpacing: CGFloat = 14

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: Self.logoToWordmarkSpacing) {
                    JIMMLogoMark(height: 172)

                    VStack(spacing: Self.wordmarkToTaglineSpacing) {
                        JIMMWordmark(fontSize: 38)
                        Text("GYM TRACKER")
                            .font(.system(size: 13, weight: .medium))
                            .tracking(6.5)
                            .foregroundStyle(Color(white: 0.48))
                            .textCase(.uppercase)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, UITheme.spaceXL)
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Logo mark (transparent brand asset)

struct JIMMLogoMark: View {
    var height: CGFloat = 172

    var body: some View {
        Image("JIMMLogo")
            .resizable()
            .interpolation(.none)
            .scaledToFit()
            .frame(height: height)
            .accessibilityLabel("JIMM")
    }
}

// MARK: - Wordmark

struct JIMMWordmark: View {
    var fontSize: CGFloat = 38

    private var accentDotSize: CGFloat { fontSize * 0.17 }

    var body: some View {
        // Overlay keeps the accent dot out of layout width so the tagline
        // centers on the JIMM letters, not the optical shift from the mark.
        Text("JIMM")
            .font(.system(size: fontSize, weight: .heavy))
            .foregroundStyle(.white)
            .overlay(alignment: .topTrailing) {
                Circle()
                    .fill(UITheme.accent)
                    .frame(width: accentDotSize, height: accentDotSize)
                    .offset(x: 4 + accentDotSize * 0.35, y: -fontSize * 0.20)
            }
    }
}

#Preview {
    LaunchLoadingView()
}
