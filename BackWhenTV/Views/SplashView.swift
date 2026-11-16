import SwiftUI

struct SplashView: View {
    let state: GuideStore.LoadState
    let onRetry: () -> Void

    @FocusState private var retryFocused: Bool

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                HStack(spacing: 0) {
                    Text("BackWhen")
                        .foregroundStyle(.white)
                    Text("TV")
                        .foregroundStyle(BW.yellow)
                }
                .font(.bw(112, .black))

                Text("CABLE TV, THE WAY YOU REMEMBER IT")
                    .font(.bw(21, .bold))
                    .tracking(3.5)
                    .foregroundStyle(BW.ice)
                    .padding(.top, 10)

                Spacer()
                status
                Spacer().frame(height: 72)
            }
            .padding(.horizontal, 80)
        }
    }

    @ViewBuilder
    private var status: some View {
        switch state {
        case .loading:
            VStack(spacing: 22) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(BW.yellow)
                    .scaleEffect(1.5)
                Text("TUNING IN...")
                    .font(.bw(24, .black))
                    .foregroundStyle(BW.yellow)
                    .tracking(2)
            }

        case .failed(let message):
            VStack(spacing: 20) {
                Text(message)
                    .font(.bw(32, .black))
                    .foregroundStyle(BW.orange)
                    .multilineTextAlignment(.center)
                Text("CHECK YOUR CONNECTION AND TRY AGAIN")
                    .font(.bw(18, .bold))
                    .foregroundStyle(BW.ice)
                    .tracking(1.5)

                Button(action: onRetry) {
                    Text("TRY AGAIN")
                        .font(.bw(22, .black))
                        .foregroundStyle(retryFocused ? BW.ink : BW.yellow)
                        .padding(.horizontal, 34)
                        .padding(.vertical, 14)
                        .background(retryFocused ? BW.yellow : Color.clear)
                        .overlay(Rectangle().stroke(BW.yellow, lineWidth: 3))
                }
                .buttonStyle(.plain)
                .focused($retryFocused)
                .padding(.top, 8)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        retryFocused = true
                    }
                }
            }

        case .ready:
            EmptyView()
        }
    }
}
