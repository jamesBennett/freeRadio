import SwiftUI

enum GridTheme {
    static let paper = Color(red: 0.96, green: 0.95, blue: 0.93)
    static let ink = Color(red: 0.08, green: 0.09, blue: 0.09)
    static let navy = Color(red: 0.09, green: 0.23, blue: 0.40)
    static let muted = Color(red: 0.36, green: 0.37, blue: 0.37)
    static let surface = Color.black.opacity(0.045)

    static func display(_ size: CGFloat, relativeTo style: Font.TextStyle = .largeTitle) -> Font {
        .custom("HelveticaNeue-Bold", size: size, relativeTo: style)
    }
}

struct SectionRule: View {
    let title: String
    var count: Int? = nil

    var body: some View {
        HStack(spacing: 12) {
            Text(title).font(.caption.weight(.bold))
            Rectangle().fill(GridTheme.ink.opacity(0.3)).frame(height: 0.5)
            if let count { Text(count.formatted()).font(.caption.monospacedDigit()).foregroundStyle(GridTheme.muted) }
        }
        .foregroundStyle(GridTheme.ink)
        .accessibilityAddTraits(.isHeader)
    }
}

struct StationArtwork: View {
    let url: URL?
    var size: CGFloat = 56

    var body: some View {
        AsyncImage(url: url) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            ZStack {
                GridTheme.surface
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: size * 0.35, weight: .light))
                    .foregroundStyle(GridTheme.navy)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityHidden(true)
    }
}
