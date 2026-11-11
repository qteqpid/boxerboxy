import AppKit
import UniformTypeIdentifiers

final class MainMenuView: NSView {
    private let onNewGame: () -> Void
    private let onLoadGame: (GameState) -> Void
    private let savesStack = NSStackView()
    private let statusLabel = NSTextField(labelWithString: "")

    init(frame frameRect: NSRect, onNewGame: @escaping () -> Void, onLoadGame: @escaping (GameState) -> Void) {
        self.onNewGame = onNewGame
        self.onLoadGame = onLoadGame
        super.init(frame: frameRect)
        configure()
        reloadSaves()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let gradient = NSGradient(colors: [
            NSColor(hex: "#02050b"),
            NSColor(hex: "#081421"),
            NSColor(hex: "#12101d")
        ])
        gradient?.draw(in: bounds, angle: 18)

        NSColor(hex: "#48e2ff").withAlphaComponent(0.08).setStroke()
        for x in stride(from: CGFloat(-120), through: bounds.width + 120, by: 78) {
            let path = NSBezierPath()
            path.lineWidth = 1
            path.move(to: CGPoint(x: x, y: bounds.minY))
            path.line(to: CGPoint(x: x + bounds.height * 0.36, y: bounds.maxY))
            path.stroke()
        }
        NSColor(hex: "#ff375c").withAlphaComponent(0.07).setStroke()
        for y in stride(from: CGFloat(44), through: bounds.height, by: 72) {
            let path = NSBezierPath()
            path.lineWidth = 1
            path.move(to: CGPoint(x: bounds.minX, y: y))
            path.line(to: CGPoint(x: bounds.maxX, y: y + 28))
            path.stroke()
        }

        let horizon = NSBezierPath()
        horizon.move(to: CGPoint(x: bounds.width * 0.54, y: bounds.minY))
        horizon.line(to: CGPoint(x: bounds.maxX, y: bounds.height * 0.28))
        horizon.line(to: CGPoint(x: bounds.maxX, y: bounds.maxY))
        horizon.line(to: CGPoint(x: bounds.width * 0.78, y: bounds.maxY))
        horizon.close()
        NSColor(hex: "#48e2ff").withAlphaComponent(0.055).setFill()
        horizon.fill()
    }

    private func configure() {
        wantsLayer = true

        let panel = MenuPanelView()
        panel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(panel)

        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 16
        root.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(root)

        let eyebrow = NSTextField(labelWithString: "BBX SAVE TERMINAL")
        eyebrow.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)
        eyebrow.textColor = NSColor(hex: "#48e2ff")

        let title = NSTextField(labelWithString: "立方锚界")
        title.font = NSFont.systemFont(ofSize: 54, weight: .black)
        title.textColor = .white

        let subtitle = NSTextField(labelWithString: "选择本地二进制存档，或启动新的六界巡礼。")
        subtitle.font = NSFont.systemFont(ofSize: 15, weight: .medium)
        subtitle.textColor = NSColor(hex: "#d6eef6")

        let actionRow = NSStackView()
        actionRow.orientation = .horizontal
        actionRow.spacing = 10
        actionRow.addArrangedSubview(menuButton(title: "新游戏", action: #selector(startNewGame), primary: true))
        actionRow.addArrangedSubview(menuButton(title: "打开存档", action: #selector(openSaveFile)))
        actionRow.addArrangedSubview(menuButton(title: "刷新", action: #selector(refreshSaves)))
        actionRow.addArrangedSubview(menuButton(title: "存档文件夹", action: #selector(openSavesFolder)))

        let savesTitle = NSTextField(labelWithString: "本地存档")
        savesTitle.font = NSFont.monospacedSystemFont(ofSize: 15, weight: .bold)
        savesTitle.textColor = NSColor(hex: "#f7c96a")

        savesStack.orientation = .vertical
        savesStack.alignment = .leading
        savesStack.spacing = 10
        savesStack.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor(hex: "#030812").withAlphaComponent(0.68)
        scrollView.documentView = savesStack
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.widthAnchor.constraint(equalToConstant: 590).isActive = true
        scrollView.heightAnchor.constraint(equalToConstant: 306).isActive = true

        statusLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        statusLabel.textColor = NSColor(hex: "#9bdff0")

        root.addArrangedSubview(eyebrow)
        root.addArrangedSubview(title)
        root.addArrangedSubview(subtitle)
        root.addArrangedSubview(actionRow)
        root.addArrangedSubview(savesTitle)
        root.addArrangedSubview(scrollView)
        root.addArrangedSubview(statusLabel)

        NSLayoutConstraint.activate([
            panel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 56),
            panel.topAnchor.constraint(equalTo: topAnchor, constant: 52),
            panel.widthAnchor.constraint(equalToConstant: 668),
            panel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -44),

            root.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 30),
            root.topAnchor.constraint(equalTo: panel.topAnchor, constant: 28),
            root.trailingAnchor.constraint(lessThanOrEqualTo: panel.trailingAnchor, constant: -30),
            root.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -28)
        ])
    }

    private func menuButton(title: String, action: Selector, primary: Bool = false) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 7
        button.layer?.backgroundColor = (primary ? NSColor(hex: "#ff375c") : NSColor(hex: "#092133")).withAlphaComponent(primary ? 0.92 : 0.86).cgColor
        button.layer?.borderWidth = 1
        button.layer?.borderColor = (primary ? NSColor(hex: "#ffd37a") : NSColor(hex: "#48e2ff")).withAlphaComponent(0.64).cgColor
        button.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .bold),
                .foregroundColor: NSColor.white
            ]
        )
        button.controlSize = .large
        button.heightAnchor.constraint(equalToConstant: 36).isActive = true
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: primary ? 96 : 82).isActive = true
        return button
    }

    private func reloadSaves() {
        savesStack.arrangedSubviews.forEach { view in
            savesStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let summaries = GameSaveStore.summaries()
        if summaries.isEmpty {
            let empty = NSTextField(labelWithString: "暂无存档。进入游戏后按 P 写入本地文件。")
            empty.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
            empty.textColor = NSColor(hex: "#d6eef6")
            savesStack.addArrangedSubview(empty)
        } else {
            summaries.forEach { savesStack.addArrangedSubview(saveRow(for: $0)) }
        }

        if let directory = try? GameSaveStore.ensureSavesDirectory() {
            statusLabel.stringValue = "存档目录：\(directory.path)"
        }
    }

    private func saveRow(for summary: SavedGameSummary) -> NSView {
        let container = SaveRowPanelView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.widthAnchor.constraint(equalToConstant: 570).isActive = true
        container.heightAnchor.constraint(equalToConstant: 64).isActive = true

        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(row)

        let labels = NSStackView()
        labels.orientation = .vertical
        labels.spacing = 3

        let title = NSTextField(labelWithString: summary.title)
        title.font = NSFont.systemFont(ofSize: 14, weight: .bold)
        title.textColor = .white

        let detail = NSTextField(labelWithString: summary.detail)
        detail.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        detail.textColor = NSColor(hex: "#9bdff0")

        labels.addArrangedSubview(title)
        labels.addArrangedSubview(detail)

        let button = SaveLoadButton(title: "载入", target: self, action: #selector(loadSaveFromButton(_:)))
        button.saveURL = summary.url
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 6
        button.layer?.backgroundColor = NSColor(hex: "#48e2ff").withAlphaComponent(0.18).cgColor
        button.layer?.borderWidth = 1
        button.layer?.borderColor = NSColor(hex: "#48e2ff").withAlphaComponent(0.78).cgColor
        button.attributedTitle = NSAttributedString(
            string: "载入",
            attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .bold),
                .foregroundColor: NSColor.white
            ]
        )
        button.widthAnchor.constraint(equalToConstant: 68).isActive = true
        button.heightAnchor.constraint(equalToConstant: 30).isActive = true

        row.addArrangedSubview(labels)
        row.addArrangedSubview(NSView())
        row.addArrangedSubview(button)

        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            row.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        return container
    }

    @objc private func startNewGame() {
        onNewGame()
    }

    @objc private func refreshSaves() {
        reloadSaves()
    }

    @objc private func openSaveFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if let saveType = UTType(filenameExtension: GameSaveStore.fileExtension) {
            panel.allowedContentTypes = [saveType]
        }
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.loadSave(from: url)
        }
    }

    @objc private func openSavesFolder() {
        guard let directory = try? GameSaveStore.ensureSavesDirectory() else { return }
        NSWorkspace.shared.open(directory)
    }

    @objc private func loadSaveFromButton(_ sender: SaveLoadButton) {
        guard let url = sender.saveURL else { return }
        loadSave(from: url)
    }

    private func loadSave(from url: URL) {
        do {
            let state = try GameSaveStore.load(from: url)
            onLoadGame(state)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            statusLabel.stringValue = "读取失败：\(message)"
        }
    }
}

private final class SaveLoadButton: NSButton {
    var saveURL: URL?
}

private final class MenuPanelView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.52
        layer?.shadowRadius = 28
        layer?.shadowOffset = NSSize(width: 0, height: -8)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 18, yRadius: 18)

        let gradient = NSGradient(colors: [
            NSColor(hex: "#07111d").withAlphaComponent(0.98),
            NSColor(hex: "#040812").withAlphaComponent(0.96)
        ])
        gradient?.draw(in: path, angle: 90)

        NSColor(hex: "#48e2ff").withAlphaComponent(0.38).setStroke()
        path.lineWidth = 1.5
        path.stroke()

        let accent = NSBezierPath()
        accent.move(to: CGPoint(x: rect.minX + 22, y: rect.maxY - 1))
        accent.line(to: CGPoint(x: rect.minX + 218, y: rect.maxY - 1))
        NSColor(hex: "#ff375c").withAlphaComponent(0.86).setStroke()
        accent.lineWidth = 3
        accent.stroke()

        let scan = NSBezierPath()
        scan.move(to: CGPoint(x: rect.minX + 1, y: rect.minY + 86))
        scan.line(to: CGPoint(x: rect.maxX - 1, y: rect.minY + 118))
        NSColor.white.withAlphaComponent(0.035).setStroke()
        scan.lineWidth = 1
        scan.stroke()
    }
}

private final class SaveRowPanelView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
        NSColor(hex: "#071827").withAlphaComponent(0.92).setFill()
        path.fill()
        NSColor(hex: "#48e2ff").withAlphaComponent(0.22).setStroke()
        path.lineWidth = 1
        path.stroke()

        let marker = NSBezierPath(roundedRect: CGRect(x: rect.minX + 1, y: rect.minY + 10, width: 4, height: rect.height - 20), xRadius: 2, yRadius: 2)
        NSColor(hex: "#f7c96a").withAlphaComponent(0.78).setFill()
        marker.fill()
    }
}
