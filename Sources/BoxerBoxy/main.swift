import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let frame = NSRect(x: 0, y: 0, width: 1280, height: 760)
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "立方锚界"
        window.center()
        window.minSize = NSSize(width: 980, height: 620)
        window.makeKeyAndOrderFront(nil)
        self.window = window
        showMainMenu()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showMainMenu() {
        let frame = window?.contentView?.bounds ?? NSRect(x: 0, y: 0, width: 1280, height: 760)
        let menuView = MainMenuView(
            frame: frame,
            onNewGame: { [weak self] in
                self?.showGame(with: GameState())
            },
            onLoadGame: { [weak self] state in
                self?.showGame(with: state)
            }
        )
        menuView.autoresizingMask = [.width, .height]
        window?.contentView = menuView
        window?.makeFirstResponder(menuView)
    }

    private func showGame(with state: GameState) {
        let frame = window?.contentView?.bounds ?? NSRect(x: 0, y: 0, width: 1280, height: 760)
        let view = GameView(frame: frame, state: state, onReturnToMenu: { [weak self] in
            self?.showMainMenu()
        })
        view.autoresizingMask = [.width, .height]
        window?.contentView = view
        window?.makeFirstResponder(view)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

NSApplication.shared.setActivationPolicy(.regular)
let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.run()
