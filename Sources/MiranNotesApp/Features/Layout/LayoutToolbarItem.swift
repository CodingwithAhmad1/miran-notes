import SwiftUI

/// Global layout control: visible whenever the toolbar is shown; interaction requires a vault-backed `AppModel`.
struct LayoutToolbarItem: View {
    var model: AppModel?
    var vaultSessionRegistry: VaultSessionRegistry
    var onToolbarInteraction: () -> Void = {}
    @State private var layoutSelectorVisible = false

    private var isGloballyActive: Bool {
        vaultSessionRegistry.hasAnyVaultSession
    }

    private var canPickLayout: Bool {
        model != nil
    }

    var body: some View {
        Button {
            onToolbarInteraction()
            guard canPickLayout else { return }
            layoutSelectorVisible.toggle()
        } label: {
            Image(systemName: "rectangle.split.2x2")
        }
        .help("Change layout")
        .disabled(!canPickLayout)
        .opacity(isGloballyActive ? 1 : 0.4)
        .popover(isPresented: $layoutSelectorVisible, arrowEdge: .bottom) {
            if let model {
                LayoutSelectorView(model: model)
            }
        }
    }
}
