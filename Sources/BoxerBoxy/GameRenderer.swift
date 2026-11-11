import AppKit

struct GameRenderer {
    let context: CGContext
    let rect: CGRect
    let state: GameState
    let world: CGSize

    func draw() {
        if let interior = state.activeRelicInterior {
            drawRelicInterior(interior)
            drawHUD()
            return
        }

        drawBackground()
        context.saveGState()
        applyGroundProjection()
        context.translateBy(x: -state.camera.x, y: -state.camera.y)
        drawGroundPlane()
        drawTerrainFeatures()
        drawWorldFrame()
        context.restoreGState()

        drawDepthSortedObjects()
        drawPlaneFlipTransition()
        drawHUD()
    }

    private func applyGroundProjection() {
        context.translateBy(x: rect.midX, y: rect.midY)
        context.concatenate(Self.groundProjection)
        context.translateBy(x: -rect.midX, y: -rect.midY)
    }

    private static let groundSkew: CGFloat = -0.18
    private static let groundScaleY: CGFloat = 0.48
    private static let groundProjection = CGAffineTransform(a: 1, b: 0, c: groundSkew, d: groundScaleY, tx: 0, ty: 0)

    private struct DepthSprite {
        let depth: CGFloat
        let draw: () -> Void
    }

    private func drawBillboard(at point: CGPoint, _ body: () -> Void) {
        let screenPoint = projectedScreenPoint(point)
        context.saveGState()
        context.translateBy(x: screenPoint.x, y: screenPoint.y)
        body()
        context.restoreGState()
    }

    private func drawDepthSortedObjects() {
        let plane = state.currentPlane
        var sprites: [DepthSprite] = []

        if let rift = state.rifts[plane.id] {
            sprites.append(DepthSprite(depth: rift.position.y) {
                drawRift()
            })
        }

        state.resourceNodes[plane.id, default: []].forEach { node in
            guard node.amount > 0 else { return }
            sprites.append(DepthSprite(depth: node.position.y) {
                let size = CGFloat(15 + node.amount * 4) + sin(CGFloat(CACurrentMediaTime()) * 2 + node.pulse) * 2
                drawCrystal(at: node.position, size: size, color: plane.palette.glow, alpha: 0.92)
            })
        }

        state.plants[plane.id, default: []].forEach { plant in
            sprites.append(DepthSprite(depth: plant.position.y + plant.height * 0.12) {
                drawTallPlant(plant)
            })
        }

        if let page = state.pages[plane.id], !page.taken {
            sprites.append(DepthSprite(depth: page.position.y) {
                drawRunePage()
            })
        }

        state.relics[plane.id, default: []].forEach { relic in
            sprites.append(DepthSprite(depth: relic.position.y) {
                drawAncientRelic(relic)
            })
        }

        state.enemies[plane.id, default: []].forEach { enemy in
            guard enemy.isAlive else { return }
            sprites.append(DepthSprite(depth: enemy.position.y) {
                drawEnemy(enemy)
            })
        }

        state.fireballs
            .filter { $0.planeID == plane.id }
            .forEach { fireball in
                sprites.append(DepthSprite(depth: fireball.position.y) {
                    drawFireball(fireball)
                })
            }

        state.enemyProjectiles
            .filter { $0.planeID == plane.id }
            .forEach { projectile in
                sprites.append(DepthSprite(depth: projectile.position.y) {
                    drawEnemyProjectile(projectile)
                })
            }

        sprites.append(DepthSprite(depth: state.player.position.y) {
            drawPlayer()
        })

        state.particles.forEach { particle in
            sprites.append(DepthSprite(depth: particle.position.y) {
                drawParticle(particle)
            })
        }

        sprites
            .sorted { $0.depth > $1.depth }
            .forEach { $0.draw() }
    }

    private func drawRelicInterior(_ interior: RelicInterior) {
        drawInteriorBackground()
        context.saveGState()
        applyGroundProjection()
        context.translateBy(x: -state.camera.x, y: -state.camera.y)
        drawInteriorGround(interior)
        context.restoreGState()
        drawInteriorObjects(interior)
        drawPlaneFlipTransition()
    }

    private func drawInteriorBackground() {
        let plane = state.currentPlane
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
            NSColor.black.cgColor,
            plane.palette.dark.cgColor,
            plane.palette.base.withAlphaComponent(0.76).cgColor
        ] as CFArray, locations: [0, 0.58, 1])!
        context.drawLinearGradient(gradient, start: rect.origin, end: CGPoint(x: rect.maxX, y: rect.maxY), options: [])
    }

    private func drawInteriorGround(_ interior: RelicInterior) {
        let plane = state.currentPlane
        let worldRect = CGRect(origin: .zero, size: interior.size)
        context.setFillColor(NSColor.black.withAlphaComponent(0.42).cgColor)
        context.fill(worldRect)

        context.setStrokeColor(plane.palette.glow.withAlphaComponent(0.13).cgColor)
        context.setLineWidth(1)
        for x in stride(from: CGFloat(120), through: interior.size.width - 120, by: 120) {
            context.move(to: CGPoint(x: x, y: 80))
            context.addLine(to: CGPoint(x: x, y: interior.size.height - 80))
        }
        for y in stride(from: CGFloat(120), through: interior.size.height - 120, by: 120) {
            context.move(to: CGPoint(x: 80, y: y))
            context.addLine(to: CGPoint(x: interior.size.width - 80, y: y))
        }
        context.strokePath()

        context.setStrokeColor(plane.palette.light.withAlphaComponent(0.32).cgColor)
        context.setFillColor(plane.palette.dark.withAlphaComponent(0.58).cgColor)
        context.setLineWidth(4)
        for chamber in interior.chambers {
            let chamberRect = CGRect(
                x: chamber.center.x - chamber.size.width / 2,
                y: chamber.center.y - chamber.size.height / 2,
                width: chamber.size.width,
                height: chamber.size.height
            )
            context.fillEllipse(in: chamberRect)
            context.strokeEllipse(in: chamberRect)
        }

        context.setStrokeColor(plane.palette.glow.withAlphaComponent(0.42).cgColor)
        context.setLineWidth(18)
        context.setLineCap(.round)
        let points = [
            CGPoint(x: 1100, y: 340),
            CGPoint(x: 520, y: 1040),
            CGPoint(x: 1100, y: 1300),
            CGPoint(x: 1680, y: 1040),
            CGPoint(x: 1100, y: 340)
        ]
        for pair in zip(points, points.dropFirst()) {
            context.move(to: pair.0)
            context.addLine(to: pair.1)
            context.strokePath()
        }

        context.setStrokeColor(plane.palette.light.withAlphaComponent(0.48).cgColor)
        context.setLineWidth(5)
        context.stroke(CGRect(x: 44, y: 44, width: interior.size.width - 88, height: interior.size.height - 88))
    }

    private func drawInteriorObjects(_ interior: RelicInterior) {
        var sprites: [DepthSprite] = []
        sprites.append(DepthSprite(depth: interior.exitPosition.y) {
            drawInteriorExit(interior)
        })
        interior.echoShards.forEach { shard in
            guard !shard.collected else { return }
            sprites.append(DepthSprite(depth: shard.position.y) {
                drawInteriorEchoShard(shard)
            })
        }
        sprites.append(DepthSprite(depth: state.player.position.y) {
            drawPlayer()
        })
        state.particles.forEach { particle in
            sprites.append(DepthSprite(depth: particle.position.y) {
                drawParticle(particle)
            })
        }
        sprites
            .sorted { $0.depth > $1.depth }
            .forEach { $0.draw() }
    }

    private func projectedScreenPoint(_ point: CGPoint) -> CGPoint {
        let raw = CGPoint(x: point.x - state.camera.x, y: point.y - state.camera.y)
        let centered = CGPoint(x: raw.x - rect.midX, y: raw.y - rect.midY)
        return CGPoint(
            x: rect.midX + centered.x + Self.groundSkew * centered.y,
            y: rect.midY + Self.groundScaleY * centered.y
        )
    }

    private func projectedMoveVector(_ vector: CGVector) -> CGVector {
        let projected = CGVector(
            dx: vector.dx + Self.groundSkew * vector.dy,
            dy: Self.groundScaleY * vector.dy
        )
        let length = max(1, hypot(projected.dx, projected.dy))
        return CGVector(dx: projected.dx / length, dy: projected.dy / length)
    }

    private func drawBackground() {
        let plane = state.currentPlane
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
            plane.palette.dark.cgColor,
            NSColor(hex: "#071018").cgColor,
            plane.palette.base.cgColor
        ] as CFArray, locations: [0, 0.55, 1])!
        context.drawLinearGradient(gradient, start: rect.origin, end: CGPoint(x: rect.maxX, y: rect.maxY), options: [])
    }

    private func drawGroundPlane() {
        let plane = state.currentPlane
        context.saveGState()
        context.setFillColor(plane.palette.dark.withAlphaComponent(0.34).cgColor)
        context.fill(CGRect(origin: .zero, size: world))

        let minX = max(0, state.camera.x - rect.width * 0.8)
        let maxX = min(world.width, state.camera.x + rect.width * 1.8)
        let minY = max(0, state.camera.y - rect.height * 1.2)
        let maxY = min(world.height, state.camera.y + rect.height * 2.4)

        for y in stride(from: floor(minY / 520) * 520, through: maxY, by: 520) {
            let alpha: CGFloat = Int(y / 520).isMultiple(of: 2) ? 0.07 : 0.025
            context.setFillColor(plane.palette.base.withAlphaComponent(alpha).cgColor)
            context.fill(CGRect(x: minX - 600, y: y, width: maxX - minX + 1200, height: 260))
        }

        context.setLineWidth(1)
        context.setStrokeColor(plane.palette.glow.withAlphaComponent(0.11).cgColor)
        for x in stride(from: floor(minX / 240) * 240, through: maxX, by: 240) {
            context.move(to: CGPoint(x: x, y: minY - 400))
            context.addLine(to: CGPoint(x: x, y: maxY + 400))
            context.strokePath()
        }
        for y in stride(from: floor(minY / 240) * 240, through: maxY, by: 240) {
            context.move(to: CGPoint(x: minX - 600, y: y))
            context.addLine(to: CGPoint(x: maxX + 600, y: y))
            context.strokePath()
        }

        context.setLineWidth(2)
        context.setStrokeColor(plane.palette.light.withAlphaComponent(0.10).cgColor)
        for y in stride(from: floor(minY / 680) * 680, through: maxY, by: 680) {
            context.move(to: CGPoint(x: minX - 700, y: y + 70))
            context.addLine(to: CGPoint(x: maxX + 700, y: y - 70))
            context.strokePath()
        }

        let depthGradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
            NSColor.black.withAlphaComponent(0.18).cgColor,
            NSColor.clear.cgColor,
            NSColor.white.withAlphaComponent(0.05).cgColor
        ] as CFArray, locations: [0, 0.55, 1])!
        context.drawLinearGradient(
            depthGradient,
            start: CGPoint(x: minX, y: minY),
            end: CGPoint(x: minX, y: maxY),
            options: []
        )
        context.restoreGState()
    }

    private func drawTerrainFeatures() {
        let plane = state.currentPlane
        for feature in state.terrainFeatures[plane.id, default: []] {
            context.saveGState()
            context.translateBy(x: feature.position.x, y: feature.position.y)
            switch feature.kind {
            case .lake:
                drawWaterPatch(size: feature.size, color: plane.palette.light, phase: feature.phase, alpha: 0.34)
            case .tidePool:
                drawWaterPatch(size: feature.size, color: plane.palette.glow, phase: feature.phase, alpha: 0.26)
                context.setStrokeColor(plane.palette.light.withAlphaComponent(0.22).cgColor)
                context.setLineWidth(3)
                context.strokeEllipse(in: CGRect(x: -feature.size.width / 2, y: -feature.size.height / 2, width: feature.size.width, height: feature.size.height))
            case .ocean:
                drawWaterPatch(size: feature.size, color: NSColor(hex: "#3eb6d6"), phase: feature.phase, alpha: 0.54)
                drawOceanWind(feature)
            case .caveMouth:
                let rect = CGRect(x: -feature.size.width / 2, y: -feature.size.height / 2, width: feature.size.width, height: feature.size.height)
                context.setFillColor(NSColor.black.withAlphaComponent(0.58).cgColor)
                context.fillEllipse(in: rect)
                context.setStrokeColor(plane.palette.glow.withAlphaComponent(0.58).cgColor)
                context.setLineWidth(5)
                context.strokeEllipse(in: rect)
                for shard in -2...2 {
                    let x = CGFloat(shard) * feature.size.width * 0.18
                    drawFlatCrystal(at: CGPoint(x: x, y: feature.size.height * 0.12), size: 18, color: plane.palette.base, alpha: 0.7)
                }
            case .crystalSpring:
                drawWaterPatch(size: feature.size, color: plane.palette.glow, phase: feature.phase, alpha: 0.42)
                drawFlatCrystal(at: .zero, size: min(feature.size.width, feature.size.height) * 0.24, color: plane.palette.light, alpha: 0.72)
            }
            context.restoreGState()
        }
    }

    private func drawWaterPatch(size: CGSize, color: NSColor, phase: CGFloat, alpha: CGFloat) {
        let rect = CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
            color.withAlphaComponent(alpha * 0.35).cgColor,
            color.withAlphaComponent(alpha).cgColor,
            NSColor.white.withAlphaComponent(alpha * 0.28).cgColor
        ] as CFArray, locations: [0, 0.62, 1])!
        context.saveGState()
        context.addEllipse(in: rect)
        context.clip()
        context.drawLinearGradient(gradient, start: CGPoint(x: rect.minX, y: rect.minY), end: CGPoint(x: rect.maxX, y: rect.maxY), options: [])
        context.setStrokeColor(NSColor.white.withAlphaComponent(alpha * 0.62).cgColor)
        context.setLineWidth(2)
        for line in -2...2 {
            let y = CGFloat(line) * size.height * 0.16 + sin(CGFloat(CACurrentMediaTime()) * 2.2 + phase + CGFloat(line)) * 9
            context.beginPath()
            context.move(to: CGPoint(x: -size.width * 0.36, y: y))
            context.addCurve(
                to: CGPoint(x: size.width * 0.36, y: y),
                control1: CGPoint(x: -size.width * 0.12, y: y + 14),
                control2: CGPoint(x: size.width * 0.12, y: y - 14)
            )
            context.strokePath()
        }
        context.restoreGState()
    }

    private func drawOceanWind(_ feature: TerrainFeature) {
        let wind = CGVector(dx: cos(feature.phase), dy: sin(feature.phase)).normalized
        context.saveGState()
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.30).cgColor)
        context.setFillColor(NSColor.white.withAlphaComponent(0.34).cgColor)
        context.setLineWidth(3)
        context.setLineCap(.round)
        for offset in stride(from: -0.34, through: 0.34, by: 0.22) {
            let start = CGPoint(
                x: -wind.dx * feature.size.width * 0.18 - wind.dy * feature.size.width * offset,
                y: -wind.dy * feature.size.height * 0.18 + wind.dx * feature.size.height * offset
            )
            let end = CGPoint(
                x: start.x + wind.dx * feature.size.width * 0.22,
                y: start.y + wind.dy * feature.size.height * 0.22
            )
            context.move(to: start)
            context.addLine(to: end)
            context.strokePath()

            context.saveGState()
            context.translateBy(x: end.x, y: end.y)
            context.rotate(by: atan2(wind.dy, wind.dx))
            context.beginPath()
            context.move(to: CGPoint(x: 0, y: 0))
            context.addLine(to: CGPoint(x: -13, y: 7))
            context.addLine(to: CGPoint(x: -10, y: 0))
            context.addLine(to: CGPoint(x: -13, y: -7))
            context.closePath()
            context.fillPath()
            context.restoreGState()
        }
        context.restoreGState()
    }

    private func drawWorldFrame() {
        let plane = state.currentPlane
        context.saveGState()
        context.setStrokeColor(plane.palette.glow.cgColor)
        context.setLineWidth(5)
        context.setShadow(offset: .zero, blur: 20, color: plane.palette.glow.cgColor)
        context.stroke(CGRect(x: 42, y: 42, width: world.width - 84, height: world.height - 84))
        context.restoreGState()

        stride(from: CGFloat(80), through: world.width - 80, by: 104).forEach { x in
            drawFlatCrystal(at: CGPoint(x: x, y: 42), size: 12, color: plane.palette.light, alpha: 0.42)
            drawFlatCrystal(at: CGPoint(x: x, y: world.height - 42), size: 12, color: plane.palette.light, alpha: 0.42)
        }
        stride(from: CGFloat(90), through: world.height - 80, by: 104).forEach { y in
            drawFlatCrystal(at: CGPoint(x: 42, y: y), size: 12, color: plane.palette.light, alpha: 0.42)
            drawFlatCrystal(at: CGPoint(x: world.width - 42, y: y), size: 12, color: plane.palette.light, alpha: 0.42)
        }

        context.setFillColor(NSColor.white.withAlphaComponent(0.08).cgColor)
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.18).cgColor)
        for x in stride(from: CGFloat(170), to: world.width, by: 240) {
            for y in stride(from: CGFloat(150), to: world.height, by: 210) {
                context.beginPath()
                context.move(to: CGPoint(x: x, y: y - 16))
                context.addLine(to: CGPoint(x: x + 44, y: y))
                context.addLine(to: CGPoint(x: x, y: y + 16))
                context.addLine(to: CGPoint(x: x - 44, y: y))
                context.closePath()
                context.drawPath(using: .fillStroke)
            }
        }

        drawCoreAltar()
    }

    private func drawCoreAltar() {
        let plane = state.currentPlane
        let center = CGPoint(x: world.width / 2, y: world.height / 2)
        let coreCount = state.collectedCores.count
        let complete = coreCount == state.planes.count
        let pulse = sin(CGFloat(CACurrentMediaTime()) * (complete ? 3.2 : 1.8)) * 0.5 + 0.5
        context.saveGState()
        context.translateBy(x: center.x, y: center.y)
        context.setStrokeColor(NSColor.white.withAlphaComponent(complete ? 0.95 : 0.38).cgColor)
        context.setLineWidth(3)
        context.setShadow(offset: .zero, blur: complete ? 32 : 18, color: NSColor.white.withAlphaComponent(complete ? 0.9 : 0.42).cgColor)
        for index in 0..<6 {
            context.saveGState()
            context.rotate(by: CGFloat(index) * CGFloat.pi * 2 / 6)
            context.setFillColor((index < coreCount ? plane.palette.light : NSColor.black.withAlphaComponent(0.22)).cgColor)
            context.beginPath()
            context.move(to: CGPoint(x: 0, y: -82))
            context.addLine(to: CGPoint(x: 34, y: -34))
            context.addLine(to: CGPoint(x: 0, y: -16))
            context.addLine(to: CGPoint(x: -34, y: -34))
            context.closePath()
            context.drawPath(using: index < coreCount ? .fillStroke : .stroke)
            context.restoreGState()
        }
        context.setFillColor(plane.palette.glow.withAlphaComponent(0.42 + pulse * 0.36).cgColor)
        context.fillEllipse(in: CGRect(x: -28 - pulse * 5, y: -28 - pulse * 5, width: 56 + pulse * 10, height: 56 + pulse * 10))
        context.setFillColor(NSColor.white.withAlphaComponent(complete ? 0.95 : 0.72).cgColor)
        context.fillEllipse(in: CGRect(x: -13, y: -13, width: 26, height: 26))
        context.restoreGState()
    }

    private func drawRift() {
        let plane = state.currentPlane
        guard let rift = state.rifts[plane.id] else { return }
        let sealed = state.sealedPlanes.contains(plane.id)
        drawBillboard(at: rift.position) {
        drawGroundShadow(width: 126, height: 30, alpha: sealed ? 0.18 : 0.28)
        context.rotate(by: CGFloat(CACurrentMediaTime()).truncatingRemainder(dividingBy: 10) * (sealed ? 0.25 : 0.75))
        context.setShadow(offset: .zero, blur: sealed ? 18 : 34, color: (sealed ? plane.palette.light : plane.palette.base).cgColor)
        context.setStrokeColor((sealed ? plane.palette.light : plane.palette.glow).cgColor)
        context.setFillColor((sealed ? NSColor.white.withAlphaComponent(0.08) : NSColor.black.withAlphaComponent(0.34)).cgColor)
        for index in 0..<5 {
            context.saveGState()
            context.rotate(by: CGFloat(index) * CGFloat.pi * 2 / 5)
            context.beginPath()
            context.move(to: CGPoint(x: 0, y: -70))
            context.addLine(to: CGPoint(x: 22, y: -14))
            context.addLine(to: .zero)
            context.addLine(to: CGPoint(x: -22, y: -14))
            context.closePath()
            context.drawPath(using: .fillStroke)
            context.restoreGState()
        }
        }
    }

    private func drawResourceNodes() {
        let plane = state.currentPlane
        state.resourceNodes[plane.id, default: []].forEach { node in
            guard node.amount > 0 else { return }
            let size = CGFloat(15 + node.amount * 4) + sin(CGFloat(CACurrentMediaTime()) * 2 + node.pulse) * 2
            drawCrystal(at: node.position, size: size, color: plane.palette.glow, alpha: 0.92)
        }
    }

    private func drawRunePage() {
        let plane = state.currentPlane
        guard let page = state.pages[plane.id], !page.taken else { return }
        drawBillboard(at: page.position) {
        context.rotate(by: sin(CGFloat(CACurrentMediaTime()) * 2) * 0.08)
        context.setFillColor(NSColor(hex: "#f6de97").withAlphaComponent(0.9).cgColor)
        context.setStrokeColor(plane.palette.light.cgColor)
        context.setLineWidth(2)
        context.setShadow(offset: .zero, blur: 18, color: plane.palette.light.cgColor)
        context.beginPath()
        context.move(to: CGPoint(x: -18, y: -26))
        context.addLine(to: CGPoint(x: 16, y: -20))
        context.addLine(to: CGPoint(x: 18, y: 24))
        context.addLine(to: CGPoint(x: -16, y: 20))
        context.closePath()
        context.drawPath(using: .fillStroke)
        context.setStrokeColor(NSColor.black.withAlphaComponent(0.42).cgColor)
        for y in stride(from: CGFloat(-10), through: CGFloat(10), by: 10) {
            context.move(to: CGPoint(x: -8, y: y))
            context.addLine(to: CGPoint(x: 9, y: y + 3))
            context.strokePath()
        }
        }
    }

    private func drawInteriorExit(_ interior: RelicInterior) {
        let plane = state.currentPlane
        drawBillboard(at: interior.exitPosition) {
            let pulse = sin(CGFloat(CACurrentMediaTime()) * 3.0) * 0.5 + 0.5
            drawGroundShadow(width: 120, height: 26, alpha: 0.32)
            context.setShadow(offset: .zero, blur: interior.isComplete ? 28 : 12, color: plane.palette.light.cgColor)
            context.setStrokeColor((interior.isComplete ? plane.palette.light : NSColor.white.withAlphaComponent(0.28)).cgColor)
            context.setFillColor(plane.palette.dark.withAlphaComponent(0.64).cgColor)
            context.setLineWidth(3)
            context.strokeEllipse(in: CGRect(x: -58, y: -28, width: 116, height: 56))
            context.setLineWidth(2)
            context.strokeEllipse(in: CGRect(x: -38, y: -18, width: 76, height: 36))

            if interior.isComplete {
                context.setFillColor(plane.palette.light.withAlphaComponent(0.28 + pulse * 0.28).cgColor)
                context.fillEllipse(in: CGRect(x: -45, y: -21, width: 90, height: 42))
            }
        }
    }

    private func drawInteriorEchoShard(_ shard: InteriorEchoShard) {
        let plane = state.currentPlane
        drawBillboard(at: shard.position) {
            let pulse = sin(CGFloat(CACurrentMediaTime()) * 3.6 + CGFloat(shard.id)) * 0.5 + 0.5
            drawGroundShadow(width: 58, height: 14, alpha: 0.24)
            context.translateBy(x: 0, y: 26 + pulse * 7)
            context.setShadow(offset: .zero, blur: 22, color: plane.palette.light.cgColor)
            context.setFillColor(plane.palette.light.cgColor)
            context.setStrokeColor(NSColor.white.cgColor)
            context.setLineWidth(2)
            context.beginPath()
            context.move(to: CGPoint(x: 0, y: 24))
            context.addLine(to: CGPoint(x: 16, y: 4))
            context.addLine(to: CGPoint(x: 8, y: -22))
            context.addLine(to: CGPoint(x: -8, y: -22))
            context.addLine(to: CGPoint(x: -16, y: 4))
            context.closePath()
            context.drawPath(using: .fillStroke)

            context.setStrokeColor(plane.palette.glow.withAlphaComponent(0.52).cgColor)
            context.setLineWidth(1.4)
            context.strokeEllipse(in: CGRect(x: -30 - pulse * 6, y: -30 - pulse * 6, width: 60 + pulse * 12, height: 60 + pulse * 12))
        }
    }

    private func drawAncientRelic(_ relic: AncientRelic) {
        let plane = state.currentPlane
        drawBillboard(at: relic.position) {
            let pulse = sin(CGFloat(CACurrentMediaTime()) * 2.4 + CGFloat(relic.id)) * 0.5 + 0.5
            let activeAlpha: CGFloat = relic.awakened ? 0.42 : 0.92
            drawGroundShadow(width: 74, height: 20, alpha: relic.awakened ? 0.18 : 0.30)

            if !relic.awakened && relic.position.distance(to: state.player.position) < 180 {
                context.setAlpha(0.38 + pulse * 0.34)
                context.setStrokeColor(plane.palette.light.cgColor)
                context.setLineWidth(4)
                context.strokeEllipse(in: CGRect(x: -72 - pulse * 16, y: -48 - pulse * 8, width: 144 + pulse * 32, height: 58 + pulse * 16))
                context.setLineWidth(2)
                context.strokeEllipse(in: CGRect(x: -104 - pulse * 20, y: -62 - pulse * 10, width: 208 + pulse * 40, height: 84 + pulse * 20))
            }

            context.setAlpha(activeAlpha)
            context.setShadow(offset: .zero, blur: relic.awakened ? 8 : 24, color: plane.palette.light.cgColor)
            context.setFillColor(plane.palette.dark.blended(withFraction: 0.48, of: plane.palette.base)?.cgColor ?? plane.palette.base.cgColor)
            context.setStrokeColor(plane.palette.light.withAlphaComponent(0.82).cgColor)
            context.setLineWidth(2)
            context.beginPath()
            context.move(to: CGPoint(x: 0, y: 54))
            context.addLine(to: CGPoint(x: 25, y: 18))
            context.addLine(to: CGPoint(x: 17, y: -28))
            context.addLine(to: CGPoint(x: -17, y: -28))
            context.addLine(to: CGPoint(x: -25, y: 18))
            context.closePath()
            context.drawPath(using: .fillStroke)

            context.setStrokeColor(plane.palette.glow.withAlphaComponent(relic.awakened ? 0.36 : 0.76).cgColor)
            context.setLineWidth(2)
            context.strokeEllipse(in: CGRect(x: -36, y: -34, width: 72, height: 18))
            context.strokeEllipse(in: CGRect(x: -23, y: 8, width: 46, height: 12))

            context.setFillColor((relic.awakened ? NSColor.white : plane.palette.light).withAlphaComponent(0.85).cgColor)
            drawMapDiamond(at: CGPoint(x: 0, y: 10), radius: 7 + pulse * 2, color: relic.awakened ? NSColor.white.withAlphaComponent(0.72) : plane.palette.light)

            if !relic.awakened {
                context.setAlpha(0.36 + pulse * 0.28)
                context.setStrokeColor(plane.palette.light.cgColor)
                context.setLineWidth(1.2)
                context.strokeEllipse(in: CGRect(x: -48, y: -42, width: 96, height: 28))
            }
        }
    }

    private func drawTallPlant(_ plant: TallPlant) {
        let plane = state.currentPlane
        drawBillboard(at: plant.position) {
            let sway = sin(CGFloat(CACurrentMediaTime()) * 1.2 + plant.sway) * 5
            let width = plant.height * 0.34 * plant.kind.widthScale
            drawGroundShadow(width: width * 1.28, height: 16, alpha: 0.30)

            context.saveGState()
            context.translateBy(x: sway * 0.32, y: 0)
            context.scaleBy(x: 1, y: -1)
            context.setShadow(offset: .zero, blur: 18, color: plane.palette.glow.cgColor)
            context.setLineJoin(.round)
            context.setLineCap(.round)

            switch plant.kind {
            case .crystalGrass:
                context.setStrokeColor(plane.palette.glow.withAlphaComponent(0.82).cgColor)
                context.setLineWidth(3)
                for blade in -2...2 {
                    context.beginPath()
                    context.move(to: CGPoint(x: CGFloat(blade) * 3, y: 0))
                    context.addCurve(
                        to: CGPoint(x: CGFloat(blade) * 5 + sway * 0.24, y: -plant.height),
                        control1: CGPoint(x: CGFloat(blade) * 4, y: -plant.height * 0.28),
                        control2: CGPoint(x: CGFloat(blade) * 7, y: -plant.height * 0.70)
                    )
                    context.strokePath()
                }
            case .dewGrass:
                context.setStrokeColor(plane.palette.light.withAlphaComponent(0.86).cgColor)
                context.setLineWidth(3)
                for blade in -3...3 {
                    context.beginPath()
                    context.move(to: CGPoint(x: CGFloat(blade) * 3, y: 0))
                    context.addLine(to: CGPoint(x: CGFloat(blade) * 7 + sway * 0.18, y: -plant.height))
                    context.strokePath()
                }
                context.setFillColor(plane.palette.glow.withAlphaComponent(0.85).cgColor)
                context.fillEllipse(in: CGRect(x: -5 + sway * 0.18, y: -plant.height - 7, width: 10, height: 10))
            case .prismSapling:
                context.setStrokeColor(plane.palette.light.withAlphaComponent(0.7).cgColor)
                context.setLineWidth(5)
                context.move(to: .zero)
                context.addLine(to: CGPoint(x: sway * 0.32, y: -plant.height))
                context.strokePath()
                context.setFillColor(plane.palette.base.withAlphaComponent(0.82).cgColor)
                for leaf in 0..<3 {
                    let y = -plant.height * (0.42 + CGFloat(leaf) * 0.18)
                    let w = width * (0.8 - CGFloat(leaf) * 0.12)
                    context.beginPath()
                    context.move(to: CGPoint(x: sway * 0.3, y: y - 18))
                    context.addLine(to: CGPoint(x: w, y: y))
                    context.addLine(to: CGPoint(x: 0, y: y + 14))
                    context.addLine(to: CGPoint(x: -w, y: y))
                    context.closePath()
                    context.drawPath(using: .fillStroke)
                }
            case .prismPine:
                context.setStrokeColor(plane.palette.light.withAlphaComponent(0.62).cgColor)
                context.setFillColor(plane.palette.base.withAlphaComponent(0.84).cgColor)
                for layer in 0..<4 {
                    let y = -CGFloat(layer) * plant.height * 0.23
                    let layerWidth = width * (1.4 - CGFloat(layer) * 0.22)
                    context.beginPath()
                    context.move(to: CGPoint(x: 0, y: -plant.height * 0.72 + y))
                    context.addLine(to: CGPoint(x: layerWidth, y: -plant.height * 0.25 + y))
                    context.addLine(to: CGPoint(x: layerWidth * 0.28, y: -plant.height * 0.12 + y))
                    context.addLine(to: CGPoint(x: -layerWidth * 0.28, y: -plant.height * 0.12 + y))
                    context.addLine(to: CGPoint(x: -layerWidth, y: -plant.height * 0.25 + y))
                    context.closePath()
                    context.drawPath(using: .fillStroke)
                }
            case .canopyTree:
                context.setStrokeColor(plane.palette.dark.blended(withFraction: 0.5, of: plane.palette.base)?.cgColor ?? plane.palette.base.cgColor)
                context.setLineWidth(9)
                context.move(to: .zero)
                context.addLine(to: CGPoint(x: sway * 0.24, y: -plant.height * 0.72))
                context.strokePath()
                context.setFillColor(plane.palette.base.withAlphaComponent(0.86).cgColor)
                context.setStrokeColor(plane.palette.light.withAlphaComponent(0.58).cgColor)
                for crown in 0..<5 {
                    let angle = CGFloat(crown) * CGFloat.pi * 2 / 5
                    let cx = cos(angle) * width * 0.52 + sway * 0.32
                    let cy = -plant.height * 0.78 + sin(angle) * width * 0.20
                    context.fillEllipse(in: CGRect(x: cx - width * 0.52, y: cy - width * 0.42, width: width * 1.04, height: width * 0.84))
                    context.strokeEllipse(in: CGRect(x: cx - width * 0.52, y: cy - width * 0.42, width: width * 1.04, height: width * 0.84))
                }
            case .crystalTree:
                context.setStrokeColor(plane.palette.light.withAlphaComponent(0.66).cgColor)
                context.setLineWidth(7)
                context.move(to: .zero)
                context.addLine(to: CGPoint(x: sway * 0.22, y: -plant.height * 0.68))
                context.strokePath()
                context.setFillColor(plane.palette.glow.withAlphaComponent(0.82).cgColor)
                context.setStrokeColor(NSColor.white.withAlphaComponent(0.58).cgColor)
                for shard in -2...2 {
                    let x = CGFloat(shard) * width * 0.34 + sway * 0.30
                    let y = -plant.height * (0.56 + CGFloat(abs(shard)) * 0.06)
                    context.beginPath()
                    context.move(to: CGPoint(x: x, y: y - width * 0.86))
                    context.addLine(to: CGPoint(x: x + width * 0.38, y: y - width * 0.12))
                    context.addLine(to: CGPoint(x: x, y: y + width * 0.18))
                    context.addLine(to: CGPoint(x: x - width * 0.38, y: y - width * 0.12))
                    context.closePath()
                    context.drawPath(using: .fillStroke)
                }
            case .runeFern:
                context.setStrokeColor(plane.palette.glow.withAlphaComponent(0.78).cgColor)
                context.setLineWidth(4)
                for blade in -2...2 {
                    context.beginPath()
                    context.move(to: .zero)
                    context.addCurve(
                        to: CGPoint(x: CGFloat(blade) * width * 0.45 + sway, y: -plant.height),
                        control1: CGPoint(x: CGFloat(blade) * 10, y: -plant.height * 0.35),
                        control2: CGPoint(x: CGFloat(blade) * width * 0.52, y: -plant.height * 0.66)
                    )
                    context.strokePath()
                }
            case .cloudReed:
                context.setStrokeColor(plane.palette.light.withAlphaComponent(0.78).cgColor)
                context.setLineWidth(5)
                for reed in -1...1 {
                    let x = CGFloat(reed) * width * 0.35
                    context.move(to: CGPoint(x: x, y: 0))
                    context.addLine(to: CGPoint(x: x + sway * 0.7, y: -plant.height))
                    context.strokePath()
                    context.setFillColor(plane.palette.glow.withAlphaComponent(0.75).cgColor)
                    context.fillEllipse(in: CGRect(x: x + sway * 0.7 - 9, y: -plant.height - 12, width: 18, height: 18))
                }
            }

            context.restoreGState()
        }
    }

    private func drawEnemies() {
        let plane = state.currentPlane
        state.enemies[plane.id, default: []].forEach { enemy in
            guard enemy.isAlive else { return }
            drawEnemy(enemy)
        }
    }

    private func drawEnemy(_ enemy: Enemy) {
        let plane = state.currentPlane
        drawBillboard(at: enemy.position) {
            if enemy.kind == .reefFish {
                let scale = enemy.kind.sizeScale
                let swim = sin(enemy.phase * 2.2) * 4
                drawGroundShadow(width: 62 * scale, height: 16 * scale, alpha: 0.22)
                context.translateBy(x: swim, y: 10 + sin(enemy.phase * 1.4) * 3)
                context.rotate(by: sin(enemy.phase) * 0.16)
                context.setShadow(offset: .zero, blur: 14, color: plane.palette.light.cgColor)
                context.setFillColor(NSColor(hex: "#56d0e8").withAlphaComponent(0.92).cgColor)
                context.setStrokeColor(NSColor.white.withAlphaComponent(0.78).cgColor)
                context.setLineWidth(2)
                context.fillEllipse(in: CGRect(x: -27 * scale, y: -13 * scale, width: 54 * scale, height: 26 * scale))
                context.strokeEllipse(in: CGRect(x: -27 * scale, y: -13 * scale, width: 54 * scale, height: 26 * scale))
                context.beginPath()
                context.move(to: CGPoint(x: -27 * scale, y: 0))
                context.addLine(to: CGPoint(x: -47 * scale, y: 14 * scale))
                context.addLine(to: CGPoint(x: -40 * scale, y: 0))
                context.addLine(to: CGPoint(x: -47 * scale, y: -14 * scale))
                context.closePath()
                context.drawPath(using: .fillStroke)
                context.setFillColor(plane.palette.glow.withAlphaComponent(0.86).cgColor)
                context.beginPath()
                context.move(to: CGPoint(x: -2 * scale, y: 10 * scale))
                context.addLine(to: CGPoint(x: -14 * scale, y: 27 * scale))
                context.addLine(to: CGPoint(x: 11 * scale, y: 11 * scale))
                context.closePath()
                context.fillPath()
                context.setFillColor(NSColor.black.withAlphaComponent(0.82).cgColor)
                context.fillEllipse(in: CGRect(x: 15 * scale, y: 4 * scale, width: 5 * scale, height: 5 * scale))
                let healthRatio = CGFloat(max(0, enemy.health)) / CGFloat(max(1, enemy.maxHealth))
                context.setFillColor(NSColor.white.cgColor)
                context.fill(CGRect(x: -17 * scale, y: -24 * scale, width: 34 * scale * healthRatio, height: 4))
                return
            }

            let scale = enemy.kind.sizeScale
            drawGroundShadow(width: 52 * scale, height: 16 * scale, alpha: 0.32)
            context.rotate(by: enemy.phase * enemy.kind.rotationSpeed)
            context.setFillColor(enemy.kind.fillColor(for: plane).cgColor)
            context.setStrokeColor(plane.palette.light.cgColor)
            context.setLineWidth(2)
            context.setShadow(offset: .zero, blur: 16, color: plane.palette.glow.cgColor)
            context.beginPath()
            for index in 0..<enemy.kind.pointCount {
                let angle = CGFloat.pi * 2 / CGFloat(enemy.kind.pointCount) * CGFloat(index)
                let radius = (index.isMultiple(of: 2) ? enemy.kind.outerRadius : enemy.kind.innerRadius) * scale
                let point = CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
                index == 0 ? context.move(to: point) : context.addLine(to: point)
            }
            context.closePath()
            context.drawPath(using: .fillStroke)
            if enemy.kind == .wisp {
                context.setStrokeColor(plane.palette.glow.withAlphaComponent(0.55).cgColor)
                context.setLineWidth(1.5)
                context.strokeEllipse(in: CGRect(x: -24 * scale, y: -24 * scale, width: 48 * scale, height: 48 * scale))
            }
            context.setFillColor(plane.palette.light.cgColor)
            context.fillEllipse(in: CGRect(x: -5 * scale, y: -5 * scale, width: 10 * scale, height: 10 * scale))
            context.setFillColor(NSColor.white.cgColor)
            let healthRatio = CGFloat(max(0, enemy.health)) / CGFloat(max(1, enemy.maxHealth))
            context.fill(CGRect(x: -13 * scale, y: -4 * scale, width: 26 * scale * healthRatio, height: 4))
        }
    }

    private func drawFireball(_ fireball: Fireball) {
        let plane = state.currentPlane
        drawBillboard(at: fireball.position) {
            drawGroundShadow(width: 32, height: 9, alpha: 0.22)
            context.translateBy(x: 0, y: 14 + sin(fireball.phase) * 2)
            context.setShadow(offset: .zero, blur: 22, color: plane.palette.light.cgColor)
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
                NSColor.white.cgColor,
                plane.palette.light.cgColor,
                NSColor(hex: "#ff6e35").cgColor
            ] as CFArray, locations: [0, 0.46, 1])!
            context.drawRadialGradient(
                gradient,
                startCenter: .zero,
                startRadius: 2,
                endCenter: .zero,
                endRadius: fireball.radius,
                options: []
            )
            context.setStrokeColor(NSColor.white.withAlphaComponent(0.64).cgColor)
            context.setLineWidth(2)
            context.strokeEllipse(in: CGRect(
                x: -fireball.radius,
                y: -fireball.radius,
                width: fireball.radius * 2,
                height: fireball.radius * 2
            ))
        }
    }

    private func drawEnemyProjectile(_ projectile: EnemyProjectile) {
        let plane = state.currentPlane
        drawBillboard(at: projectile.position) {
            drawGroundShadow(width: 20, height: 6, alpha: 0.18)
            context.translateBy(x: 0, y: 12 + sin(projectile.phase) * 1.5)
            context.setShadow(offset: .zero, blur: 16, color: plane.palette.glow.cgColor)
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
                plane.palette.light.cgColor,
                plane.palette.glow.cgColor,
                plane.palette.dark.cgColor
            ] as CFArray, locations: [0, 0.52, 1])!
            context.drawRadialGradient(
                gradient,
                startCenter: .zero,
                startRadius: 1,
                endCenter: .zero,
                endRadius: projectile.radius,
                options: []
            )
            context.setStrokeColor(NSColor.white.withAlphaComponent(0.5).cgColor)
            context.setLineWidth(1.5)
            context.strokeEllipse(in: CGRect(
                x: -projectile.radius,
                y: -projectile.radius,
                width: projectile.radius * 2,
                height: projectile.radius * 2
            ))
        }
    }

    private func drawPlayer() {
        let plane = state.currentPlane
        let player = state.player
        drawBillboard(at: player.position) {
            let floatPhase = sin(CGFloat(CACurrentMediaTime()) * (player.isWalking ? 7.5 : 2.6))
            let bob = player.isWalking ? 3.4 + floatPhase * 1.6 : 2.0 + floatPhase * 1.0
            let screenMove = projectedMoveVector(player.moveDirection)
            let leanAmount: CGFloat = player.isWalking ? 1 : 0
            let jumpRatio = min(1, player.jumpHeight / 140)
            drawGroundShadow(width: 46 * (1 - jumpRatio * 0.28), height: 12 * (1 - jumpRatio * 0.24), alpha: 0.34 * (1 - jumpRatio * 0.45))
            if state.craftedItems.contains(.skiff), currentOceanFeature != nil {
                context.saveGState()
                context.translateBy(x: 0, y: 22 + player.jumpHeight * 0.28)
                context.setShadow(offset: .zero, blur: 12, color: plane.palette.light.cgColor)
                context.setFillColor(NSColor(hex: "#8a5a35").withAlphaComponent(0.88).cgColor)
                context.setStrokeColor(NSColor(hex: "#f1d37e").withAlphaComponent(0.62).cgColor)
                context.setLineWidth(2)
                context.beginPath()
                context.move(to: CGPoint(x: -38, y: -8))
                context.addLine(to: CGPoint(x: 35, y: -8))
                context.addLine(to: CGPoint(x: 24, y: -25))
                context.addLine(to: CGPoint(x: -28, y: -25))
                context.closePath()
                context.drawPath(using: .fillStroke)
                context.setStrokeColor(NSColor.white.withAlphaComponent(0.72).cgColor)
                context.move(to: CGPoint(x: 0, y: -7))
                context.addLine(to: CGPoint(x: 0, y: 30))
                context.strokePath()
                context.setFillColor(plane.palette.light.withAlphaComponent(0.64).cgColor)
                context.beginPath()
                context.move(to: CGPoint(x: 3, y: 27))
                context.addLine(to: CGPoint(x: 25, y: 7))
                context.addLine(to: CGPoint(x: 3, y: 7))
                context.closePath()
                context.fillPath()
                context.restoreGState()
            }
            context.translateBy(
                x: screenMove.dx * 7 * leanAmount,
                y: 38 + screenMove.dy * 5 * leanAmount + bob + player.jumpHeight
            )
            context.rotate(by: -screenMove.dx * 0.12 * leanAmount)

            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.setShadow(offset: .zero, blur: 16, color: plane.palette.glow.cgColor)

            let robeGradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
                NSColor.white.cgColor,
                plane.palette.light.withAlphaComponent(0.92).cgColor,
                plane.palette.base.withAlphaComponent(0.82).cgColor
            ] as CFArray, locations: [0, 0.62, 1])!

            context.setFillColor(NSColor.white.withAlphaComponent(0.98).cgColor)
            context.setStrokeColor(plane.palette.glow.cgColor)
            context.setLineWidth(3)
            context.beginPath()
            context.move(to: CGPoint(x: 0, y: -30))
            context.addLine(to: CGPoint(x: 16, y: -12))
            context.addLine(to: CGPoint(x: 20, y: 14))
            context.addLine(to: CGPoint(x: 9, y: 31))
            context.addLine(to: CGPoint(x: -9, y: 31))
            context.addLine(to: CGPoint(x: -20, y: 14))
            context.addLine(to: CGPoint(x: -16, y: -12))
            context.closePath()
            context.saveGState()
            context.clip()
            context.drawLinearGradient(robeGradient, start: CGPoint(x: 0, y: -30), end: CGPoint(x: 0, y: 28), options: [])
            context.restoreGState()
            context.strokePath()

            context.setFillColor(plane.palette.glow.cgColor)
            context.fillEllipse(in: CGRect(x: -4, y: -13, width: 8, height: 8))

            if state.craftedItems.contains(.barrierArmor) {
                context.setStrokeColor(NSColor(hex: "#9af8ff").cgColor)
            context.setLineWidth(2)
            context.strokeEllipse(in: CGRect(x: -29, y: -34, width: 58, height: 70))
            }
        }
    }

    private func drawParticles() {
        state.particles.forEach { particle in
            drawParticle(particle)
        }
    }

    private func drawParticle(_ particle: Particle) {
        drawBillboard(at: particle.position) {
            context.setAlpha(max(0, min(1, particle.life)))
            context.setFillColor(particle.color.cgColor)
            context.rotate(by: particle.spin)
            context.fill(CGRect(x: -particle.size / 2, y: -particle.size / 2, width: particle.size, height: particle.size))
        }
    }

    private struct ObjectiveTarget {
        let position: CGPoint
        let label: String
        let color: NSColor
    }

    private var objectiveTarget: ObjectiveTarget? {
        if let interior = state.activeRelicInterior {
            if let shard = interior.echoShards
                .filter({ !$0.collected })
                .min(by: { $0.position.distance(to: state.player.position) < $1.position.distance(to: state.player.position) }) {
                return ObjectiveTarget(position: shard.position, label: "锚印", color: state.currentPlane.palette.light)
            }
            return ObjectiveTarget(position: interior.exitPosition, label: "出口", color: state.currentPlane.palette.light)
        }

        let plane = state.currentPlane
        let center = CGPoint(x: world.width / 2, y: world.height / 2)
        if state.collectedCores.count == state.planes.count && !state.won {
            return ObjectiveTarget(position: center, label: "核心", color: NSColor.white)
        }

        if let rift = state.rifts[plane.id],
           !state.sealedPlanes.contains(plane.id),
           state.inventory[.sealStele, default: 0] > 0 {
            return ObjectiveTarget(position: rift.position, label: "裂隙", color: plane.palette.glow)
        }

        if let page = state.pages[plane.id], !page.taken {
            return ObjectiveTarget(position: page.position, label: "残页", color: NSColor(hex: "#f7c96a"))
        }

        if let relic = state.relics[plane.id, default: []]
            .filter({ !$0.awakened })
            .min(by: { $0.position.distance(to: state.player.position) < $1.position.distance(to: state.player.position) }) {
            return ObjectiveTarget(position: relic.position, label: "锚碑", color: NSColor(hex: "#f7c96a"))
        }

        if let rift = state.rifts[plane.id], !state.sealedPlanes.contains(plane.id) {
            return ObjectiveTarget(position: rift.position, label: "裂隙", color: plane.palette.base)
        }

        return ObjectiveTarget(position: center, label: "据点", color: NSColor.white.withAlphaComponent(0.88))
    }

    private func drawObjectiveCompass() {
        guard let target = objectiveTarget else { return }
        let targetScreen = projectedScreenPoint(target.position)
        let safeRect = rect.insetBy(dx: 150, dy: 112)
        let distance = Int(state.player.position.distance(to: target.position))

        if safeRect.contains(targetScreen) {
            drawCompassMarker(at: targetScreen, angle: nil, target: target, distance: distance)
            return
        }

        let center = CGPoint(x: rect.midX, y: rect.midY)
        let vector = CGVector(dx: targetScreen.x - center.x, dy: targetScreen.y - center.y)
        let safeX = max(1, rect.width / 2 - 96)
        let safeY = max(1, rect.height / 2 - 92)
        let scale = min(safeX / max(1, abs(vector.dx)), safeY / max(1, abs(vector.dy)))
        let point = CGPoint(x: center.x + vector.dx * scale, y: center.y + vector.dy * scale)
        drawCompassMarker(at: point, angle: atan2(vector.dy, vector.dx), target: target, distance: distance)
    }

    private func drawCompassMarker(at point: CGPoint, angle: CGFloat?, target: ObjectiveTarget, distance: Int) {
        context.saveGState()
        context.setShadow(offset: .zero, blur: 12, color: target.color.withAlphaComponent(0.55).cgColor)
        context.setStrokeColor(target.color.cgColor)
        context.setFillColor(NSColor.black.withAlphaComponent(0.62).cgColor)
        context.setLineWidth(1.5)
        context.strokeEllipse(in: CGRect(x: point.x - 16, y: point.y - 16, width: 32, height: 32))

        context.saveGState()
        context.translateBy(x: point.x, y: point.y)
        if let angle {
            context.rotate(by: angle)
            context.setFillColor(target.color.withAlphaComponent(0.92).cgColor)
            context.beginPath()
            context.move(to: CGPoint(x: 20, y: 0))
            context.addLine(to: CGPoint(x: 5, y: 8))
            context.addLine(to: CGPoint(x: 8, y: 0))
            context.addLine(to: CGPoint(x: 5, y: -8))
            context.closePath()
            context.fillPath()
        } else {
            context.setFillColor(target.color.withAlphaComponent(0.92).cgColor)
            context.fillEllipse(in: CGRect(x: -5, y: -5, width: 10, height: 10))
        }
        context.restoreGState()
        context.restoreGState()

        let label = "\(target.label) \(distance)"
        let labelFrame = CGRect(x: clamp(point.x - 52, 14, rect.width - 118), y: clamp(point.y + 18, 14, rect.height - 36), width: 104, height: 20)
        drawPanel(labelFrame, cut: 7, stroke: target.color.withAlphaComponent(0.42))
        drawText(label, in: labelFrame.insetBy(dx: 8, dy: 4), size: 10, weight: .semibold, color: .white, alignment: .center)
    }

    private func drawHUD() {
        if state.activeRelicInterior != nil {
            drawVitals()
            drawInventory()
            drawRelicInteriorHUD()
            drawObjectiveCompass()
            drawInteractionHint()
            drawToast()
            return
        }

        drawVitals()
        drawGatherButton()
        drawInventory()
        drawMainQuest()
        drawObjectiveCompass()
        drawDiscoveryNote()
        drawInteractionHint()
        drawForgePanel()
        drawCodex()
        drawToast()
    }

    private func drawPlaneFlipTransition() {
        guard state.planeFlipProgress > 0 else { return }
        let progress = CGFloat(state.planeFlipProgress)
        let fold = sin(progress * CGFloat.pi)
        context.saveGState()
        context.setFillColor(NSColor.black.withAlphaComponent(0.36 * progress).cgColor)
        context.fill(rect)

        let width = rect.width * (0.18 + 0.72 * fold)
        let panel = CGRect(x: rect.midX - width / 2, y: 0, width: width, height: rect.height)
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
            state.currentPlane.palette.light.withAlphaComponent(0.05 + 0.28 * progress).cgColor,
            state.currentPlane.palette.glow.withAlphaComponent(0.22 + 0.34 * progress).cgColor,
            state.currentPlane.palette.dark.withAlphaComponent(0.08 + 0.32 * progress).cgColor
        ] as CFArray, locations: [0, 0.5, 1])!
        context.drawLinearGradient(gradient, start: CGPoint(x: panel.minX, y: panel.midY), end: CGPoint(x: panel.maxX, y: panel.midY), options: [])
        context.setStrokeColor(state.currentPlane.palette.light.withAlphaComponent(0.76 * progress).cgColor)
        context.setLineWidth(4)
        context.move(to: CGPoint(x: panel.minX, y: 0))
        context.addLine(to: CGPoint(x: panel.minX + rect.height * 0.18, y: rect.height))
        context.move(to: CGPoint(x: panel.maxX, y: 0))
        context.addLine(to: CGPoint(x: panel.maxX - rect.height * 0.18, y: rect.height))
        context.strokePath()
        context.restoreGState()
    }

    private func drawVitals() {
        let values: [(String, Double, NSColor)] = [
            ("生命力", state.player.vitality, NSColor(hex: "#ff6e7f")),
            ("恒温", state.player.thermal, NSColor(hex: "#8be6ff")),
            ("体力", state.player.stamina, NSColor(hex: "#f7c96a")),
            ("污染", state.player.pollution, NSColor(hex: "#b983ff"))
        ]
        for (index, value) in values.enumerated() {
            let center = CGPoint(x: rect.width - 62, y: 70 + CGFloat(index) * 88)
            drawDiamond(center: center, size: 72, fillRatio: value.1 / 100, color: value.2, text: "\(value.0)\n\(Int(value.1.rounded()))")
        }
    }

    private func drawInventory() {
        let items: [ItemID] = [.emberCrystal, .galeCrystal, .frostCrystal, .verdantCrystal, .voidCrystal, .cloudCrystal, .wildGrass, .crystalWood, .distortionShard, .runePage, .anchorEcho, .sealStele, .crystalTonic, .runeAxe, .crystalSickle, .emberWand, .windBoots, .timberSaw, .barrierBuckler, .skiff]
        let slotWidth: CGFloat = 43
        let gap: CGFloat = 4
        let totalWidth = CGFloat(items.count) * slotWidth + CGFloat(items.count - 1) * gap + 28
        let x = (rect.width - totalWidth) / 2
        let y: CGFloat = rect.height - 80
        drawPanel(CGRect(x: x, y: y - 10, width: totalWidth, height: 72), cut: 18)

        for (index, item) in items.enumerated() {
            let slot = CGRect(x: x + 14 + CGFloat(index) * (slotWidth + gap), y: y, width: slotWidth, height: 54)
            drawOctagon(in: slot, color: NSColor.white.withAlphaComponent(0.08), stroke: NSColor.white.withAlphaComponent(0.18))
            drawText(item.name, in: CGRect(x: slot.minX + 3, y: slot.minY + 8, width: slot.width - 6, height: 18), size: 9, weight: .semibold, color: .white, alignment: .center)
            drawText("\(state.inventory[item, default: 0])", in: CGRect(x: slot.minX + 4, y: slot.minY + 29, width: slot.width - 8, height: 16), size: 11, weight: .regular, color: NSColor.white.withAlphaComponent(0.72), alignment: .center)
        }
    }

    private func drawGatherButton() {
        let frame = CGRect(x: rect.width - 118, y: 394, width: 92, height: 48)
        drawPanel(frame, cut: 14, stroke: state.currentPlane.palette.glow.withAlphaComponent(0.72))
        drawText("拔起", in: CGRect(x: frame.minX + 8, y: frame.minY + 8, width: frame.width - 16, height: 16), size: 13, weight: .bold, color: .white, alignment: .center)
        drawText("小草", in: CGRect(x: frame.minX + 8, y: frame.minY + 26, width: frame.width - 16, height: 14), size: 10, weight: .regular, color: NSColor.white.withAlphaComponent(0.72), alignment: .center)
    }

    private func drawMainQuest() {
        let quest = state.mainQuest
        let width = min(430, max(320, rect.width - 710))
        let frame = CGRect(x: rect.midX - width / 2, y: rect.height - 184, width: width, height: 88)
        drawPanel(frame, cut: 18, stroke: state.currentPlane.palette.light.withAlphaComponent(0.36))

        drawText(quest.title, in: CGRect(x: frame.minX + 16, y: frame.minY + 10, width: frame.width - 32, height: 18), size: 13, weight: .bold, color: .white)
        drawText(quest.objective, in: CGRect(x: frame.minX + 16, y: frame.minY + 31, width: frame.width - 32, height: 18), size: 11, weight: .semibold, color: NSColor.white.withAlphaComponent(0.78))
        drawText(quest.hint, in: CGRect(x: frame.minX + 16, y: frame.minY + 50, width: frame.width - 32, height: 16), size: 10, weight: .regular, color: NSColor.white.withAlphaComponent(0.62))

        let barFrame = CGRect(x: frame.minX + 16, y: frame.maxY - 15, width: frame.width - 118, height: 5)
        context.setFillColor(NSColor.white.withAlphaComponent(0.10).cgColor)
        context.fill(barFrame)
        context.setFillColor(state.currentPlane.palette.glow.withAlphaComponent(0.82).cgColor)
        context.fill(CGRect(x: barFrame.minX, y: barFrame.minY, width: barFrame.width * clamp(quest.progress, 0, 1), height: barFrame.height))
        drawText(quest.progressText, in: CGRect(x: barFrame.maxX + 8, y: frame.maxY - 22, width: 84, height: 16), size: 9, weight: .semibold, color: NSColor(hex: "#f7c96a"), alignment: .right)
    }

    private func drawRelicInteriorHUD() {
        guard let interior = state.activeRelicInterior else { return }
        let width = min(460, max(340, rect.width - 660))
        let frame = CGRect(x: rect.midX - width / 2, y: rect.height - 184, width: width, height: 88)
        drawPanel(frame, cut: 18, stroke: state.currentPlane.palette.light.withAlphaComponent(0.45))

        drawText("遗迹内部：\(interior.title)", in: CGRect(x: frame.minX + 16, y: frame.minY + 10, width: frame.width - 32, height: 18), size: 13, weight: .bold, color: .white)
        let objective = interior.isComplete ? "锚印已经完整，返回入口离开遗迹。" : "探索内部房间，收集全部发光锚印。"
        drawText(objective, in: CGRect(x: frame.minX + 16, y: frame.minY + 31, width: frame.width - 32, height: 18), size: 11, weight: .semibold, color: NSColor.white.withAlphaComponent(0.78))
        drawText("按 E 拾取锚印；收集完成后在入口按 E 返回外部世界。", in: CGRect(x: frame.minX + 16, y: frame.minY + 50, width: frame.width - 32, height: 16), size: 10, weight: .regular, color: NSColor.white.withAlphaComponent(0.62))

        let barFrame = CGRect(x: frame.minX + 16, y: frame.maxY - 15, width: frame.width - 118, height: 5)
        let progress = CGFloat(interior.collectedCount) / CGFloat(max(1, interior.echoShards.count))
        context.setFillColor(NSColor.white.withAlphaComponent(0.10).cgColor)
        context.fill(barFrame)
        context.setFillColor(state.currentPlane.palette.light.withAlphaComponent(0.86).cgColor)
        context.fill(CGRect(x: barFrame.minX, y: barFrame.minY, width: barFrame.width * progress, height: barFrame.height))
        drawText("锚印 \(interior.collectedCount) / \(interior.echoShards.count)", in: CGRect(x: barFrame.maxX + 8, y: frame.maxY - 22, width: 84, height: 16), size: 9, weight: .semibold, color: NSColor(hex: "#f7c96a"), alignment: .right)
    }

    private func drawDiscoveryNote() {
        guard let note = state.codexNote else { return }
        let frame = CGRect(x: rect.midX - 245, y: 88, width: 490, height: 48)
        drawPanel(frame, cut: 16, stroke: state.currentPlane.palette.light.withAlphaComponent(0.54))
        drawText("锚印记录", in: CGRect(x: frame.minX + 16, y: frame.minY + 8, width: 90, height: 16), size: 11, weight: .bold, color: state.currentPlane.palette.light)
        drawText(note, in: CGRect(x: frame.minX + 16, y: frame.minY + 25, width: frame.width - 32, height: 16), size: 10, weight: .regular, color: NSColor.white.withAlphaComponent(0.76))
    }

    private func drawInteractionHint() {
        guard let text = nearbyInteractionText else { return }
        let frame = CGRect(x: rect.midX - 138, y: 146, width: 276, height: 32)
        drawPanel(frame, cut: 12, stroke: state.currentPlane.palette.glow.withAlphaComponent(0.54))
        drawText(text, in: frame.insetBy(dx: 14, dy: 8), size: 11, weight: .semibold, color: .white, alignment: .center)
    }

    private func drawForgePanel() {
        let frame = CGRect(x: 22, y: 22, width: 310, height: 566)
        drawPanel(frame, cut: 22)
        drawText("符文锻造基座", in: CGRect(x: 40, y: 42, width: 200, height: 24), size: 17, weight: .bold, color: .white)
        let help = "P存档 C冲刺 V小船；2-7基础 8镰刀 9法杖"
        drawText(help, in: CGRect(x: 40, y: 70, width: 260, height: 34), size: 11, weight: .regular, color: NSColor.white.withAlphaComponent(0.68))

        let visibleRecipes = state.recipes
        for (index, recipe) in visibleRecipes.enumerated() {
            let y = 112 + CGFloat(index) * 34
            let affordable = recipe.cost.allSatisfy { state.inventory[$0.key, default: 0] >= $0.value }
            let unlocked = state.unlockedRecipes.contains(recipe.id)
            context.setFillColor(NSColor.white.withAlphaComponent(unlocked ? 0.08 : 0.035).cgColor)
            context.fill(CGRect(x: 40, y: y, width: 252, height: 28))
            drawText(recipe.name, in: CGRect(x: 50, y: y + 3, width: 112, height: 13), size: 10, weight: .semibold, color: unlocked ? .white : NSColor.white.withAlphaComponent(0.42))
            let cost = recipe.cost.map { "\($0.key.name)\($0.value)" }.joined(separator: " ")
            drawText(unlocked ? cost : "符文未显现", in: CGRect(x: 50, y: y + 16, width: 220, height: 11), size: 8.5, weight: .regular, color: affordable ? NSColor(hex: "#f7c96a") : NSColor.white.withAlphaComponent(0.52))
        }
    }

    private func drawCodex() {
        let topLimit = rect.height - 96
        let bottomLimit: CGFloat = 452
        let height = clamp(topLimit - bottomLimit, 72, 126)
        let width = clamp(height * (world.width / world.height), 148, 210)
        let frame = CGRect(x: rect.width - width - 38, y: topLimit - height, width: width, height: height)
        drawPanel(frame.insetBy(dx: -4, dy: -4), cut: 14, stroke: state.currentPlane.palette.glow.withAlphaComponent(0.56))
        drawMinimap(in: frame)
    }

    private func drawMinimap(in frame: CGRect) {
        let plane = state.currentPlane
        let mapRect = frame

        context.saveGState()
        context.setShadow(offset: .zero, blur: 12, color: plane.palette.glow.withAlphaComponent(0.24).cgColor)
        context.setFillColor(NSColor.black.withAlphaComponent(0.55).cgColor)
        context.fill(frame)
        context.setShadow(offset: .zero, blur: 0, color: nil)

        context.addRect(mapRect)
        context.clip()

        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
            plane.palette.dark.withAlphaComponent(0.96).cgColor,
            plane.palette.base.withAlphaComponent(0.38).cgColor,
            NSColor.black.withAlphaComponent(0.66).cgColor
        ] as CFArray, locations: [0, 0.54, 1])!
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: mapRect.minX, y: mapRect.minY),
            end: CGPoint(x: mapRect.maxX, y: mapRect.maxY),
            options: []
        )

        context.setLineWidth(0.8)
        context.setStrokeColor(plane.palette.light.withAlphaComponent(0.15).cgColor)
        for step in 1..<8 {
            let x = mapRect.minX + mapRect.width * CGFloat(step) / 8
            context.move(to: CGPoint(x: x, y: mapRect.minY))
            context.addLine(to: CGPoint(x: x, y: mapRect.maxY))
        }
        for step in 1..<4 {
            let y = mapRect.minY + mapRect.height * CGFloat(step) / 4
            context.move(to: CGPoint(x: mapRect.minX, y: y))
            context.addLine(to: CGPoint(x: mapRect.maxX, y: y))
        }
        context.strokePath()

        state.terrainFeatures[plane.id, default: []].forEach { feature in
            let point = mapPoint(feature.position, in: mapRect)
            let size = CGSize(
                width: max(5, feature.size.width / world.width * mapRect.width),
                height: max(4, feature.size.height / world.height * mapRect.height)
            )
            let alpha: CGFloat = feature.kind == .caveMouth ? 0.28 : (feature.kind == .ocean ? 0.36 : 0.18)
            let color = feature.kind == .caveMouth ? NSColor.black : (feature.kind == .ocean ? NSColor(hex: "#3eb6d6") : plane.palette.light)
            context.setFillColor(color.withAlphaComponent(alpha).cgColor)
            context.fillEllipse(in: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height))
        }

        state.plants[plane.id, default: []].prefix(60).forEach { plant in
            drawMapDot(at: mapPoint(plant.position, in: mapRect), radius: 0.7, color: plane.palette.light.withAlphaComponent(0.34))
        }

        state.resourceNodes[plane.id, default: []].forEach { node in
            guard node.amount > 0 else { return }
            drawMapDot(at: mapPoint(node.position, in: mapRect), radius: 1.4, color: plane.palette.glow.withAlphaComponent(0.72))
        }

        state.relics[plane.id, default: []].forEach { relic in
            let color = relic.awakened ? NSColor.white.withAlphaComponent(0.42) : NSColor(hex: "#f7c96a")
            drawMapDiamond(at: mapPoint(relic.position, in: mapRect), radius: relic.awakened ? 2.2 : 3.2, color: color)
        }

        state.enemies[plane.id, default: []].forEach { enemy in
            guard enemy.isAlive else { return }
            drawMapDot(at: mapPoint(enemy.position, in: mapRect), radius: 2.0, color: NSColor(hex: "#ff6e7f").withAlphaComponent(0.9))
        }

        if let page = state.pages[plane.id], !page.taken {
            drawMapDiamond(at: mapPoint(page.position, in: mapRect), radius: 3.4, color: NSColor(hex: "#f7c96a"))
        }

        if let rift = state.rifts[plane.id] {
            let color = state.sealedPlanes.contains(plane.id) ? plane.palette.light : plane.palette.base
            drawMapDiamond(at: mapPoint(rift.position, in: mapRect), radius: 4.2, color: color)
        }

        let centerPoint = mapPoint(CGPoint(x: world.width / 2, y: world.height / 2), in: mapRect)
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.62).cgColor)
        context.setLineWidth(1.1)
        context.strokeEllipse(in: CGRect(x: centerPoint.x - 4, y: centerPoint.y - 4, width: 8, height: 8))
        if let target = objectiveTarget, state.activeRelicInterior == nil {
            let playerPoint = mapPoint(state.player.position, in: mapRect)
            let targetPoint = mapPoint(target.position, in: mapRect)
            context.setStrokeColor(target.color.withAlphaComponent(0.34).cgColor)
            context.setLineWidth(1)
            context.move(to: playerPoint)
            context.addLine(to: targetPoint)
            context.strokePath()
            drawMapDiamond(at: targetPoint, radius: 4.8, color: target.color.withAlphaComponent(0.92))
        }

        let viewRect = CGRect(
            x: mapRect.minX + state.camera.x / world.width * mapRect.width,
            y: mapRect.minY + state.camera.y / world.height * mapRect.height,
            width: rect.width / world.width * mapRect.width,
            height: rect.height / world.height * mapRect.height
        )
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.52).cgColor)
        context.setLineWidth(0.8)
        context.stroke(viewRect)

        drawMapDot(at: mapPoint(state.player.position, in: mapRect), radius: 4.0, color: NSColor.white)
        context.restoreGState()

        context.setStrokeColor(plane.palette.glow.withAlphaComponent(0.62).cgColor)
        context.setLineWidth(1.2)
        context.stroke(frame)
    }

    private func drawToast() {
        guard let toast = state.toast else { return }
        let frame = CGRect(x: rect.midX - 240, y: 26, width: 480, height: 48)
        drawPanel(frame, cut: 18, stroke: state.currentPlane.palette.light)
        drawText(toast, in: frame.insetBy(dx: 18, dy: 14), size: 14, weight: .semibold, color: .white, alignment: .center)
    }

    private func drawCrystal(at point: CGPoint, size: CGFloat, color: NSColor, alpha: CGFloat) {
        drawBillboard(at: point) {
        drawGroundShadow(width: size * 1.35, height: max(8, size * 0.38), alpha: 0.22)
        context.setAlpha(alpha)
        context.setFillColor(color.cgColor)
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.65).cgColor)
        context.setLineWidth(1.5)
        context.setShadow(offset: .zero, blur: 15, color: color.cgColor)
        context.beginPath()
        context.move(to: CGPoint(x: 0, y: -size))
        context.addLine(to: CGPoint(x: size * 0.78, y: -size * 0.18))
        context.addLine(to: CGPoint(x: size * 0.48, y: size))
        context.addLine(to: CGPoint(x: -size * 0.48, y: size))
        context.addLine(to: CGPoint(x: -size * 0.78, y: -size * 0.18))
        context.closePath()
        context.drawPath(using: .fillStroke)
        }
    }

    private func drawFlatCrystal(at point: CGPoint, size: CGFloat, color: NSColor, alpha: CGFloat) {
        context.saveGState()
        context.translateBy(x: point.x, y: point.y)
        context.setAlpha(alpha)
        context.setFillColor(color.cgColor)
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.65).cgColor)
        context.setLineWidth(1.5)
        context.setShadow(offset: .zero, blur: 15, color: color.cgColor)
        context.beginPath()
        context.move(to: CGPoint(x: 0, y: -size))
        context.addLine(to: CGPoint(x: size * 0.78, y: -size * 0.18))
        context.addLine(to: CGPoint(x: size * 0.48, y: size))
        context.addLine(to: CGPoint(x: -size * 0.48, y: size))
        context.addLine(to: CGPoint(x: -size * 0.78, y: -size * 0.18))
        context.closePath()
        context.drawPath(using: .fillStroke)
        context.restoreGState()
    }

    private func drawGroundShadow(width: CGFloat, height: CGFloat, alpha: CGFloat) {
        context.saveGState()
        context.setFillColor(NSColor.black.withAlphaComponent(alpha).cgColor)
        context.fillEllipse(in: CGRect(x: -width / 2, y: -height / 2, width: width, height: height))
        context.restoreGState()
    }

    private func drawDiamond(center: CGPoint, size: CGFloat, fillRatio: Double, color: NSColor, text: String) {
        context.saveGState()
        context.translateBy(x: center.x, y: center.y)
        context.rotate(by: CGFloat.pi / 4)
        let rect = CGRect(x: -size / 2, y: -size / 2, width: size, height: size)
        context.setFillColor(NSColor.black.withAlphaComponent(0.48).cgColor)
        context.fill(rect)
        context.setFillColor(color.withAlphaComponent(0.78).cgColor)
        context.fill(CGRect(x: rect.minX, y: rect.maxY - rect.height * CGFloat(fillRatio), width: rect.width, height: rect.height * CGFloat(fillRatio)))
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.22).cgColor)
        context.setLineWidth(1)
        context.stroke(rect)
        context.restoreGState()
        drawText(text, in: CGRect(x: center.x - 34, y: center.y - 18, width: 68, height: 36), size: 11, weight: .bold, color: .white, alignment: .center)
    }

    private func drawPanel(_ frame: CGRect, cut: CGFloat, stroke: NSColor = NSColor.white.withAlphaComponent(0.22)) {
        context.saveGState()
        context.setFillColor(NSColor.black.withAlphaComponent(0.58).cgColor)
        context.setStrokeColor(stroke.cgColor)
        context.setLineWidth(1)
        context.beginPath()
        context.move(to: CGPoint(x: frame.minX + cut, y: frame.minY))
        context.addLine(to: CGPoint(x: frame.maxX, y: frame.minY))
        context.addLine(to: CGPoint(x: frame.maxX, y: frame.maxY - cut))
        context.addLine(to: CGPoint(x: frame.maxX - cut, y: frame.maxY))
        context.addLine(to: CGPoint(x: frame.minX, y: frame.maxY))
        context.addLine(to: CGPoint(x: frame.minX, y: frame.minY + cut))
        context.closePath()
        context.drawPath(using: .fillStroke)
        context.restoreGState()
    }

    private func drawOctagon(in frame: CGRect, color: NSColor, stroke: NSColor) {
        let cut = min(frame.width, frame.height) * 0.22
        context.setFillColor(color.cgColor)
        context.setStrokeColor(stroke.cgColor)
        context.beginPath()
        context.move(to: CGPoint(x: frame.minX + cut, y: frame.minY))
        context.addLine(to: CGPoint(x: frame.maxX - cut, y: frame.minY))
        context.addLine(to: CGPoint(x: frame.maxX, y: frame.minY + cut))
        context.addLine(to: CGPoint(x: frame.maxX, y: frame.maxY - cut))
        context.addLine(to: CGPoint(x: frame.maxX - cut, y: frame.maxY))
        context.addLine(to: CGPoint(x: frame.minX + cut, y: frame.maxY))
        context.addLine(to: CGPoint(x: frame.minX, y: frame.maxY - cut))
        context.addLine(to: CGPoint(x: frame.minX, y: frame.minY + cut))
        context.closePath()
        context.drawPath(using: .fillStroke)
    }

    private var currentOceanFeature: TerrainFeature? {
        oceanFeature(containing: state.player.position)
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

    private var nearbyInteractionText: String? {
        if let interior = state.activeRelicInterior {
            if let shard = interior.echoShards
                .filter({ !$0.collected })
                .min(by: { $0.position.distance(to: state.player.position) < $1.position.distance(to: state.player.position) }),
               shard.position.distance(to: state.player.position) <= 86 {
                return "E 拾取 \(shard.label)"
            }

            if state.player.position.distance(to: interior.exitPosition) <= 106 {
                return interior.isComplete ? "E 离开遗迹内部" : "还需收集锚印 \(interior.collectedCount) / \(interior.echoShards.count)"
            }

            return nil
        }

        let plane = state.currentPlane
        let playerPosition = state.player.position

        if let ocean = oceanFeature(containing: playerPosition) {
            let wind = CGVector(dx: cos(ocean.phase), dy: sin(ocean.phase)).normalized
            let alignment = state.player.moveDirection.dx * wind.dx + state.player.moveDirection.dy * wind.dy
            if !state.craftedItems.contains(.skiff) {
                return "海洋危险：需要风纹小船"
            }
            if alignment > 0.35 {
                return "顺风航行"
            }
            if alignment < -0.35 {
                return "逆风航行"
            }
            return "海面横风"
        }

        if let relic = state.relics[plane.id, default: []]
            .filter({ !$0.awakened })
            .min(by: { $0.position.distance(to: playerPosition) < $1.position.distance(to: playerPosition) }),
           relic.position.distance(to: playerPosition) <= 126 {
            return "E 进入 \(relic.title)"
        }

        if let plant = state.plants[plane.id, default: []]
            .min(by: { $0.position.distance(to: playerPosition) < $1.position.distance(to: playerPosition) }),
           plant.position.distance(to: playerPosition) <= 82 {
            if plant.kind.isPickableGrass {
                return "E 采集晶露小草"
            }
            if plant.kind.isTree {
                return state.craftedItems.contains(.runeAxe) || state.craftedItems.contains(.timberSaw)
                    ? "E 砍伐晶纹木"
                    : "需要碎晶斧或伐晶锯"
            }
        }

        if let node = state.resourceNodes[plane.id, default: []]
            .filter({ $0.amount > 0 })
            .min(by: { $0.position.distance(to: playerPosition) < $1.position.distance(to: playerPosition) }),
           node.position.distance(to: playerPosition) <= 64 {
            return "E 采集 \(plane.resource.name)"
        }

        if let rift = state.rifts[plane.id],
           !state.sealedPlanes.contains(plane.id),
           rift.position.distance(to: playerPosition) <= 136 {
            return state.inventory[.sealStele, default: 0] > 0 ? "B 放置封印石碑" : "需要封印石碑"
        }

        let center = CGPoint(x: world.width / 2, y: world.height / 2)
        if center.distance(to: playerPosition) <= 185 {
            return state.won ? "核心结界稳定，状态快速恢复" : "核心据点正在恢复状态"
        }

        if playerPosition.x <= 96 || playerPosition.x >= world.width - 96 ||
            playerPosition.y <= 96 || playerPosition.y >= world.height - 96 {
            return "E 穿越位面边界"
        }

        if state.inventory[.crystalTonic, default: 0] > 0 {
            return state.player.vitality < 99.5 || state.player.thermal < 99.5
                ? "E 使用晶凝药剂"
                : "晶凝药剂已备好"
        }

        return nil
    }

    private func mapPoint(_ point: CGPoint, in mapRect: CGRect) -> CGPoint {
        CGPoint(
            x: mapRect.minX + point.x / world.width * mapRect.width,
            y: mapRect.minY + point.y / world.height * mapRect.height
        )
    }

    private func drawMapDot(at point: CGPoint, radius: CGFloat, color: NSColor) {
        context.setFillColor(color.cgColor)
        context.fillEllipse(in: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
    }

    private func drawMapDiamond(at point: CGPoint, radius: CGFloat, color: NSColor) {
        context.setFillColor(color.cgColor)
        context.beginPath()
        context.move(to: CGPoint(x: point.x, y: point.y + radius))
        context.addLine(to: CGPoint(x: point.x + radius, y: point.y))
        context.addLine(to: CGPoint(x: point.x, y: point.y - radius))
        context.addLine(to: CGPoint(x: point.x - radius, y: point.y))
        context.closePath()
        context.fillPath()
    }

    private func drawText(_ string: String, in frame: CGRect, size: CGFloat, weight: NSFont.Weight, color: NSColor, alignment: NSTextAlignment = .left) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        string.draw(in: frame, withAttributes: attributes)
    }
}

private extension EnemyKind {
    var rotationSpeed: CGFloat {
        switch self {
        case .shardling: return 0.25
        case .skitter: return -0.42
        case .bulwark: return 0.12
        case .wisp: return 0.55
        case .reefFish: return 0.18
        }
    }

    var outerRadius: CGFloat {
        switch self {
        case .shardling: return 29
        case .skitter: return 31
        case .bulwark: return 32
        case .wisp: return 24
        case .reefFish: return 27
        }
    }

    var innerRadius: CGFloat {
        switch self {
        case .shardling: return 17
        case .skitter: return 10
        case .bulwark: return 24
        case .wisp: return 14
        case .reefFish: return 12
        }
    }

    func fillColor(for plane: Plane) -> NSColor {
        switch self {
        case .shardling:
            return plane.palette.base
        case .skitter:
            return plane.palette.glow.withAlphaComponent(0.92)
        case .bulwark:
            return plane.palette.dark.blended(withFraction: 0.5, of: plane.palette.base) ?? plane.palette.base
        case .wisp:
            return plane.palette.light.withAlphaComponent(0.72)
        case .reefFish:
            return NSColor(hex: "#56d0e8")
        }
    }
}
