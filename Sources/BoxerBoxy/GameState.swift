import AppKit

struct GameState {
    static let worldSize = CGSize(width: 15000, height: 10500)

    var planes: [Plane] = Plane.defaults
    var planeIndex = 0
    var player = Player(position: CGPoint(x: worldSize.width / 2, y: worldSize.height / 2))
    var camera = CGPoint.zero
    var inventory: [ItemID: Int] = [
        .emberCrystal: 0,
        .galeCrystal: 0,
        .frostCrystal: 0,
        .verdantCrystal: 0,
        .voidCrystal: 0,
        .cloudCrystal: 0,
        .distortionShard: 0,
        .runePage: 0,
        .sealStele: 0,
        .crystalTonic: 0,
        .wildGrass: 0,
        .crystalWood: 0,
        .runeAxe: 0,
        .emberWand: 0,
        .windBoots: 0,
        .crystalSickle: 0,
        .timberSaw: 0,
        .barrierBuckler: 0,
        .skiff: 0,
        .anchorEcho: 0
    ]
    var unlockedRecipes: Set<RecipeID> = [.crystalPick, .crystalTonic, .sealStele, .runeAxe, .emberWand, .windBoots, .crystalSickle, .timberSaw, .barrierBuckler, .skiff]
    var craftedItems: Set<RecipeID> = []
    var sealedPlanes: Set<PlaneID> = []
    var collectedCores: Set<ItemID> = []
    var resourceNodes: [PlaneID: [ResourceNode]] = [:]
    var terrainFeatures: [PlaneID: [TerrainFeature]] = [:]
    var plants: [PlaneID: [TallPlant]] = [:]
    var enemies: [PlaneID: [Enemy]] = [:]
    var rifts: [PlaneID: Rift] = [:]
    var pages: [PlaneID: RunePage] = [:]
    var relics: [PlaneID: [AncientRelic]] = [:]
    var activeRelicInterior: RelicInterior?
    var fireballs: [Fireball] = []
    var enemyProjectiles: [EnemyProjectile] = []
    var particles: [Particle] = []
    var resourceRegrowthClock = 0.0
    var toast: String?
    var toastUntil = 0.0
    var codexNote: String?
    var codexNoteUntil = 0.0
    var planeFlipProgress = 0.0
    var won = false
    let recipes = Recipe.defaults

    var currentPlane: Plane {
        planes[planeIndex]
    }

    var currentWorldSize: CGSize {
        activeRelicInterior?.size ?? Self.worldSize
    }

    init() {
        for (index, plane) in planes.enumerated() {
            var random = SeededRandom(seed: UInt64(index + 11))
            resourceNodes[plane.id] = (0..<90).map { nodeIndex in
                let amount = Int.random(in: 2...5, using: &random)
                return ResourceNode(
                    id: nodeIndex,
                    position: CGPoint(
                        x: CGFloat.random(in: 180...(Self.worldSize.width - 180), using: &random),
                        y: CGFloat.random(in: 160...(Self.worldSize.height - 160), using: &random)
                    ),
                    amount: amount,
                    maxAmount: amount,
                    pulse: CGFloat.random(in: 0...(CGFloat.pi * 2), using: &random)
                )
            }
            terrainFeatures[plane.id] = (0..<18).map { featureIndex in
                let kind = TerrainKind.allCases[(featureIndex + index) % TerrainKind.allCases.count]
                return TerrainFeature(
                    id: featureIndex,
                    position: CGPoint(
                        x: CGFloat.random(in: 520...(Self.worldSize.width - 520), using: &random),
                        y: CGFloat.random(in: 420...(Self.worldSize.height - 420), using: &random)
                    ),
                    size: CGSize(
                        width: CGFloat.random(in: kind.widthRange, using: &random),
                        height: CGFloat.random(in: kind.heightRange, using: &random)
                    ),
                    kind: kind,
                    phase: CGFloat.random(in: 0...(CGFloat.pi * 2), using: &random)
                )
            }
            plants[plane.id] = (0..<150).map { plantIndex in
                let kind = TallPlantKind.allCases[(plantIndex + index) % TallPlantKind.allCases.count]
                return TallPlant(
                    id: plantIndex,
                    position: CGPoint(
                        x: CGFloat.random(in: 240...(Self.worldSize.width - 240), using: &random),
                        y: CGFloat.random(in: 220...(Self.worldSize.height - 220), using: &random)
                    ),
                    kind: kind,
                    height: CGFloat.random(in: kind.heightRange, using: &random),
                    sway: CGFloat.random(in: 0...(CGFloat.pi * 2), using: &random)
                )
            }
            let oceanFeatures = terrainFeatures[plane.id, default: []].filter { $0.kind == .ocean }
            let landEnemyKinds: [EnemyKind] = [.shardling, .skitter, .bulwark, .wisp]
            enemies[plane.id] = (0..<34).map { enemyIndex in
                let ocean = oceanFeatures.isEmpty ? nil : oceanFeatures[(enemyIndex + index) % oceanFeatures.count]
                let kind: EnemyKind = enemyIndex.isMultiple(of: 6) && ocean != nil
                    ? .reefFish
                    : landEnemyKinds[(enemyIndex + index) % landEnemyKinds.count]
                let home: CGPoint
                if let ocean, kind == .reefFish {
                    let angle = CGFloat.random(in: 0...(CGFloat.pi * 2), using: &random)
                    let radius = CGFloat.random(in: 0.12...0.42, using: &random)
                    home = CGPoint(
                        x: clamp(ocean.position.x + cos(angle) * ocean.size.width * radius, 300, Self.worldSize.width - 300),
                        y: clamp(ocean.position.y + sin(angle) * ocean.size.height * radius, 240, Self.worldSize.height - 240)
                    )
                } else {
                    home = CGPoint(
                        x: CGFloat.random(in: 300...(Self.worldSize.width - 300), using: &random),
                        y: CGFloat.random(in: 240...(Self.worldSize.height - 240), using: &random)
                    )
                }
                let health = kind.baseHealth + (plane.id == .void ? 1 : 0)
                return Enemy(
                    id: enemyIndex,
                    position: home,
                    home: home,
                    health: health,
                    maxHealth: health,
                    kind: kind,
                    phase: CGFloat.random(in: 0...(CGFloat.pi * 2), using: &random),
                    shootCooldown: CGFloat.random(in: 0.5...2.8, using: &random)
                )
            }
            rifts[plane.id] = Rift(position: CGPoint(
                x: CGFloat.random(in: 420...(Self.worldSize.width - 420), using: &random),
                y: CGFloat.random(in: 360...(Self.worldSize.height - 360), using: &random)
            ))
            pages[plane.id] = RunePage(position: CGPoint(
                x: CGFloat.random(in: 260...(Self.worldSize.width - 260), using: &random),
                y: CGFloat.random(in: 240...(Self.worldSize.height - 240), using: &random)
            ))
            relics[plane.id] = AncientRelic.defaults(for: plane, planeIndex: index, random: &random)
        }
    }

    mutating func replaceResourceNode(_ node: ResourceNode, in planeID: PlaneID) {
        guard let index = resourceNodes[planeID]?.firstIndex(where: { $0.id == node.id }) else { return }
        resourceNodes[planeID]?[index] = node
    }

    mutating func removePlant(_ plant: TallPlant, in planeID: PlaneID) {
        plants[planeID]?.removeAll { $0.id == plant.id }
    }

    var mainQuest: MainQuest {
        if won {
            return MainQuest(
                title: "终章：结界归位",
                objective: "六维核心已经稳定，立方锚界暂时脱离崩解。",
                hint: "继续探索、采集或清理残余畸变。",
                progressText: "主线完成",
                progress: 1
            )
        }

        if collectedCores.count == planes.count {
            let center = CGPoint(x: Self.worldSize.width / 2, y: Self.worldSize.height / 2)
            let distance = player.position.distance(to: center)
            return MainQuest(
                title: "终章：回到核心",
                objective: "六枚本源晶核已经集齐，回到世界中心完成结界。",
                hint: "朝地图中央移动，靠近核心祭坛。",
                progressText: "距核心 \(Int(distance))",
                progress: clamp(1 - distance / 5200, 0, 1)
            )
        }

        if collectedCores.count > 0 {
            let currentSealed = sealedPlanes.contains(currentPlane.id)
            let sealCount = inventory[.sealStele, default: 0]
            let objective = currentSealed
                ? "当前位面已稳定，切换到未封印位面继续寻找裂隙。"
                : "封印所有位面的主要裂隙，取回六枚本源晶核。"
            let hint = currentSealed
                ? "按 Q / R 切换位面。"
                : (sealCount > 0 ? "前往小地图菱形裂隙标记，靠近后按 B 放置封印石碑。" : "收集符文残页和 3 个畸变残片，按 3 锻造封印石碑。")
            return MainQuest(
                title: "第三章：六界巡礼",
                objective: objective,
                hint: hint,
                progressText: "晶核 \(collectedCores.count) / \(planes.count)",
                progress: CGFloat(collectedCores.count) / CGFloat(planes.count)
            )
        }

        if inventory[.sealStele, default: 0] > 0 {
            return MainQuest(
                title: "第二章：第一座封碑",
                objective: "带着封印石碑找到当前位面的主要裂隙。",
                hint: "小地图上的大菱形就是裂隙，靠近后按 B 封印。",
                progressText: "封印石碑就绪",
                progress: 0.82
            )
        }

        let runePages = inventory[.runePage, default: 0]
        let shards = inventory[.distortionShard, default: 0]
        if craftedItems.contains(.crystalPick) {
            let progress = (CGFloat(min(runePages, 1)) + CGFloat(min(shards, 3)) / 3) / 2
            return MainQuest(
                title: "第二章：铸造封碑",
                objective: "封印裂隙需要一座封印石碑。",
                hint: "拾取符文残页，击败畸变生物获得 3 个残片，然后按 3 锻造石碑。",
                progressText: "残页 \(min(runePages, 1)) / 1  残片 \(min(shards, 3)) / 3",
                progress: progress
            )
        }

        let ember = inventory[.emberCrystal, default: 0]
        let gale = inventory[.galeCrystal, default: 0]
        let progress = (CGFloat(min(ember, 2)) + CGFloat(min(gale, 2))) / 4
        return MainQuest(
            title: "第一章：唤醒采掘器",
            objective: "立方核心正在失稳，先锻造晶脉采掘器。",
            hint: "采集 2 个焰晶和 2 个风晶，按 2 锻造采掘器；按 Q / R 切换位面。",
            progressText: "焰晶 \(min(ember, 2)) / 2  风晶 \(min(gale, 2)) / 2",
            progress: progress
        )
    }
}

struct MainQuest {
    let title: String
    let objective: String
    let hint: String
    let progressText: String
    let progress: CGFloat
}

struct Player {
    var position: CGPoint
    var vitality = 100.0
    var thermal = 88.0
    var stamina = 100.0
    var pollution = 0.0
    var hitCooldown = 0.0
    var harvestCooldown = 0.0
    var attackCooldown = 0.0
    var dashCooldown = 0.0
    var jumpHeight: CGFloat = 0
    var jumpVelocity: CGFloat = 0
    var isWalking = false
    var moveDirection = CGVector.zero
    var lastAimDirection = CGVector(dx: 1, dy: 0)
}

enum PlaneID: String, CaseIterable, Codable {
    case ember
    case gale
    case frost
    case verdant
    case void
    case cloud
}

struct Plane {
    let id: PlaneID
    let name: String
    let shortName: String
    let lore: String
    let resource: ItemID
    let core: ItemID
    let pollutionName: String
    let hazard: Double
    let palette: Palette

    static let defaults: [Plane] = [
        Plane(id: .ember, name: "焰晶地界", shortName: "焰界", lore: "裂隙热浪正沿晶脉扩散。", resource: .emberCrystal, core: .emberCore, pollutionName: "熔蚀", hazard: 0.24, palette: Palette(dark: "#39140f", base: "#cc4b31", glow: "#ffb35f", light: "#ffd37a")),
        Plane(id: .gale, name: "土风高原", shortName: "高原", lore: "风蚀纹路把古老锚点切成层状阶梯。", resource: .galeCrystal, core: .galeCore, pollutionName: "风蚀", hazard: 0.16, palette: Palette(dark: "#2f2916", base: "#b99042", glow: "#f1d37e", light: "#9fe5dd")),
        Plane(id: .frost, name: "凝晶雪原", shortName: "雪原", lore: "凝晶冰封溢灾会持续压低恒温指数。", resource: .frostCrystal, core: .frostCore, pollutionName: "冰封", hazard: 0.28, palette: Palette(dark: "#11293a", base: "#4ea7c8", glow: "#b8f3ff", light: "#f8ffff")),
        Plane(id: .verdant, name: "翠晶密林", shortName: "密林", lore: "潮湿腐浊污染让每次奔跑都更沉重。", resource: .verdantCrystal, core: .verdantCore, pollutionName: "腐浊", hazard: 0.20, palette: Palette(dark: "#102619", base: "#3da66a", glow: "#96ef9d", light: "#e2ffb0")),
        Plane(id: .void, name: "暗符虚空", shortName: "虚空", lore: "暗蚀符文污染会干扰锻造稳定性。", resource: .voidCrystal, core: .voidCore, pollutionName: "暗蚀", hazard: 0.31, palette: Palette(dark: "#160d29", base: "#5e3aa7", glow: "#b983ff", light: "#69eff5")),
        Plane(id: .cloud, name: "云晶浮空城邦", shortName: "浮空", lore: "高空风压污染会撕扯位面边缘的气流。", resource: .cloudCrystal, core: .cloudCore, pollutionName: "风压", hazard: 0.22, palette: Palette(dark: "#17212f", base: "#9db7ca", glow: "#f4fbff", light: "#8be6ff"))
    ]
}

struct Palette {
    let dark: NSColor
    let base: NSColor
    let glow: NSColor
    let light: NSColor

    init(dark: String, base: String, glow: String, light: String) {
        self.dark = NSColor(hex: dark)
        self.base = NSColor(hex: base)
        self.glow = NSColor(hex: glow)
        self.light = NSColor(hex: light)
    }
}

enum ItemID: String, CaseIterable, Hashable, Codable {
    case emberCrystal
    case galeCrystal
    case frostCrystal
    case verdantCrystal
    case voidCrystal
    case cloudCrystal
    case distortionShard
    case runePage
    case sealStele
    case crystalTonic
    case wildGrass
    case crystalWood
    case runeAxe
    case emberWand
    case windBoots
    case crystalSickle
    case timberSaw
    case barrierBuckler
    case skiff
    case crystalPick
    case barrierArmor
    case purifyingCharm
    case skyBridge
    case emberCore
    case galeCore
    case frostCore
    case verdantCore
    case voidCore
    case cloudCore
    case anchorEcho

    var name: String {
        switch self {
        case .emberCrystal: return "焰晶"
        case .galeCrystal: return "风晶"
        case .frostCrystal: return "凝晶"
        case .verdantCrystal: return "木晶"
        case .voidCrystal: return "暗晶"
        case .cloudCrystal: return "云晶"
        case .distortionShard: return "畸变残片"
        case .runePage: return "符文残页"
        case .sealStele: return "封印石碑"
        case .crystalTonic: return "晶凝药剂"
        case .wildGrass: return "晶露小草"
        case .crystalWood: return "晶纹木"
        case .runeAxe: return "碎晶斧"
        case .emberWand: return "焰核法杖"
        case .windBoots: return "风纹靴"
        case .crystalSickle: return "晶草镰"
        case .timberSaw: return "伐晶锯"
        case .barrierBuckler: return "晶盾环"
        case .skiff: return "风纹小船"
        case .crystalPick: return "晶脉采掘器"
        case .barrierArmor: return "维度屏障铠"
        case .purifyingCharm: return "净化护符"
        case .skyBridge: return "悬空晶桥"
        case .emberCore: return "焰晶核"
        case .galeCore: return "风晶核"
        case .frostCore: return "凝晶核"
        case .verdantCore: return "木晶核"
        case .voidCore: return "暗晶核"
        case .cloudCore: return "云晶核"
        case .anchorEcho: return "锚印回响"
        }
    }
}

enum RecipeID: String, Hashable, Codable {
    case crystalPick
    case barrierArmor
    case sealStele
    case purifyingCharm
    case crystalTonic
    case skyBridge
    case runeAxe
    case emberWand
    case windBoots
    case crystalSickle
    case timberSaw
    case barrierBuckler
    case skiff
}

struct Recipe {
    let id: RecipeID
    let name: String
    let description: String
    let cost: [ItemID: Int]
    let produces: ItemID
    let once: Bool

    static let defaults: [Recipe] = [
        Recipe(id: .crystalPick, name: "晶脉采掘器", description: "提高晶材采集量。", cost: [.emberCrystal: 2, .galeCrystal: 2], produces: .crystalPick, once: true),
        Recipe(id: .barrierArmor, name: "维度屏障铠", description: "降低畸变生物接触伤害。", cost: [.frostCrystal: 2, .verdantCrystal: 2, .distortionShard: 1], produces: .barrierArmor, once: true),
        Recipe(id: .sealStele, name: "封印石碑", description: "稳定当前位面的主要裂隙。", cost: [.distortionShard: 3, .runePage: 1], produces: .sealStele, once: false),
        Recipe(id: .runeAxe, name: "碎晶斧", description: "砍伐高大晶植获得晶纹木。", cost: [.wildGrass: 3, .distortionShard: 1], produces: .runeAxe, once: true),
        Recipe(id: .crystalSickle, name: "晶草镰", description: "拔草时额外收获晶露小草。", cost: [.wildGrass: 5, .verdantCrystal: 2], produces: .crystalSickle, once: true),
        Recipe(id: .emberWand, name: "焰核法杖", description: "强化火球威力、速度和连发频率。", cost: [.emberCrystal: 4, .voidCrystal: 1, .distortionShard: 2], produces: .emberWand, once: true),
        Recipe(id: .windBoots, name: "风纹靴", description: "提高移动速度并降低奔跑负担。", cost: [.galeCrystal: 4, .cloudCrystal: 2, .wildGrass: 2], produces: .windBoots, once: true),
        Recipe(id: .timberSaw, name: "伐晶锯", description: "砍树时额外获得晶纹木。", cost: [.crystalWood: 3, .galeCrystal: 1, .distortionShard: 2], produces: .timberSaw, once: true),
        Recipe(id: .barrierBuckler, name: "晶盾环", description: "进一步降低接触与晶弹伤害。", cost: [.crystalWood: 2, .frostCrystal: 2, .distortionShard: 2], produces: .barrierBuckler, once: true),
        Recipe(id: .skiff, name: "风纹小船", description: "允许穿越海洋并借顺风加速。", cost: [.crystalWood: 15, .galeCrystal: 3], produces: .skiff, once: true),
        Recipe(id: .purifyingCharm, name: "净化护符", description: "持续放缓污染累积。", cost: [.voidCrystal: 2, .cloudCrystal: 2, .runePage: 1], produces: .purifyingCharm, once: true),
        Recipe(id: .crystalTonic, name: "晶凝药剂", description: "恢复生命力与恒温指数。", cost: [.verdantCrystal: 2, .frostCrystal: 1], produces: .crystalTonic, once: false),
        Recipe(id: .skyBridge, name: "悬空晶桥", description: "强化冲刺并降低跨位面消耗。", cost: [.cloudCrystal: 4, .galeCrystal: 3, .voidCrystal: 1], produces: .skyBridge, once: true)
    ]
}

struct ResourceNode: Codable {
    let id: Int
    var position: CGPoint
    var amount: Int
    let maxAmount: Int
    var pulse: CGFloat
}

enum TerrainKind: String, CaseIterable, Codable {
    case lake
    case tidePool
    case ocean
    case caveMouth
    case crystalSpring

    var widthRange: ClosedRange<CGFloat> {
        switch self {
        case .lake: return 260...560
        case .tidePool: return 420...820
        case .ocean: return 920...1680
        case .caveMouth: return 180...340
        case .crystalSpring: return 150...280
        }
    }

    var heightRange: ClosedRange<CGFloat> {
        switch self {
        case .lake: return 150...330
        case .tidePool: return 220...460
        case .ocean: return 520...980
        case .caveMouth: return 120...220
        case .crystalSpring: return 100...180
        }
    }
}

struct TerrainFeature: Codable {
    let id: Int
    var position: CGPoint
    var size: CGSize
    var kind: TerrainKind
    var phase: CGFloat
}

struct Enemy: Codable {
    let id: Int
    var position: CGPoint
    var home: CGPoint
    var health: Int
    var maxHealth: Int
    var kind: EnemyKind
    var phase: CGFloat
    var shootCooldown: TimeInterval

    var isAlive: Bool { health > 0 }
}

enum EnemyKind: String, CaseIterable, Codable {
    case shardling
    case skitter
    case bulwark
    case wisp
    case reefFish

    var baseHealth: Int {
        switch self {
        case .shardling: return 3
        case .skitter: return 2
        case .bulwark: return 6
        case .wisp: return 3
        case .reefFish: return 4
        }
    }

    var speedMultiplier: CGFloat {
        switch self {
        case .shardling: return 1.0
        case .skitter: return 1.34
        case .bulwark: return 0.68
        case .wisp: return 1.18
        case .reefFish: return 1.55
        }
    }

    var sizeScale: CGFloat {
        switch self {
        case .shardling: return 1.0
        case .skitter: return 0.78
        case .bulwark: return 1.34
        case .wisp: return 0.92
        case .reefFish: return 0.86
        }
    }

    var pointCount: Int {
        switch self {
        case .shardling: return 7
        case .skitter: return 5
        case .bulwark: return 8
        case .wisp: return 6
        case .reefFish: return 5
        }
    }

    var contactDamage: Double {
        switch self {
        case .shardling: return 13
        case .skitter: return 9
        case .bulwark: return 19
        case .wisp: return 11
        case .reefFish: return 16
        }
    }

    var hitRadius: CGFloat {
        28 * sizeScale + 18
    }

    var canShoot: Bool {
        switch self {
        case .skitter, .wisp: return true
        case .shardling, .bulwark, .reefFish: return false
        }
    }

    var projectileInterval: TimeInterval {
        switch self {
        case .skitter: return 1.8
        case .wisp: return 1.25
        case .shardling, .bulwark, .reefFish: return 99
        }
    }

    var projectileSpeed: CGFloat {
        switch self {
        case .skitter: return 360
        case .wisp: return 430
        case .shardling, .bulwark, .reefFish: return 0
        }
    }

    var projectileDamage: Double {
        switch self {
        case .skitter: return 7
        case .wisp: return 9
        case .shardling, .bulwark, .reefFish: return 0
        }
    }
}

enum TallPlantKind: String, CaseIterable, Codable {
    case crystalGrass
    case dewGrass
    case prismSapling
    case prismPine
    case canopyTree
    case crystalTree
    case runeFern
    case cloudReed

    var widthScale: CGFloat {
        switch self {
        case .crystalGrass: return 0.42
        case .dewGrass: return 0.50
        case .prismSapling: return 0.48
        case .prismPine: return 0.72
        case .canopyTree: return 1.12
        case .crystalTree: return 0.92
        case .runeFern: return 0.95
        case .cloudReed: return 0.58
        }
    }

    var heightRange: ClosedRange<CGFloat> {
        switch self {
        case .crystalGrass: return 22...36
        case .dewGrass: return 28...44
        case .prismSapling: return 58...82
        case .prismPine: return 110...170
        case .canopyTree: return 130...210
        case .crystalTree: return 120...190
        case .runeFern: return 72...118
        case .cloudReed: return 92...150
        }
    }

    var isPickableGrass: Bool {
        switch self {
        case .crystalGrass, .dewGrass: return true
        case .prismSapling, .prismPine, .canopyTree, .crystalTree, .runeFern, .cloudReed: return false
        }
    }

    var isTree: Bool {
        switch self {
        case .prismPine, .canopyTree, .crystalTree: return true
        case .crystalGrass, .dewGrass, .prismSapling, .runeFern, .cloudReed: return false
        }
    }

    var grassYield: Int {
        switch self {
        case .crystalGrass: return 1
        case .dewGrass: return 2
        case .prismSapling, .prismPine, .canopyTree, .crystalTree, .runeFern, .cloudReed: return 0
        }
    }

    var woodYield: Int {
        switch self {
        case .prismPine: return 2
        case .canopyTree: return 4
        case .crystalTree: return 3
        case .crystalGrass, .dewGrass, .prismSapling, .runeFern, .cloudReed: return 0
        }
    }
}

struct TallPlant: Codable {
    let id: Int
    var position: CGPoint
    var kind: TallPlantKind
    var height: CGFloat
    var sway: CGFloat
}

struct Rift: Codable {
    var position: CGPoint
}

struct RunePage: Codable {
    var position: CGPoint
    var taken = false
}

struct AncientRelic: Codable {
    let id: Int
    var position: CGPoint
    let title: String
    let message: String
    var awakened = false

    static func defaults(for plane: Plane, planeIndex: Int, random: inout SeededRandom) -> [AncientRelic] {
        let titles = [
            "\(plane.shortName)坠落锚碑",
            "\(plane.shortName)晶脉记事",
            "\(plane.shortName)边界回声"
        ]
        let messages: [String]
        switch plane.id {
        case .ember:
            messages = ["旧锚曾用热流固定位面边缘。", "焰晶越亮，裂隙越接近失控。", "封碑需要先压住熔蚀脉搏。"]
        case .gale:
            messages = ["高原风纹记录着位面折叠方向。", "风晶能让锚点重新获得轻量。", "边界气流可通向相邻位面。"]
        case .frost:
            messages = ["凝晶冷雾会偷走行者恒温。", "雪原符文适合加固屏障。", "冰封越深，裂隙越安静也越危险。"]
        case .verdant:
            messages = ["密林根系缠住了古老锚索。", "晶露小草能稳定药剂纹路。", "腐浊污染会拖慢奔跑节奏。"]
        case .void:
            messages = ["暗符会污染尚未完成的锻造。", "净化护符的纹路藏在虚空残页里。", "虚空裂隙会吞掉附近光线。"]
        case .cloud:
            messages = ["浮空城邦依靠云晶维持高度。", "风压会撕扯位面边缘的桥。", "悬空晶桥曾连接六界巡礼路。"]
        }

        return (0..<3).map { relicIndex in
            AncientRelic(
                id: relicIndex,
                position: CGPoint(
                    x: CGFloat.random(in: 520...(GameState.worldSize.width - 520), using: &random),
                    y: CGFloat.random(in: 420...(GameState.worldSize.height - 420), using: &random)
                ),
                title: titles[relicIndex],
                message: messages[relicIndex]
            )
        }
    }
}

struct RelicInterior {
    let planeID: PlaneID
    let relicID: Int
    let title: String
    let message: String
    let returnPosition: CGPoint
    let size = CGSize(width: 2200, height: 1580)
    let entryPosition = CGPoint(x: 1100, y: 170)
    let exitPosition = CGPoint(x: 1100, y: 118)
    var echoShards: [InteriorEchoShard]
    let chambers: [InteriorChamber]

    var collectedCount: Int {
        echoShards.filter(\.collected).count
    }

    var isComplete: Bool {
        collectedCount == echoShards.count
    }

    init(plane: Plane, relic: AncientRelic, returnPosition: CGPoint) {
        planeID = plane.id
        relicID = relic.id
        title = relic.title
        message = relic.message
        self.returnPosition = returnPosition
        echoShards = [
            InteriorEchoShard(id: 0, position: CGPoint(x: 520, y: 1110), label: "左翼锚印"),
            InteriorEchoShard(id: 1, position: CGPoint(x: 1680, y: 1120), label: "右翼锚印"),
            InteriorEchoShard(id: 2, position: CGPoint(x: 1100, y: 1390), label: "核心锚印")
        ]
        chambers = [
            InteriorChamber(center: CGPoint(x: 1100, y: 380), size: CGSize(width: 720, height: 360), title: "入碑回廊"),
            InteriorChamber(center: CGPoint(x: 520, y: 1040), size: CGSize(width: 560, height: 390), title: "左翼记忆室"),
            InteriorChamber(center: CGPoint(x: 1680, y: 1040), size: CGSize(width: 560, height: 390), title: "右翼记忆室"),
            InteriorChamber(center: CGPoint(x: 1100, y: 1300), size: CGSize(width: 620, height: 330), title: "核心铭刻厅")
        ]
    }
}

struct InteriorEchoShard: Codable {
    let id: Int
    var position: CGPoint
    let label: String
    var collected = false
}

struct InteriorChamber {
    var center: CGPoint
    var size: CGSize
    let title: String
}

struct Particle {
    var position: CGPoint
    var velocity: CGVector
    var size: CGFloat
    var life: TimeInterval
    var color: NSColor
    var spin: CGFloat
}

struct Fireball {
    var position: CGPoint
    var velocity: CGVector
    var planeID: PlaneID
    var damage: Int
    var life: TimeInterval
    var radius: CGFloat = 16
    var phase: CGFloat = CGFloat.random(in: 0...(CGFloat.pi * 2))
}

struct EnemyProjectile {
    var position: CGPoint
    var velocity: CGVector
    var planeID: PlaneID
    var damage: Double
    var life: TimeInterval
    var radius: CGFloat = 10
    var phase: CGFloat = CGFloat.random(in: 0...(CGFloat.pi * 2))
}
