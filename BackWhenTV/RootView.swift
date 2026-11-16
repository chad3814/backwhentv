import SwiftUI

enum TVFocus: Hashable {
    case surface
    case channel(String)
}

struct RootView: View {
    let store: GuideStore
    let player: PlayerController
    let usage: UsageReporter

    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var focus: TVFocus?
    @State private var showGuide = false
    @State private var showBanner = false
    @State private var bannerTask: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()

            if store.state == .ready {
                readyContent
            } else {
                SplashView(state: store.state, onRetry: retry)
            }
        }
        .task {
            usage.start()
            await boot()
        }
        .onChange(of: showGuide) { _, isOpen in
            if !isOpen {
                DispatchQueue.main.async { focus = .surface }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task { await store.refreshIfStale() }
                player.resumeIfSuspended()
                if !player.isPaused, let channel = player.currentChannel {
                    usage.switchTo(channel.id)
                }
            case .inactive:
                // Stop the watch clock if the app is covered by the system.
                usage.switchTo(nil)
            case .background:
                player.suspendPlayback()
                usage.switchTo(nil)
                usage.flushAndSend()
            @unknown default:
                break
            }
        }
        .animation(.easeInOut(duration: 0.18), value: showGuide)
        .animation(.easeInOut(duration: 0.22), value: showBanner)
        .onDisappear {
            bannerTask?.cancel()
        }
    }

    @ViewBuilder
    private var readyContent: some View {
        PlayerLayerView(player: player.player)
            .ignoresSafeArea()

        if player.isWeather, !showGuide {
            WeatherOverlay(store: store)
                .transition(.opacity)
        }

        if !showGuide {
            RemoteSurface(
                focus: $focus,
                onSelect: openGuide,
                onUp: { stepChannel(1) },
                onDown: { stepChannel(-1) },
                onMenu: openGuide,
                onPlayPause: {
                    player.togglePause()
                    usage.switchTo(player.isPaused ? nil : player.currentChannel?.id)
                    flashBanner()
                }
            )
        }

        if player.isLoading, !player.isWeather, !showGuide {
            ZStack { LoadingOverlay() }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
        }

        if player.noSignal, !showGuide {
            ZStack { NoSignalOverlay(channel: player.currentChannel) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
        }

        if showBanner, !showGuide {
            BannerView(channel: player.currentChannel, store: store, isPaused: player.isPaused)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }

        if showGuide {
            GuideView(
                focus: $focus,
                store: store,
                tunedID: player.currentChannel?.id ?? store.tunedChannelID,
                now: store.now,
                onSelect: tune,
                onClose: closeGuide
            )
            .transition(.opacity)
        }
    }

    // MARK: - Lifecycle

    private func boot() async {
        if store.state != .ready {
            await store.load()
        }
        tuneInitially()
    }

    private func retry() {
        Task { await boot() }
    }

    private func tuneInitially() {
        guard store.state == .ready, player.currentChannel == nil, !store.channels.isEmpty else { return }
        let channel = store.channels.first { $0.id == store.tunedChannelID } ?? store.channels[0]
        tune(channel)
    }

    // MARK: - Remote actions

    private func tune(_ channel: Channel) {
        player.tune(channel, store: store)
        store.tunedChannelID = channel.id
        usage.switchTo(channel.id)
        showGuide = false
        flashBanner()
    }

    private func stepChannel(_ delta: Int) {
        guard let current = player.currentChannel,
              let index = store.channels.firstIndex(where: { $0.id == current.id }),
              !store.channels.isEmpty
        else { return }
        let count = store.channels.count
        let next = store.channels[(index + delta + count) % count]
        tune(next)
    }

    private func openGuide() {
        guard store.state == .ready else { return }
        showBanner = false
        showGuide = true

        let target = player.currentChannel?.id ?? store.tunedChannelID ?? store.channels.first?.id
        if let target {
            DispatchQueue.main.async { focus = .channel(target) }
        }
    }

    private func closeGuide() {
        showGuide = false
        DispatchQueue.main.async { focus = .surface }
    }

    private func flashBanner() {
        showBanner = true
        bannerTask?.cancel()
        bannerTask = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.28)) {
                showBanner = false
            }
        }
    }
}
