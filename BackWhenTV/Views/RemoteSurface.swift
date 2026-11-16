import SwiftUI

struct RemoteSurface: View {
    @FocusState.Binding var focus: TVFocus?

    let onSelect: () -> Void
    let onUp: () -> Void
    let onDown: () -> Void
    let onMenu: () -> Void
    let onPlayPause: () -> Void

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .focusable()
            .focusEffectDisabled()
            .focused($focus, equals: .surface)
            .onTapGesture(perform: onSelect)
            .onMoveCommand { direction in
                switch direction {
                case .up: onUp()
                case .down: onDown()
                default: break
                }
            }
            .onExitCommand(perform: onMenu)
            .onPlayPauseCommand(perform: onPlayPause)
            .onAppear { focus = .surface }
            .ignoresSafeArea()
    }
}
