import SwiftUI

struct BannerView: View {
    let channel: Channel?
    let store: GuideStore
    let isPaused: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let program = channel.map { store.program(for: $0, at: context.date) }

            HStack(spacing: 22) {
                Text(channel.map { "\($0.num)" } ?? "--")
                    .font(.bw(62, .black))
                    .foregroundStyle(BW.yellow)
                    .frame(minWidth: 92, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text(channel?.name.uppercased() ?? "BACKWHENTV")
                        .font(.bw(19, .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(program?.title.uppercased() ?? "NO SIGNAL")
                        .font(.bw(30, .black))
                        .foregroundStyle(BW.yellow)
                        .lineLimit(1)
                    if isPaused {
                        Text("PAUSED")
                            .font(.bw(16, .black))
                            .foregroundStyle(BW.orange)
                    } else if let next = program?.next, !next.isEmpty {
                        Text("NEXT: \(next.uppercased())")
                            .font(.bw(17, .regular))
                            .foregroundStyle(BW.ice)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 20)

                VStack(alignment: .trailing, spacing: 3) {
                    Text(BW.time(context.date))
                        .font(.bw(27, .black))
                        .foregroundStyle(BW.orange)
                    Text("BACKWHENTV")
                        .font(.bw(12, .black))
                        .foregroundStyle(BW.ice.opacity(0.55))
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BW.panel.opacity(0.95))
            .overlay(Rectangle().stroke(BW.orange, lineWidth: 3))
        }
        .padding(.horizontal, 54)
        .padding(.bottom, 44)
    }
}

struct LoadingOverlay: View {
    var body: some View {
        VStack(spacing: 0) {
            ColorBars()
            Text("LOADING CHANNEL...")
                .font(.bw(25, .black))
                .foregroundStyle(.white)
                .padding(.horizontal, 38)
                .padding(.vertical, 16)
        }
        .background(Color.black.opacity(0.86))
        .overlay(Rectangle().stroke(BW.orange, lineWidth: 3))
    }
}

struct NoSignalOverlay: View {
    let channel: Channel?

    var body: some View {
        VStack(spacing: 16) {
            Text("NO SIGNAL")
                .font(.bw(88, .black))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.8), radius: 0, x: 4, y: 4)
            if let channel {
                Text("CH \(channel.num)  \(channel.name.uppercased())")
                    .font(.bw(24, .bold))
                    .foregroundStyle(BW.orange)
            }
        }
        .padding(.horizontal, 70)
        .padding(.vertical, 44)
        .background(Color.black.opacity(0.55))
    }
}
