import SwiftUI

struct GuideView: View {
    @FocusState.Binding var focus: TVFocus?

    let store: GuideStore
    let tunedID: String?
    let now: Date
    let onSelect: (Channel) -> Void
    let onClose: () -> Void

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 12) {
                VStack(spacing: 10) {
                    header
                    GuidePreview(channel: selectedChannel, store: store, tunedID: tunedID)
                }
                .frame(height: geometry.size.height * 0.25, alignment: .top)

                columnHeader

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 7) {
                            ForEach(store.channels) { channel in
                                GuideRow(
                                    channel: channel,
                                    program: store.program(for: channel, at: now),
                                    isFocused: focus == .channel(channel.id),
                                    isTuned: channel.id == tunedID,
                                    action: { onSelect(channel) }
                                )
                                .id(channel.id)
                                .focused($focus, equals: .channel(channel.id))
                            }
                        }
                        .padding(.bottom, 6)
                    }
                    .scrollIndicators(.hidden)
                    .onAppear {
                        if let tunedID, store.channels.contains(where: { $0.id == tunedID }) {
                            DispatchQueue.main.async {
                                focus = .channel(tunedID)
                                proxy.scrollTo(tunedID, anchor: .center)
                            }
                        } else if let first = store.channels.first {
                            DispatchQueue.main.async {
                                focus = .channel(first.id)
                            }
                        }
                    }
                    .onChange(of: focus) { _, newValue in
                        guard case .channel(let id) = newValue else { return }
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                }

                footer
            }
            .padding(.horizontal, 54)
            .padding(.top, 26)
            .padding(.bottom, 22)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(BW.blue.ignoresSafeArea())
        .onExitCommand(perform: onClose)
    }

    /// The row the remote is currently on, falling back to the tuned channel
    /// while focus is being established.
    private var selectedChannel: Channel? {
        if case .channel(let id) = focus,
           let channel = store.channels.first(where: { $0.id == id }) {
            return channel
        }
        if let tunedID, let channel = store.channels.first(where: { $0.id == tunedID }) {
            return channel
        }
        return store.channels.first
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 12) {
                Text("BACKWHENTV")
                    .font(.bw(44, .black))
                    .foregroundStyle(BW.yellow)
                Text("GUIDE")
                    .font(.bw(44, .black))
                    .foregroundStyle(BW.yellow.opacity(0.65))
            }
            Spacer()
            Text("\(BW.day(now))   \(BW.time(now))")
                .font(.bw(28, .bold))
                .foregroundStyle(BW.orange)
        }
        .padding(.horizontal, 4)
    }

    private var columnHeader: some View {
        HStack(spacing: 0) {
            Text("CH").frame(width: 120, alignment: .leading)
            Text("CHANNEL").frame(width: 350, alignment: .leading)
            Text("NOW PLAYING")
            Spacer(minLength: 0)
            Text("UP NEXT").frame(width: 430, alignment: .leading)
        }
        .font(.bw(15, .black))
        .foregroundStyle(BW.orange)
        .padding(.horizontal, 24)
    }

    private var footer: some View {
        HStack(spacing: 26) {
            KeyCap(key: "▲ ▼", label: "BROWSE")
            KeyCap(key: "SELECT", label: "WATCH")
            KeyCap(key: "MENU", label: "CLOSE")
            Spacer()
            Text("\(store.channels.count) CHANNELS")
                .font(.bw(16, .black))
                .foregroundStyle(BW.orange.opacity(0.85))
        }
        .padding(.horizontal, 4)
    }
}

private struct GuideRow: View {
    let channel: Channel
    let program: ProgramInfo
    let isFocused: Bool
    let isTuned: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                HStack(spacing: 10) {
                    Text("\(channel.num)")
                        .font(.bw(36, .black))
                        .frame(minWidth: 84, alignment: .leading)
                    if isTuned {
                        Circle()
                            .fill(isFocused ? BW.orange : BW.yellow)
                            .frame(width: 9, height: 9)
                    }
                }
                .frame(width: 120, alignment: .leading)

                Text(channel.name.uppercased())
                    .font(.bw(24, .black))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: 350, alignment: .leading)

                Text(program.title.uppercased())
                    .font(.bw(25, program.isAd ? .black : .regular))
                    .foregroundStyle(program.isAd ? BW.orange : .primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, 24)

                VStack(alignment: .leading, spacing: 1) {
                    Text("NEXT")
                        .font(.bw(11, .black))
                        .foregroundStyle(isFocused ? BW.ink.opacity(0.55) : BW.orange)
                    if let next = program.next, !next.isEmpty {
                        Text(next.uppercased())
                            .font(.bw(18, .regular))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    } else {
                        Text("—")
                            .font(.bw(18, .regular))
                    }
                }
                .frame(width: 430, alignment: .leading)
            }
            .padding(.horizontal, 24)
            .frame(height: 74)
            .foregroundStyle(isFocused ? BW.ink : Color.white)
            .background(isFocused ? BW.yellow : BW.row)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(isFocused ? BW.orange : Color.clear)
                    .frame(width: 7)
            }
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .animation(.easeOut(duration: 0.12), value: isFocused)
    }
}
