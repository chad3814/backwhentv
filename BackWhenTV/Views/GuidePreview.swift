import SwiftUI

/// The top quarter of the guide: the channel the focus is on, what is playing
/// right now, how far through it is, and what comes next.
struct GuidePreview: View {
    let channel: Channel?
    let store: GuideStore
    let tunedID: String?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            panel(at: context.date)
        }
    }

    @ViewBuilder
    private func panel(at date: Date) -> some View {
        if let channel {
            let program = store.program(for: channel, at: date)

            HStack(alignment: .center, spacing: 24) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(channel.num)")
                        .font(.bw(94, .black))
                        .foregroundStyle(BW.yellow)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                    Text((channel.cat ?? "LIVE TV").uppercased())
                        .font(.bw(12, .black))
                        .foregroundStyle(BW.orange)
                        .lineLimit(1)
                }
                .frame(width: 132, alignment: .leading)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 12) {
                        Text(channel.name.uppercased())
                            .font(.bw(32, .black))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if channel.id == tunedID {
                            Text("WATCHING")
                                .font(.bw(11, .black))
                                .foregroundStyle(BW.ink)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(BW.yellow)
                        }
                        Spacer(minLength: 0)
                    }

                    if let blurb = channel.blurb, !blurb.isEmpty {
                        Text(blurb)
                            .font(.bw(17, .regular))
                            .foregroundStyle(BW.ice)
                            .lineLimit(1)
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("NOW PLAYING")
                            .font(.bw(12, .black))
                            .foregroundStyle(BW.orange)
                        Text(program.title.uppercased())
                            .font(.bw(27, .black))
                            .foregroundStyle(BW.yellow)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 2)

                    if let progress = program.progress {
                        progressRow(program: program, progress: progress, date: date)
                    } else {
                        Text(channel.isWeather ? "LIVE LOCAL FORECAST" : "LIVE")
                            .font(.bw(13, .black))
                            .foregroundStyle(BW.ice.opacity(0.8))
                    }
                }

                Spacer(minLength: 12)

                VStack(alignment: .leading, spacing: 4) {
                    Text("UP NEXT")
                        .font(.bw(12, .black))
                        .foregroundStyle(BW.orange)
                    if let next = program.next, !next.isEmpty {
                        Text(next.uppercased())
                            .font(.bw(18, .bold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                    } else {
                        Text("—")
                            .font(.bw(18, .bold))
                            .foregroundStyle(BW.ice)
                    }
                }
                .frame(width: 370, alignment: .leading)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .background(BW.panel)
            .overlay(Rectangle().stroke(BW.orange, lineWidth: 3))
        } else {
            Text("NO CHANNELS")
                .font(.bw(30, .black))
                .foregroundStyle(BW.orange)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(BW.panel)
                .overlay(Rectangle().stroke(BW.orange, lineWidth: 3))
        }
    }

    private func progressRow(program: ProgramInfo, progress: Double, date: Date) -> some View {
        HStack(spacing: 14) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.16))
                    Capsule()
                        .fill(BW.orange)
                        .frame(width: max(4, geometry.size.width * progress))
                }
            }
            .frame(height: 5)
            .frame(maxWidth: 500)

            if let start = program.start, let end = program.end {
                Text("\(BW.time(start))–\(BW.time(end))")
                    .font(.bw(15, .bold))
                    .foregroundStyle(BW.ice)
                    .fixedSize()

                let remainingMinutes = Int((max(0, end.timeIntervalSince(date)) / 60).rounded(.up))
                Text("\(remainingMinutes) MIN LEFT")
                    .font(.bw(14, .black))
                    .foregroundStyle(BW.orange)
                    .fixedSize()
            }

            Spacer(minLength: 0)
        }
    }
}
