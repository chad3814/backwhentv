import SwiftUI

enum BW {
    static let blue = Color(red: 0.071, green: 0.188, blue: 0.722)      // #1230b8
    static let panel = Color(red: 0.043, green: 0.059, blue: 0.290)     // #0b0f4a
    static let yellow = Color(red: 1.0, green: 0.824, blue: 0.122)      // #ffd21f
    static let orange = Color(red: 1.0, green: 0.604, blue: 0.122)      // #ff9a1f
    static let row = Color(red: 0.153, green: 0.259, blue: 0.839)       // #2742d6
    static let ice = Color(red: 0.722, green: 0.776, blue: 1.0)         // #b8c6ff
    static let navy = Color(red: 0.043, green: 0.110, blue: 0.420)
    static let ink = Color(red: 0.067, green: 0.067, blue: 0.067)
    static let alert = Color(red: 1.0, green: 0.42, blue: 0.42)

    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mma"
        return formatter
    }()

    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE M/d"
        return formatter
    }()

    static func time(_ date: Date) -> String {
        timeFormatter.string(from: date).uppercased()
    }

    static func day(_ date: Date) -> String {
        dayFormatter.string(from: date).uppercased()
    }
}

extension Font {
    /// The web player uses Roboto Condensed; the system's condensed face gets
    /// very close without shipping a font file.
    static func bw(_ size: CGFloat, _ weight: Weight = .bold) -> Font {
        .system(size: size, weight: weight).width(.condensed)
    }
}

struct ColorBars: View {
    private let colors: [Color] = [
        Color(white: 0.78),
        Color(red: 0.75, green: 0.75, blue: 0.0),
        Color(red: 0.0, green: 0.75, blue: 0.75),
        Color(red: 0.0, green: 0.75, blue: 0.0),
        Color(red: 0.75, green: 0.0, blue: 0.75),
        Color(red: 0.75, green: 0.0, blue: 0.0),
        Color(red: 0.0, green: 0.0, blue: 0.75)
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
                Rectangle().fill(color).frame(width: 28, height: 16)
            }
        }
    }
}

struct KeyCap: View {
    let key: String
    let label: String

    var body: some View {
        HStack(spacing: 8) {
            Text(key)
                .font(.bw(16, .black))
                .foregroundStyle(BW.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(BW.yellow)
                .clipShape(RoundedRectangle(cornerRadius: 3))
            Text(label)
                .font(.bw(16, .bold))
                .foregroundStyle(BW.ice)
        }
    }
}
