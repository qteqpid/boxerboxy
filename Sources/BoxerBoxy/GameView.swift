import AppKit

final class GameView: NSView {
    private let world = GameState.worldSize
    private var displayLink: Timer?
    private var lastFrame = CACurrentMediaTime()
    private var pressedKeys = Set<UInt16>()
    private var state: GameState
    private var onReturnToMenu: (() -> Void)?
    private var planeTransitionCooldown = 0.0
    private var isMouseFiring = false
    private var mouseWorldTarget = CGPoint(x: GameState.worldSize.width / 2 + 1, y: GameState.worldSize.height / 2)

    private static let groundSkew: CGFloat = -0.18
    private static let groundScaleY: CGFloat = 0.48

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        state = GameState()
        super.init(frame: frameRect)
        configureView()
    }

    init(frame frameRect: NSRect, state initialState: GameState, onReturnToMenu: (() -> Void)? = nil) {
        state = initialState
        self.onReturnToMenu = onReturnToMenu
        super.init(frame: frameRect)
        configureView()
        updateCamera()
    }

    private func configureView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        startLoop()
    }

    required init?(coder: NSCoder) {
        state = GameState()
        super.init(coder: coder)
        configureView()
    }

    deinit {
        displayLink?.invalidate()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        if !event.isARepeat {
            pressedKeys.insert(event.keyCode)
            if event.keyCode == KeyCode.space {
                triggerJump()
                return
            }
            handleCommand(event)
        }
    }

    override func keyUp(with event: NSEvent) {
        pressedKeys.remove(event.keyCode)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if state.activeRelicInterior != nil {
            isMouseFiring = false
            return
        }
        let local = convert(event.locationInWindow, from: nil)
        if handleForgePanelClick(at: local) {
            isMouseFiring = false
            return
        }
        if gatherButtonFrame.contains(local) {
            isMouseFiring = false
            pullNearestGrass()
            return
        }
        isMouseFiring = true
        mouseWorldTarget = worldPoint(for: event)
        fireballToward(mouseWorldTarget)
    }

    override func mouseDragged(with event: NSEvent) {
        guard state.activeRelicInterior == nil else { return }
        mouseWorldTarget = worldPoint(for: event)
    }

    override func mouseUp(with event: NSEvent) {
        guard state.activeRelicInterior == nil else {
            isMouseFiring = false
            return
        }
        mouseWorldTarget = worldPoint(for: event)
        isMouseFiring = false
    }

    override func rightMouseDown(with event: NSEvent) {
        mouseDown(with: event)
    }

    override func rightMouseDragged(with event: NSEvent) {
        mouseDragged(with: event)
    }

    override func rightMouseUp(with event: NSEvent) {
        mouseUp(with: event)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let renderer = GameRenderer(context: context, rect: bounds, state: state, world: world)
        renderer.draw()
    }

    private func startLoop() {
        displayLink = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let delta = min(0.033, now - lastFrame)
        lastFrame = now
        update(delta: delta)
        needsDisplay = true
    }

    private func update(delta: TimeInterval) {
        if state.activeRelicInterior != nil {
            updateRelicInterior(delta: delta)
            return
        }

        var direction = CGVector.zero
        if pressedKeys.contains(KeyCode.w) || pressedKeys.contains(KeyCode.up) { direction.dy += 1 }
        if pressedKeys.contains(KeyCode.s) || pressedKeys.contains(KeyCode.down) { direction.dy -= 1 }
        if pressedKeys.contains(KeyCode.a) || pressedKeys.contains(KeyCode.left) { direction.dx -= 1 }
        if pressedKeys.contains(KeyCode.d) || pressedKeys.contains(KeyCode.right) { direction.dx += 1 }

        let playerWasMoving = direction.dx != 0 || direction.dy != 0
        state.player.isWalking = playerWasMoving
        if playerWasMoving {
            let length = max(1, hypot(direction.dx, direction.dy))
            direction.dx /= length
            direction.dy /= length
            state.player.moveDirection = direction
            state.player.lastAimDirection = direction
            let sprinting = pressedKeys.contains(KeyCode.shift) && state.player.stamina > 3
            let speedBonus: CGFloat = state.craftedItems.contains(.windBoots) ? 1.18 : 1.0
            let oceanEffect = oceanNavigationEffect(for: direction)
            let speed: CGFloat = (sprinting ? 292 : 190) * speedBonus * oceanEffect.speedMultiplier
            state.player.position.x = clamp(state.player.position.x + direction.dx * speed * delta, 36, world.width - 36)
            state.player.position.y = clamp(state.player.position.y + direction.dy * speed * delta, 36, world.height - 36)
            let staminaCost = (sprinting ? 13 : 5) * (state.craftedItems.contains(.windBoots) ? 0.76 : 1) * oceanEffect.staminaMultiplier
            state.player.stamina -= staminaCost * delta
        } else {
            state.player.moveDirection = .zero
            state.player.stamina += 15 * delta
        }

        updateOceanHazard(delta: delta)

        if state.player.stamina < 0 {
            state.player.vitality += state.player.stamina * 0.08 * delta
        }
        state.player.stamina = clamp(state.player.stamina, 0, 100)

        let plane = state.currentPlane
        let sealed = state.sealedPlanes.contains(plane.id)
        let pollutionRate = sealed ? -4 : plane.hazard * 10
        let charmFactor = state.craftedItems.contains(.purifyingCharm) ? 0.45 : 1
        state.player.pollution = clamp(state.player.pollution + pollutionRate * charmFactor * delta, 0, 100)

        if plane.id == .frost && !sealed {
            state.player.thermal -= (state.craftedItems.contains(.barrierArmor) ? 2.4 : 5.8) * delta
        } else {
            state.player.thermal += 4.2 * delta
        }
        state.player.thermal = clamp(state.player.thermal, 0, 100)

        if state.player.thermal < 18 {
            state.player.vitality -= (18 - state.player.thermal) * 0.03 * delta
        }
        if state.player.pollution > 72 {
            state.player.vitality -= (state.player.pollution - 72) * 0.018 * delta
        }

        state.player.hitCooldown = max(0, state.player.hitCooldown - delta)
        state.player.harvestCooldown = max(0, state.player.harvestCooldown - delta)
        state.player.attackCooldown = max(0, state.player.attackCooldown - delta)
        state.player.dashCooldown = max(0, state.player.dashCooldown - delta)
        updateJump(delta: delta)
        planeTransitionCooldown = max(0, planeTransitionCooldown - delta)
        state.planeFlipProgress = max(0, state.planeFlipProgress - delta * 2.6)
        if isMouseFiring, state.player.attackCooldown <= 0 {
            fireballToward(mouseWorldTarget)
        }
        updateCoreSanctuary(delta: delta)
        updateResourceRegrowth(delta: delta)
        checkPlaneBoundaryTransition()
        updateEnemies(delta: delta)
        updateFireballs(delta: delta)
        updateEnemyProjectiles(delta: delta)
        updatePages()
        updateParticles(delta: delta)
        updateCamera()
        checkCoreCompletion()

        if state.player.vitality <= 0 {
            collapseToCore()
        }
    }

    private func triggerJump() {
        guard state.player.jumpHeight <= 0.5, state.player.stamina >= 8 else { return }
        state.player.jumpVelocity = state.craftedItems.contains(.windBoots) ? 560 : 500
        state.player.stamina = clamp(state.player.stamina - 8, 0, 100)
        addParticles(at: state.player.position, color: state.currentPlane.palette.light, count: 8)
    }

    private func updateJump(delta: TimeInterval) {
        guard state.player.jumpHeight > 0 || state.player.jumpVelocity > 0 else { return }
        state.player.jumpVelocity -= 980 * CGFloat(delta)
        state.player.jumpHeight += state.player.jumpVelocity * CGFloat(delta)
        if state.player.jumpHeight <= 0 {
            state.player.jumpHeight = 0
            state.player.jumpVelocity = 0
            addParticles(at: state.player.position, color: state.currentPlane.palette.glow, count: 6)
        }
    }

    private func updateEnemies(delta: TimeInterval) {
        let plane = state.currentPlane
        guard let rift = state.rifts[plane.id] else { return }
        for index in state.enemies[plane.id, default: []].indices {
            guard state.enemies[plane.id]?[index].isAlive == true else { continue }
            var enemy = state.enemies[plane.id]![index]
            enemy.phase += delta * 2
            enemy.shootCooldown = max(0, enemy.shootCooldown - delta)
            let playerPosition = state.player.position
            let playerDistance = enemy.position.distance(to: playerPosition)
            let homeDistance = enemy.position.distance(to: enemy.home)
            let riftDistance = enemy.position.distance(to: rift.position)
            var target = CGPoint(
                x: enemy.home.x + cos(enemy.phase) * 48,
                y: enemy.home.y + sin(enemy.phase * 0.8) * 42
            )

            if enemy.kind == .reefFish {
                let playerInOcean = oceanFeature(containing: playerPosition) != nil
                if playerDistance < (playerInOcean ? 520 : 260) {
                    target = playerPosition
                } else {
                    target = CGPoint(
                        x: enemy.home.x + cos(enemy.phase * 0.8) * 150,
                        y: enemy.home.y + sin(enemy.phase * 1.15) * 92
                    )
                }
            } else if plane.id == .frost {
                if playerDistance < 145 && homeDistance < 220 { target = playerPosition }
            } else if plane.id == .cloud {
                if playerDistance < 180 && state.player.pollution > 32 {
                    target = CGPoint(x: playerPosition.x + sin(enemy.phase) * 70, y: playerPosition.y)
                }
            } else if plane.id == .void {
                if playerDistance < 230 || riftDistance < 260 { target = playerPosition }
            } else if playerDistance < 170 {
                target = playerPosition
            }

            let vector = CGVector(dx: target.x - enemy.position.x, dy: target.y - enemy.position.y)
            let length = max(1, hypot(vector.dx, vector.dy))
            let speed: CGFloat = (plane.id == .cloud ? 126 : 96) * enemy.kind.speedMultiplier
            enemy.position.x += vector.dx / length * speed * delta
            enemy.position.y += vector.dy / length * speed * delta

            if playerDistance < 35 && state.player.hitCooldown <= 0 {
                let rawDamage = enemy.kind.contactDamage
                let damage = reducedDamage(rawDamage)
                state.player.vitality -= damage
                state.player.hitCooldown = 0.75
                addParticles(at: state.player.position, color: plane.palette.light, count: 18)
                showToast("维度屏障承受畸变冲击，生命力 -\(Int(damage))")
            }

            if enemy.kind.canShoot && playerDistance < 520 && enemy.shootCooldown <= 0 {
                let aim = CGVector(
                    dx: playerPosition.x - enemy.position.x,
                    dy: playerPosition.y - enemy.position.y
                ).normalized
                state.enemyProjectiles.append(EnemyProjectile(
                    position: CGPoint(
                        x: enemy.position.x + aim.dx * enemy.kind.hitRadius * 0.62,
                        y: enemy.position.y + aim.dy * enemy.kind.hitRadius * 0.62
                    ),
                    velocity: CGVector(
                        dx: aim.dx * enemy.kind.projectileSpeed,
                        dy: aim.dy * enemy.kind.projectileSpeed
                    ),
                    planeID: plane.id,
                    damage: enemy.kind.projectileDamage,
                    life: 2.1
                ))
                enemy.shootCooldown = enemy.kind.projectileInterval + TimeInterval.random(in: -0.25...0.35)
                addParticles(at: enemy.position, color: plane.palette.glow, count: 7)
            }

            state.enemies[plane.id]![index] = enemy
        }
    }

    private func updatePages() {
        let plane = state.currentPlane
        guard var page = state.pages[plane.id], !page.taken else { return }
        if page.position.distance(to: state.player.position) < 42 {
            page.taken = true
            state.pages[plane.id] = page
            state.inventory[.runePage, default: 0] += 1
            if plane.id == .void { state.unlockedRecipes.insert(.purifyingCharm) }
            if plane.id == .cloud { state.unlockedRecipes.insert(.skyBridge) }
            if plane.id == .frost || plane.id == .verdant { state.unlockedRecipes.insert(.barrierArmor) }
            showToast("拾得\(plane.shortName)符文残页，新的锻造纹路已显现")
        }
    }

    private func updateParticles(delta: TimeInterval) {
        state.particles = state.particles.compactMap { particle in
            var copy = particle
            copy.life -= delta
            copy.position.x += copy.velocity.dx * delta
            copy.position.y += copy.velocity.dy * delta
            copy.size *= 0.985
            return copy.life > 0 ? copy : nil
        }

        if CACurrentMediaTime() > state.toastUntil {
            state.toast = nil
        }
        if CACurrentMediaTime() > state.codexNoteUntil {
            state.codexNote = nil
        }
    }

    private func updateCamera() {
        let activeWorld = state.currentWorldSize
        state.camera.x = clamp(state.player.position.x - bounds.width / 2, 0, max(0, activeWorld.width - bounds.width))
        state.camera.y = clamp(state.player.position.y - bounds.height / 2, 0, max(0, activeWorld.height - bounds.height))
    }

    private func handleCommand(_ event: NSEvent) {
        if state.activeRelicInterior != nil {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "e": interact()
            case "c": triggerDash()
            case "p": saveGame()
            case "k": returnToMenu()
            default: break
            }
            return
        }

        switch event.charactersIgnoringModifiers?.lowercased() {
        case "e": interact()
        case "c": triggerDash()
        case "p": saveGame()
        case "k": returnToMenu()
        case "f": fireballToward(mouseWorldTarget)
        case "b": placeSeal()
        case "q": shiftPlane(-1)
        case "r": shiftPlane(1)
        case "1": useTonic()
        case "2": craft(.crystalPick)
        case "3": craft(.sealStele)
        case "4": craft(.crystalTonic)
        case "5": craft(.barrierArmor)
        case "6": craft(.purifyingCharm)
        case "7": craft(.runeAxe)
        case "8": craft(.crystalSickle)
        case "9": craft(.emberWand)
        case "0": craft(.windBoots)
        case "-": craft(.timberSaw)
        case "=": craft(.barrierBuckler)
        case "v": craft(.skiff)
        default: break
        }
    }

    private func interact() {
        if state.activeRelicInterior != nil {
            interactInRelicInterior()
            return
        }

        let plane = state.currentPlane
        if handleNearestRelicInteraction(in: plane) {
            return
        }

        if handleNearestPlantInteraction(in: plane) {
            return
        }

        if var node = nearestResourceNode(in: plane), node.amount > 0, state.player.harvestCooldown <= 0 {
            let gain = state.craftedItems.contains(.crystalPick) ? 2 : 1
            node.amount = max(0, node.amount - gain)
            state.replaceResourceNode(node, in: plane.id)
            state.inventory[plane.resource, default: 0] += gain
            state.player.stamina = clamp(state.player.stamina - 5, 0, 100)
            state.player.harvestCooldown = 0.32
            addParticles(at: node.position, color: plane.palette.glow, count: 12)
            showToast("采得\(plane.resource.name) x\(gain)")
            return
        }

        if let edge = boundaryEdge(for: state.player.position, threshold: 92) {
            shiftPlane(edge.forwardDirection, enteringFrom: edge)
            return
        }

        if let rift = state.rifts[plane.id], !state.sealedPlanes.contains(plane.id), rift.position.distance(to: state.player.position) < 125 {
            showToast("裂隙正在振动，需要封印石碑完成稳定")
            return
        }

        if useRecoveryItemFromEmptyHandInteraction() {
            return
        }

        showToast("晶脉未响应，换个更近的位置")
    }

    private func handleNearestRelicInteraction(in plane: Plane) -> Bool {
        guard let relic = nearestRelic(in: plane, maxDistance: 126), !relic.awakened else { return false }
        enterRelicInterior(relic, in: plane)
        return true
    }

    private func enterRelicInterior(_ relic: AncientRelic, in plane: Plane) {
        addParticles(at: relic.position, color: plane.palette.light, count: 64)
        state.activeRelicInterior = RelicInterior(plane: plane, relic: relic, returnPosition: state.player.position)
        state.player.position = state.activeRelicInterior?.entryPosition ?? state.player.position
        state.player.jumpHeight = 0
        state.player.jumpVelocity = 0
        state.fireballs.removeAll()
        state.enemyProjectiles.removeAll()
        state.planeFlipProgress = 1
        isMouseFiring = false
        addParticles(at: state.player.position, color: plane.palette.light, count: 56)
        updateCamera()
        showToast("锚碑展开内部空间：探索全部锚印后从入口离开")
    }

    private func updateRelicInterior(delta: TimeInterval) {
        guard let interior = state.activeRelicInterior else { return }

        var direction = CGVector.zero
        if pressedKeys.contains(KeyCode.w) || pressedKeys.contains(KeyCode.up) { direction.dy += 1 }
        if pressedKeys.contains(KeyCode.s) || pressedKeys.contains(KeyCode.down) { direction.dy -= 1 }
        if pressedKeys.contains(KeyCode.a) || pressedKeys.contains(KeyCode.left) { direction.dx -= 1 }
        if pressedKeys.contains(KeyCode.d) || pressedKeys.contains(KeyCode.right) { direction.dx += 1 }

        let playerWasMoving = direction.dx != 0 || direction.dy != 0
        state.player.isWalking = playerWasMoving
        if playerWasMoving {
            let length = max(1, hypot(direction.dx, direction.dy))
            direction.dx /= length
            direction.dy /= length
            state.player.moveDirection = direction
            state.player.lastAimDirection = direction
            let speed: CGFloat = pressedKeys.contains(KeyCode.shift) && state.player.stamina > 3 ? 248 : 176
            state.player.position.x = clamp(state.player.position.x + direction.dx * speed * delta, 56, interior.size.width - 56)
            state.player.position.y = clamp(state.player.position.y + direction.dy * speed * delta, 56, interior.size.height - 56)
            state.player.stamina -= (pressedKeys.contains(KeyCode.shift) ? 9 : 3) * delta
        } else {
            state.player.moveDirection = .zero
            state.player.stamina += 16 * delta
        }

        state.player.stamina = clamp(state.player.stamina, 0, 100)
        state.player.hitCooldown = max(0, state.player.hitCooldown - delta)
        state.player.harvestCooldown = max(0, state.player.harvestCooldown - delta)
        state.player.attackCooldown = max(0, state.player.attackCooldown - delta)
        state.player.dashCooldown = max(0, state.player.dashCooldown - delta)
        updateJump(delta: delta)
        state.planeFlipProgress = max(0, state.planeFlipProgress - delta * 2.6)
        updateParticles(delta: delta)
        updateCamera()
    }

    private func interactInRelicInterior() {
        guard var interior = state.activeRelicInterior else { return }
        if let index = interior.echoShards.indices.first(where: {
            !interior.echoShards[$0].collected &&
                interior.echoShards[$0].position.distance(to: state.player.position) <= 76
        }) {
            let shard = interior.echoShards[index]
            interior.echoShards[index].collected = true
            state.activeRelicInterior = interior
            state.inventory[.anchorEcho, default: 0] += 1
            addParticles(at: shard.position, color: state.currentPlane.palette.light, count: 36)
            showToast("拾取\(shard.label)，锚印回响 +1")
            return
        }

        if state.player.position.distance(to: interior.exitPosition) <= 96 {
            if interior.isComplete {
                completeRelicInterior(interior)
            } else {
                showToast("内部锚印尚未完整：\(interior.collectedCount) / \(interior.echoShards.count)")
            }
            return
        }

        showToast("遗迹内部回声很弱，继续寻找发光锚印")
    }

    private func completeRelicInterior(_ interior: RelicInterior) {
        let plane = state.currentPlane
        if let index = state.relics[interior.planeID]?.firstIndex(where: { $0.id == interior.relicID }) {
            state.relics[interior.planeID]?[index].awakened = true
        }
        state.player.position = interior.returnPosition
        state.activeRelicInterior = nil
        state.inventory[plane.resource, default: 0] += 2
        state.player.pollution = max(0, state.player.pollution - 10)
        state.player.thermal = clamp(state.player.thermal + 5, 0, 100)
        state.codexNote = "\(interior.title)：\(interior.message)"
        state.codexNoteUntil = CACurrentMediaTime() + 5.2
        state.planeFlipProgress = 1
        addParticles(at: interior.returnPosition, color: plane.palette.light, count: 72)
        updateCamera()
        showToast("完成\(interior.title)内部探索，获得\(plane.resource.name) x2")
    }

    private func updateCoreSanctuary(delta: TimeInterval) {
        let center = CGPoint(x: world.width / 2, y: world.height / 2)
        let distance = state.player.position.distance(to: center)
        guard distance <= 230 else { return }

        let strength = Double(1 - distance / 230)
        let victoryBoost = state.won ? 1.8 : 1.0
        state.player.stamina = clamp(state.player.stamina + (24 + 28 * strength) * delta, 0, 100)
        state.player.vitality = clamp(state.player.vitality + 7 * strength * victoryBoost * delta, 0, 100)
        state.player.thermal = clamp(state.player.thermal + 8 * strength * victoryBoost * delta, 0, 100)
        state.player.pollution = clamp(state.player.pollution - 11 * strength * victoryBoost * delta, 0, 100)

        if Double.random(in: 0...1) < delta * 0.55 {
            addParticles(at: center, color: NSColor.white.withAlphaComponent(0.9), count: state.won ? 5 : 3)
        }
    }

    private struct OceanNavigationEffect {
        let speedMultiplier: CGFloat
        let staminaMultiplier: Double
    }

    private func oceanNavigationEffect(for direction: CGVector) -> OceanNavigationEffect {
        guard let ocean = oceanFeature(containing: state.player.position) else {
            return OceanNavigationEffect(speedMultiplier: 1, staminaMultiplier: 1)
        }

        guard state.craftedItems.contains(.skiff) else {
            return OceanNavigationEffect(speedMultiplier: 0.38, staminaMultiplier: 1.8)
        }

        let wind = oceanWindVector(for: ocean)
        let alignment = direction.dx * wind.dx + direction.dy * wind.dy
        if alignment > 0.35 {
            return OceanNavigationEffect(speedMultiplier: 1.42, staminaMultiplier: 0.68)
        }
        if alignment < -0.35 {
            return OceanNavigationEffect(speedMultiplier: 0.62, staminaMultiplier: 1.35)
        }
        return OceanNavigationEffect(speedMultiplier: 0.94, staminaMultiplier: 1.0)
    }

    private func updateOceanHazard(delta: TimeInterval) {
        guard oceanFeature(containing: state.player.position) != nil else { return }
        if state.craftedItems.contains(.skiff) {
            if Double.random(in: 0...1) < delta * 0.22 {
                addParticles(at: state.player.position, color: state.currentPlane.palette.light, count: 2)
            }
            return
        }

        if state.player.hitCooldown <= 0 {
            state.player.vitality -= 9
            state.player.hitCooldown = 1.15
            addParticles(at: state.player.position, color: state.currentPlane.palette.light, count: 16)
            showToast("海潮吞没脚步，需要风纹小船才能安全航行")
        }
    }

    private func oceanFeature(containing point: CGPoint) -> TerrainFeature? {
        state.terrainFeatures[state.currentPlane.id, default: []]
            .filter { $0.kind == .ocean }
            .first { feature in
                let dx = (point.x - feature.position.x) / max(1, feature.size.width / 2)
                let dy = (point.y - feature.position.y) / max(1, feature.size.height / 2)
                return dx * dx + dy * dy <= 1
            }
    }

    private func oceanWindVector(for feature: TerrainFeature) -> CGVector {
        CGVector(dx: cos(feature.phase), dy: sin(feature.phase)).normalized
    }

    private func updateResourceRegrowth(delta: TimeInterval) {
        state.resourceRegrowthClock += delta
        guard state.resourceRegrowthClock >= 7.5 else { return }
        state.resourceRegrowthClock = 0

        for planeID in PlaneID.allCases {
            guard var nodes = state.resourceNodes[planeID],
                  let index = nodes.indices.first(where: { nodes[$0].amount < nodes[$0].maxAmount }) else {
                continue
            }
            nodes[index].amount += 1
            state.resourceNodes[planeID] = nodes
        }
    }

    private var gatherButtonFrame: CGRect {
        CGRect(x: bounds.width - 118, y: 394, width: 92, height: 48)
    }

    private var forgePanelFrame: CGRect {
        CGRect(x: 22, y: 22, width: 310, height: 566)
    }

    private func handleForgePanelClick(at point: CGPoint) -> Bool {
        guard forgePanelFrame.contains(point) else { return false }
        for (index, recipe) in state.recipes.enumerated() {
            let row = CGRect(x: 40, y: 112 + CGFloat(index) * 34, width: 252, height: 28)
            if row.contains(point) {
                craft(recipe.id)
                return true
            }
        }
        return true
    }

    private func handleNearestPlantInteraction(in plane: Plane) -> Bool {
        guard let plant = nearestPlant(in: plane, maxDistance: 72) else { return false }
        if plant.kind.isPickableGrass {
            pullPlant(plant, in: plane)
            return true
        }
        if plant.kind.isTree {
            chopTree(plant, in: plane)
            return true
        }
        showToast("这株晶植根系太深，暂时无法采集")
        return true
    }

    private func pullNearestGrass() {
        let plane = state.currentPlane
        guard let plant = nearestPlant(in: plane, maxDistance: 86, matching: { $0.kind.isPickableGrass }) else {
            showToast("附近没有可以拔起的小草")
            return
        }
        pullPlant(plant, in: plane)
    }

    private func pullPlant(_ plant: TallPlant, in plane: Plane) {
        guard state.player.harvestCooldown <= 0 else { return }
        state.removePlant(plant, in: plane.id)
        let bonus = state.craftedItems.contains(.crystalSickle) ? 1 : 0
        let yield = plant.kind.grassYield + bonus
        state.inventory[.wildGrass, default: 0] += yield
        state.player.harvestCooldown = 0.28
        addParticles(at: plant.position, color: plane.palette.glow, count: 10)
        showToast("拔起\(ItemID.wildGrass.name) x\(yield)")
    }

    private func chopTree(_ plant: TallPlant, in plane: Plane) {
        guard state.player.harvestCooldown <= 0 else { return }
        guard state.craftedItems.contains(.runeAxe) || state.craftedItems.contains(.timberSaw) else {
            showToast("需要先用小草和畸变残片合成碎晶斧")
            return
        }
        state.removePlant(plant, in: plane.id)
        let bonus = state.craftedItems.contains(.timberSaw) ? 2 : 0
        let yield = plant.kind.woodYield + bonus
        state.inventory[.crystalWood, default: 0] += yield
        state.player.stamina = clamp(state.player.stamina - (state.craftedItems.contains(.timberSaw) ? 6 : 10), 0, 100)
        state.player.harvestCooldown = state.craftedItems.contains(.timberSaw) ? 0.42 : 0.55
        addParticles(at: plant.position, color: plane.palette.light, count: 22)
        showToast("砍得\(ItemID.crystalWood.name) x\(yield)")
    }

    private func nearestPlant(in plane: Plane, maxDistance: CGFloat, matching predicate: (TallPlant) -> Bool = { _ in true }) -> TallPlant? {
        state.plants[plane.id, default: []]
            .filter(predicate)
            .min { $0.position.distance(to: state.player.position) < $1.position.distance(to: state.player.position) }
            .flatMap { $0.position.distance(to: state.player.position) <= maxDistance ? $0 : nil }
    }

    private func nearestResourceNode(in plane: Plane) -> ResourceNode? {
        state.resourceNodes[plane.id, default: []]
            .filter { $0.amount > 0 }
            .min { $0.position.distance(to: state.player.position) < $1.position.distance(to: state.player.position) }
            .flatMap { $0.position.distance(to: state.player.position) < 54 ? $0 : nil }
    }

    private func nearestRelic(in plane: Plane, maxDistance: CGFloat) -> AncientRelic? {
        state.relics[plane.id, default: []]
            .filter { !$0.awakened }
            .min { $0.position.distance(to: state.player.position) < $1.position.distance(to: state.player.position) }
            .flatMap { $0.position.distance(to: state.player.position) <= maxDistance ? $0 : nil }
    }

    private func updateFireballs(delta: TimeInterval) {
        let plane = state.currentPlane
        var survivingFireballs: [Fireball] = []

        for var fireball in state.fireballs where fireball.planeID == plane.id {
            fireball.life -= delta
            fireball.phase += CGFloat(delta) * 9
            fireball.position.x += fireball.velocity.dx * delta
            fireball.position.y += fireball.velocity.dy * delta

            let inBounds = fireball.position.x > 24 &&
                fireball.position.x < world.width - 24 &&
                fireball.position.y > 24 &&
                fireball.position.y < world.height - 24
            guard fireball.life > 0, inBounds else {
                addParticles(at: fireball.position, color: plane.palette.base, count: 10)
                continue
            }

            if let hitIndex = state.enemies[plane.id, default: []].indices.first(where: {
                let enemy = state.enemies[plane.id]![$0]
                return enemy.isAlive && enemy.position.distance(to: fireball.position) < enemy.kind.hitRadius
            }) {
                var enemy = state.enemies[plane.id]![hitIndex]
                enemy.health -= fireball.damage
                let knockback = fireball.velocity.normalized
                enemy.position.x += knockback.dx * 24
                enemy.position.y += knockback.dy * 24
                addParticles(at: enemy.position, color: plane.palette.light, count: 26)

                if enemy.health <= 0 {
                    enemy.health = 0
                    state.inventory[.distortionShard, default: 0] += 1
                    showToast("火球击碎畸变外壳，残片可用于净化铭刻")
                }

                state.enemies[plane.id]![hitIndex] = enemy
                continue
            }

            survivingFireballs.append(fireball)
        }

        state.fireballs = survivingFireballs
    }

    private func updateEnemyProjectiles(delta: TimeInterval) {
        let plane = state.currentPlane
        var survivingProjectiles: [EnemyProjectile] = []

        for var projectile in state.enemyProjectiles where projectile.planeID == plane.id {
            projectile.life -= delta
            projectile.phase += CGFloat(delta) * 8
            projectile.position.x += projectile.velocity.dx * delta
            projectile.position.y += projectile.velocity.dy * delta

            let inBounds = projectile.position.x > 24 &&
                projectile.position.x < world.width - 24 &&
                projectile.position.y > 24 &&
                projectile.position.y < world.height - 24

            guard projectile.life > 0, inBounds else {
                addParticles(at: projectile.position, color: plane.palette.base, count: 6)
                continue
            }

            if projectile.position.distance(to: state.player.position) < 34 && state.player.hitCooldown <= 0 {
                let damage = reducedDamage(projectile.damage)
                state.player.vitality -= damage
                state.player.hitCooldown = 0.38
                addParticles(at: state.player.position, color: plane.palette.light, count: 14)
                showToast("畸变晶弹命中，生命力 -\(Int(damage))")
                continue
            }

            survivingProjectiles.append(projectile)
        }

        state.enemyProjectiles = survivingProjectiles
    }

    private func triggerDash() {
        guard state.player.dashCooldown <= 0 else { return }

        let hasSkyBridge = state.craftedItems.contains(.skyBridge)
        let staminaCost = hasSkyBridge ? 10.0 : 16.0
        guard state.player.stamina >= staminaCost else {
            showToast("体力不足，无法短距冲刺")
            return
        }

        let direction = (state.player.moveDirection.dx == 0 && state.player.moveDirection.dy == 0)
            ? state.player.lastAimDirection.normalized
            : state.player.moveDirection.normalized
        let activeWorld = state.currentWorldSize
        let distance: CGFloat = (hasSkyBridge ? 315 : 245) * (state.craftedItems.contains(.windBoots) ? 1.10 : 1.0)
        let margin: CGFloat = state.activeRelicInterior == nil ? 42 : 64
        let start = state.player.position

        state.player.position.x = clamp(start.x + direction.dx * distance, margin, activeWorld.width - margin)
        state.player.position.y = clamp(start.y + direction.dy * distance, margin, activeWorld.height - margin)
        state.player.stamina = clamp(state.player.stamina - staminaCost, 0, 100)
        state.player.dashCooldown = hasSkyBridge ? 0.48 : 0.68
        state.player.lastAimDirection = direction

        let color = hasSkyBridge ? state.currentPlane.palette.light : state.currentPlane.palette.glow
        addParticles(at: start, color: color, count: hasSkyBridge ? 26 : 18)
        addParticles(at: state.player.position, color: color, count: hasSkyBridge ? 18 : 10)
        updateCamera()
    }

    private func fireballToward(_ target: CGPoint) {
        guard state.player.stamina >= 6 else {
            showToast("躯体体力不足，火球无法凝成")
            return
        }
        guard state.player.attackCooldown <= 0 else { return }

        let hasWand = state.craftedItems.contains(.emberWand)
        state.player.stamina -= hasWand ? 4 : 6
        state.player.attackCooldown = hasWand ? 0.22 : 0.32
        let plane = state.currentPlane
        let aim = CGVector(
            dx: target.x - state.player.position.x,
            dy: target.y - state.player.position.y
        ).normalized
        state.player.lastAimDirection = aim
        let start = CGPoint(
            x: state.player.position.x + aim.dx * 34,
            y: state.player.position.y + aim.dy * 34
        )
        state.fireballs.append(Fireball(
            position: start,
            velocity: CGVector(dx: aim.dx * (hasWand ? 760 : 620), dy: aim.dy * (hasWand ? 760 : 620)),
            planeID: plane.id,
            damage: hasWand ? 4 : (state.craftedItems.contains(.crystalPick) ? 3 : 2),
            life: hasWand ? 1.7 : 1.45,
            radius: hasWand ? 19 : 16
        ))
        addParticles(at: start, color: plane.palette.light, count: 10)
    }

    private func reducedDamage(_ rawDamage: Double) -> Double {
        var damage = rawDamage
        if state.craftedItems.contains(.barrierArmor) {
            damage *= 0.58
        }
        if state.craftedItems.contains(.barrierBuckler) {
            damage *= 0.78
        }
        return damage
    }

    private func worldPoint(for event: NSEvent) -> CGPoint {
        let local = convert(event.locationInWindow, from: nil)
        return worldPoint(forScreenPoint: local)
    }

    private func worldPoint(forScreenPoint screenPoint: CGPoint) -> CGPoint {
        let activeWorld = state.currentWorldSize
        let centeredScreen = CGPoint(
            x: screenPoint.x - bounds.midX,
            y: screenPoint.y - bounds.midY
        )
        let centeredWorldY = centeredScreen.y / Self.groundScaleY
        let centeredWorldX = centeredScreen.x - Self.groundSkew * centeredWorldY
        return CGPoint(
            x: clamp(bounds.midX + centeredWorldX + state.camera.x, 0, activeWorld.width),
            y: clamp(bounds.midY + centeredWorldY + state.camera.y, 0, activeWorld.height)
        )
    }

    private func placeSeal() {
        let plane = state.currentPlane
        guard let rift = state.rifts[plane.id] else { return }
        if state.sealedPlanes.contains(plane.id) {
            showToast("\(plane.name)的主要裂隙已经稳定")
            return
        }
        guard rift.position.distance(to: state.player.position) <= 128 else {
            showToast("需要靠近主要裂隙才能放置封印石碑")
            return
        }
        guard state.inventory[.sealStele, default: 0] > 0 else {
            showToast("背包中没有封印石碑")
            return
        }

        state.inventory[.sealStele, default: 0] -= 1
        state.sealedPlanes.insert(plane.id)
        state.inventory[plane.core, default: 0] = 1
        state.collectedCores.insert(plane.core)
        state.player.pollution = max(0, state.player.pollution - 34)
        addParticles(at: rift.position, color: plane.palette.light, count: 70)
        showToast("\(plane.name)裂隙稳定，获得\(plane.core.name)")
    }

    private func checkPlaneBoundaryTransition() {
        guard planeTransitionCooldown <= 0, let edge = boundaryEdge(for: state.player.position, threshold: 38) else { return }
        shiftPlane(edge.forwardDirection, enteringFrom: edge)
    }

    private func boundaryEdge(for position: CGPoint, threshold: CGFloat) -> PlaneEdge? {
        if position.x <= threshold { return .left }
        if position.x >= world.width - threshold { return .right }
        if position.y <= threshold { return .bottom }
        if position.y >= world.height - threshold { return .top }
        return nil
    }

    private func shiftPlane(_ direction: Int, enteringFrom edge: PlaneEdge? = nil) {
        let oldPlane = state.currentPlane
        state.planeIndex = (state.planeIndex + direction + state.planes.count) % state.planes.count
        let plane = state.currentPlane
        switch edge {
        case .left:
            state.player.position.x = world.width - 104
            state.player.position.y = clamp(state.player.position.y, 104, world.height - 104)
        case .right:
            state.player.position.x = 104
            state.player.position.y = clamp(state.player.position.y, 104, world.height - 104)
        case .bottom:
            state.player.position.x = clamp(state.player.position.x, 104, world.width - 104)
            state.player.position.y = world.height - 104
        case .top:
            state.player.position.x = clamp(state.player.position.x, 104, world.width - 104)
            state.player.position.y = 104
        case .none:
            state.player.position.x = direction > 0 ? 104 : world.width - 104
            state.player.position.y = world.height - state.player.position.y
        }
        let hasSkyBridge = state.craftedItems.contains(.skyBridge)
        state.player.stamina = max(0, state.player.stamina - (hasSkyBridge ? 3 : 10))
        state.player.pollution = max(0, state.player.pollution - (hasSkyBridge ? 14 : 8))
        state.player.jumpHeight = 0
        state.player.jumpVelocity = 0
        state.fireballs.removeAll()
        state.enemyProjectiles.removeAll()
        state.planeFlipProgress = 1
        planeTransitionCooldown = 0.55
        addParticles(at: state.player.position, color: plane.palette.glow, count: 36)
        let bridgeText = hasSkyBridge ? "，晶桥护住边界落点" : ""
        showToast("\(oldPlane.shortName)气流折入\(plane.name)\(bridgeText)")
    }

    private func saveGame() {
        do {
            let url = try GameSaveStore.save(state)
            showToast("存档已写入 \(url.lastPathComponent)")
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            showToast("存档失败：\(message)")
        }
    }

    private func returnToMenu() {
        pressedKeys.removeAll()
        isMouseFiring = false
        onReturnToMenu?()
    }

    private func useTonic() {
        guard state.inventory[.crystalTonic, default: 0] > 0 else {
            showToast("背包中没有晶凝药剂")
            return
        }
        state.inventory[.crystalTonic, default: 0] -= 1
        state.player.vitality = clamp(state.player.vitality + 28, 0, 100)
        state.player.thermal = clamp(state.player.thermal + 26, 0, 100)
        showToast("晶凝药剂回流，生命力与恒温指数恢复")
    }

    private func useRecoveryItemFromEmptyHandInteraction() -> Bool {
        guard state.inventory[.crystalTonic, default: 0] > 0 else { return false }
        guard state.player.vitality < 99.5 || state.player.thermal < 99.5 else {
            showToast("状态已经稳定，暂时不需要使用晶凝药剂")
            return true
        }

        useTonic()
        return true
    }

    private func craft(_ recipeID: RecipeID) {
        guard state.unlockedRecipes.contains(recipeID), let recipe = state.recipes.first(where: { $0.id == recipeID }) else {
            showToast("符文纹路尚未显现")
            return
        }
        if recipe.once && state.craftedItems.contains(recipeID) {
            showToast("\(recipe.name)已经铭刻")
            return
        }
        guard recipe.cost.allSatisfy({ state.inventory[$0.key, default: 0] >= $0.value }) else {
            showToast("晶材纹路不足，锻造未能启动")
            return
        }

        if state.currentPlane.id == .void && state.player.pollution > 70 && !state.craftedItems.contains(.purifyingCharm) && Double.random(in: 0...1) < 0.35 {
            for (item, count) in recipe.cost {
                state.inventory[item, default: 0] -= Int(ceil(Double(count) / 2))
            }
            showToast("暗蚀符文污染扰乱锻造，部分材料碎裂")
            return
        }

        for (item, count) in recipe.cost {
            state.inventory[item, default: 0] -= count
        }

        if recipe.once {
            state.craftedItems.insert(recipeID)
            state.inventory[recipe.produces, default: 0] = 1
        } else {
            state.inventory[recipe.produces, default: 0] += 1
        }

        addParticles(at: state.player.position, color: NSColor.systemYellow, count: 24)
        showToast("\(recipe.name)锻造完成")
    }

    private func checkCoreCompletion() {
        guard !state.won, state.collectedCores.count == state.planes.count else { return }
        let center = CGPoint(x: world.width / 2, y: world.height / 2)
        if state.player.position.distance(to: center) < 98 {
            state.won = true
            state.player.vitality = 100
            state.player.thermal = 100
            state.player.stamina = 100
            state.player.pollution = 0
            addParticles(at: center, color: NSColor.white, count: 120)
            showToast("六维本源晶核归位，立方核心结界完成稳定")
        }
    }

    private func collapseToCore() {
        state.player.vitality = 72
        state.player.thermal = 70
        state.player.stamina = 76
        state.player.pollution = 22
        state.player.position = CGPoint(x: world.width / 2, y: world.height / 2)
        state.inventory[.distortionShard, default: 0] = max(0, state.inventory[.distortionShard, default: 0] - 2)
        addParticles(at: state.player.position, color: state.currentPlane.palette.base, count: 80)
        showToast("锚定行者被核心牵回，据点消耗残片稳住躯体")
    }

    private func addParticles(at position: CGPoint, color: NSColor, count: Int) {
        for _ in 0..<count {
            let angle = CGFloat.random(in: 0...(CGFloat.pi * 2))
            let speed = CGFloat.random(in: 36...168)
            state.particles.append(Particle(
                position: position,
                velocity: CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed),
                size: CGFloat.random(in: 3...8),
                life: TimeInterval.random(in: 0.45...1.15),
                color: color,
                spin: CGFloat.random(in: 0...(CGFloat.pi * 2))
            ))
        }
    }

    private func showToast(_ text: String) {
        state.toast = text
        state.toastUntil = CACurrentMediaTime() + 2.6
    }
}

private enum PlaneEdge {
    case left
    case right
    case bottom
    case top

    var forwardDirection: Int {
        switch self {
        case .right, .top: return 1
        case .left, .bottom: return -1
        }
    }
}

private enum KeyCode {
    static let a: UInt16 = 0
    static let s: UInt16 = 1
    static let d: UInt16 = 2
    static let f: UInt16 = 3
    static let w: UInt16 = 13
    static let q: UInt16 = 12
    static let r: UInt16 = 15
    static let shift: UInt16 = 56
    static let space: UInt16 = 49
    static let left: UInt16 = 123
    static let right: UInt16 = 124
    static let down: UInt16 = 125
    static let up: UInt16 = 126
}
