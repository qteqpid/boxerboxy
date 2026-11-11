import AppKit
import Foundation

enum GameSaveError: Error, LocalizedError {
    case invalidHeader
    case missingSaveDirectory

    var errorDescription: String? {
        switch self {
        case .invalidHeader:
            return "存档文件头不匹配"
        case .missingSaveDirectory:
            return "无法定位本地存档文件夹"
        }
    }
}

struct SavedGameSummary {
    let url: URL
    let title: String
    let detail: String
}

struct GameSaveFile: Codable {
    static let currentFormatVersion = 1

    var formatVersion = currentFormatVersion
    var savedAt: Date
    var planeIndex: Int
    var player: SavedPlayer
    var inventory: [ItemID: Int]
    var unlockedRecipes: Set<RecipeID>
    var craftedItems: Set<RecipeID>
    var sealedPlanes: Set<PlaneID>
    var collectedCores: Set<ItemID>
    var resourceNodes: [PlaneID: [ResourceNode]]
    var plants: [PlaneID: [TallPlant]]
    var enemies: [PlaneID: [Enemy]]
    var rifts: [PlaneID: Rift]
    var pages: [PlaneID: RunePage]
    var relics: [PlaneID: [AncientRelic]]
    var activeRelicInterior: SavedRelicInterior?
    var resourceRegrowthClock: Double
    var won: Bool

    init(state: GameState, savedAt: Date = Date()) {
        self.savedAt = savedAt
        planeIndex = state.planeIndex
        player = SavedPlayer(player: state.player)
        inventory = state.inventory
        unlockedRecipes = state.unlockedRecipes
        craftedItems = state.craftedItems
        sealedPlanes = state.sealedPlanes
        collectedCores = state.collectedCores
        resourceNodes = state.resourceNodes
        plants = state.plants
        enemies = state.enemies
        rifts = state.rifts
        pages = state.pages
        relics = state.relics
        activeRelicInterior = state.activeRelicInterior.map(SavedRelicInterior.init(interior:))
        resourceRegrowthClock = state.resourceRegrowthClock
        won = state.won
    }
}

struct SavedPlayer: Codable {
    var position: CGPoint
    var vitality: Double
    var thermal: Double
    var stamina: Double
    var pollution: Double
    var hitCooldown: Double
    var harvestCooldown: Double
    var attackCooldown: Double
    var dashCooldown: Double
    var jumpHeight: CGFloat
    var jumpVelocity: CGFloat
    var isWalking: Bool
    var moveDirection: SavedVector
    var lastAimDirection: SavedVector

    init(player: Player) {
        position = player.position
        vitality = player.vitality
        thermal = player.thermal
        stamina = player.stamina
        pollution = player.pollution
        hitCooldown = player.hitCooldown
        harvestCooldown = player.harvestCooldown
        attackCooldown = player.attackCooldown
        dashCooldown = player.dashCooldown
        jumpHeight = player.jumpHeight
        jumpVelocity = player.jumpVelocity
        isWalking = false
        moveDirection = SavedVector(vector: .zero)
        lastAimDirection = SavedVector(vector: player.lastAimDirection)
    }

    var restoredPlayer: Player {
        Player(
            position: position,
            vitality: vitality,
            thermal: thermal,
            stamina: stamina,
            pollution: pollution,
            hitCooldown: hitCooldown,
            harvestCooldown: harvestCooldown,
            attackCooldown: attackCooldown,
            dashCooldown: dashCooldown,
            jumpHeight: jumpHeight,
            jumpVelocity: jumpVelocity,
            isWalking: isWalking,
            moveDirection: moveDirection.cgVector,
            lastAimDirection: lastAimDirection.cgVector
        )
    }
}

struct SavedVector: Codable {
    var dx: CGFloat
    var dy: CGFloat

    init(vector: CGVector) {
        dx = vector.dx
        dy = vector.dy
    }

    var cgVector: CGVector {
        CGVector(dx: dx, dy: dy)
    }
}

struct SavedRelicInterior: Codable {
    var planeID: PlaneID
    var relicID: Int
    var returnPosition: CGPoint
    var echoShards: [InteriorEchoShard]

    init(interior: RelicInterior) {
        planeID = interior.planeID
        relicID = interior.relicID
        returnPosition = interior.returnPosition
        echoShards = interior.echoShards
    }
}

enum GameSaveStore {
    private static let header = Data([0x42, 0x42, 0x58, 0x59, 0x53, 0x41, 0x56, 0x45, 0x01])
    static let fileExtension = "bbxsave"

    static var savesDirectory: URL {
        get throws {
            guard let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                throw GameSaveError.missingSaveDirectory
            }
            return root.appendingPathComponent("立方锚界", isDirectory: true)
                .appendingPathComponent("Saves", isDirectory: true)
        }
    }

    static func ensureSavesDirectory() throws -> URL {
        let directory = try savesDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func save(_ state: GameState) throws -> URL {
        let directory = try ensureSavesDirectory()
        let timestamp = Self.fileTimestampFormatter.string(from: Date())
        let url = directory.appendingPathComponent("立方锚界-\(timestamp)").appendingPathExtension(fileExtension)
        try write(GameSaveFile(state: state), to: url)
        return url
    }

    static func write(_ saveFile: GameSaveFile, to url: URL) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let payload = try encoder.encode(saveFile)
        var data = header
        data.append(payload)
        try data.write(to: url, options: [.atomic])
    }

    static func load(from url: URL) throws -> GameState {
        let saveFile = try readSaveFile(from: url)
        return GameState(saveFile: saveFile)
    }

    static func summaries() -> [SavedGameSummary] {
        guard let directory = try? ensureSavesDirectory(),
              let urls = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
              ) else {
            return []
        }

        return urls
            .filter { $0.pathExtension == fileExtension }
            .compactMap { url -> SavedGameSummary? in
                guard let saveFile = try? readSaveFile(from: url) else { return nil }
                let planeName = Plane.defaults.indices.contains(saveFile.planeIndex)
                    ? Plane.defaults[saveFile.planeIndex].shortName
                    : "未知位面"
                let title = saveFile.won ? "主线完成" : "晶核 \(saveFile.collectedCores.count) / \(Plane.defaults.count)"
                let detail = "\(planeName)  \(Self.displayDateFormatter.string(from: saveFile.savedAt))"
                return SavedGameSummary(url: url, title: title, detail: detail)
            }
            .sorted { lhs, rhs in
                let leftDate = ((try? lhs.url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate) ?? .distantPast
                let rightDate = ((try? rhs.url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate) ?? .distantPast
                return leftDate > rightDate
            }
    }

    private static func readSaveFile(from url: URL) throws -> GameSaveFile {
        let data = try Data(contentsOf: url)
        guard data.starts(with: header) else {
            throw GameSaveError.invalidHeader
        }
        let payload = data.dropFirst(header.count)
        return try PropertyListDecoder().decode(GameSaveFile.self, from: Data(payload))
    }

    private static let fileTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    private static let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
}

extension GameState {
    init(saveFile: GameSaveFile) {
        self.init()
        planeIndex = clamp(saveFile.planeIndex, 0, max(0, planes.count - 1))
        player = saveFile.player.restoredPlayer
        camera = .zero
        inventory = saveFile.inventory
        unlockedRecipes = saveFile.unlockedRecipes
        craftedItems = saveFile.craftedItems
        sealedPlanes = saveFile.sealedPlanes
        collectedCores = saveFile.collectedCores
        resourceNodes = saveFile.resourceNodes
        plants = saveFile.plants
        enemies = saveFile.enemies
        rifts = saveFile.rifts
        pages = saveFile.pages
        relics = saveFile.relics
        activeRelicInterior = saveFile.activeRelicInterior.flatMap { savedInterior in
            guard let plane = planes.first(where: { $0.id == savedInterior.planeID }),
                  let relic = relics[savedInterior.planeID]?.first(where: { $0.id == savedInterior.relicID }) else {
                return nil
            }
            var interior = RelicInterior(plane: plane, relic: relic, returnPosition: savedInterior.returnPosition)
            interior.echoShards = savedInterior.echoShards
            return interior
        }
        fireballs = []
        enemyProjectiles = []
        particles = []
        resourceRegrowthClock = saveFile.resourceRegrowthClock
        toast = nil
        toastUntil = 0
        codexNote = nil
        codexNoteUntil = 0
        planeFlipProgress = 0
        won = saveFile.won
    }
}
