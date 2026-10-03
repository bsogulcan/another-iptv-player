import SwiftUI
import UIKit

/// UIKit owns the presented menu. SwiftUI updates only the callbacks for the next
/// opening, never UIButton.menu or the elements currently being scrolled.
struct PlayerMoreMenuButton: UIViewRepresentable {
    let makeMenu: () -> UIMenu
    let onPresentationChange: (Bool) -> Void

    func makeUIView(context: Context) -> PlayerMoreMenuUIKitButton {
        let button = PlayerMoreMenuUIKitButton(type: .system)
        updateUIView(button, context: context)
        return button
    }

    func updateUIView(_ button: PlayerMoreMenuUIKitButton, context: Context) {
        button.makeMenu = makeMenu
        button.onPresentationChange = onPresentationChange
        button.accessibilityLabel = L("detail.show_more")
    }
}

final class PlayerMoreMenuUIKitButton: UIButton {
    var makeMenu: (() -> UIMenu)?
    var onPresentationChange: ((Bool) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setImage(UIImage(systemName: "ellipsis", withConfiguration:
            UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)), for: .normal)
        tintColor = UIColor.white.withAlphaComponent(0.96)
        accessibilityIdentifier = "player.more"
        showsMenuAsPrimaryAction = true
        preferredMenuElementOrder = .fixed
        // Resolve once per opening, including the sleep timer's remaining time.
        // No cached elements or live SwiftUI Picker bindings survive between opens.
        menu = UIMenu(children: [UIDeferredMenuElement.uncached { [weak self] completion in
            completion(self?.menuElementsForPresentation() ?? [])
        }])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func menuElementsForPresentation() -> [UIMenuElement] {
        makeMenu?().children ?? []
    }

    override func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        willDisplayMenuFor configuration: UIContextMenuConfiguration,
        animator: (any UIContextMenuInteractionAnimating)?
    ) {
        super.contextMenuInteraction(interaction, willDisplayMenuFor: configuration, animator: animator)
        onPresentationChange?(true)
    }

    override func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        willEndFor configuration: UIContextMenuConfiguration,
        animator: (any UIContextMenuInteractionAnimating)?
    ) {
        super.contextMenuInteraction(interaction, willEndFor: configuration, animator: animator)
        if let animator {
            animator.addCompletion { [weak self] in self?.onPresentationChange?(false) }
        } else {
            onPresentationChange?(false)
        }
    }
}
