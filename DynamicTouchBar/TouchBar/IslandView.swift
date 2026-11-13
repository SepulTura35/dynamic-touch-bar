import AppKit
import Combine

/// Renders the island: the capsule, the optional detached bubble, the ambient glow and the
/// content, all driven by `CapsuleAnimator` on the shared display link.
///
/// The same view is used on the physical Touch Bar, in the optional on-screen mirror and in
/// the Settings preview — touches (Touch Bar) and clicks (screen) go through one gesture
/// recognizer, so behaviour is identical everywhere.
final class IslandView: NSView, FrameDriven {
    enum Role { case touchBar, mirror, preview }

    let role: Role
    private unowned let env: AppEnvironment
    private var animator: CapsuleAnimator
    private var palette: IslandPalette
    private var currentState = IslandLayoutState.initial

    private var contentViews: [String: IslandContentView] = [:]
    private var bubbleViews: [String: IslandContentView] = [:]
    private var contentSizes: [String: CGSize] = [:]

    private let backgroundView = NSView()
    private let glowLayer = CAGradientLayer()
    private let capsuleLayer = CAGradientLayer()
    private let rimLayer = CALayer()
    private let rimMask = CAGradientLayer()
    private let bubbleLayer = CAGradientLayer()
    private let bubbleRimLayer = CALayer()
    private let contentHost = NSView()
    private let contentMask = CALayer()
    private let bubbleHost = NSView()
    private let bubbleMask = CALayer()
    private var debugLabel: NSTextField?

    private var glowTint: NSColor = .clear
    private var isRegisteredForFrames = false
    private var lastLaidOutSize: CGSize = .zero
    private var cancellables = Set<AnyCancellable>()
    private var lastSettings: AppSettings

    private enum TrackingTarget {
        case control(IslandInteractive)
        case capsule(start: NSPoint)
        case bubble
        case none
    }
    private var tracking: TrackingTarget = .none

    init(env: AppEnvironment, role: Role) {
        self.env = env
        self.role = role
        self.lastSettings = env.settings.settings
        self.palette = IslandPalette.make(theme: lastSettings.theme, accent: lastSettings.accent)
        self.animator = CapsuleAnimator(parameters: lastSettings.springParameters)
        super.init(frame: NSRect(x: 0, y: 0, width: IslandMetrics.defaultAppRegionWidth, height: IslandMetrics.barHeight))
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        setUpLayers()
        setUpGestures()
        bind()
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Dynamic Island")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        // FrameDriver holds clients weakly; nothing to unregister.
    }

    override var isFlipped: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: - Setup

    private func setUpLayers() {
        backgroundView.wantsLayer = true
        addSubview(backgroundView)
        let root = backgroundView.layer!

        glowLayer.type = .radial
        glowLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        glowLayer.endPoint = CGPoint(x: 1, y: 1)
        glowLayer.opacity = 0
        root.addSublayer(glowLayer)

        for shape in [capsuleLayer, bubbleLayer] {
            shape.startPoint = CGPoint(x: 0.5, y: 1)
            shape.endPoint = CGPoint(x: 0.5, y: 0)
            shape.masksToBounds = true
            root.addSublayer(shape)
        }
        // Hairline highlight on the top edge only (no full border).
        for rim in [rimLayer, bubbleRimLayer] {
            rim.borderWidth = 0.75
            root.addSublayer(rim)
        }
        rimMask.colors = [NSColor.white.cgColor, NSColor.white.withAlphaComponent(0).cgColor]
        rimMask.startPoint = CGPoint(x: 0.5, y: 1)
        rimMask.endPoint = CGPoint(x: 0.5, y: 0.45)
        rimLayer.mask = rimMask
        let bubbleRimMask = CAGradientLayer()
        bubbleRimMask.colors = rimMask.colors
        bubbleRimMask.startPoint = rimMask.startPoint
        bubbleRimMask.endPoint = rimMask.endPoint
        bubbleRimLayer.mask = bubbleRimMask

        for host in [contentHost, bubbleHost] {
            host.wantsLayer = true
            addSubview(host)
        }
        contentMask.backgroundColor = NSColor.black.cgColor
        bubbleMask.backgroundColor = NSColor.black.cgColor
        contentHost.layer?.mask = contentMask
        bubbleHost.layer?.mask = bubbleMask

        applyPaletteToLayers()
    }

    private func applyPaletteToLayers() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let colors = [palette.capsuleTop.cgColor, palette.capsuleBottom.cgColor]
        capsuleLayer.colors = colors
        bubbleLayer.colors = colors
        rimLayer.borderColor = palette.rim.cgColor
        bubbleRimLayer.borderColor = palette.rim.cgColor
        CATransaction.commit()
    }

    private func setUpGestures() {
        allowedTouchTypes = [.direct, .indirect]
        let press = NSPressGestureRecognizer(target: self, action: #selector(handlePress(_:)))
        press.minimumPressDuration = 0
        press.allowableMovement = 10_000
        press.allowedTouchTypes = [.direct]
        press.buttonMask = 0x1
        addGestureRecognizer(press)
    }

    private func bind() {
        env.coordinator.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in self?.render(state, animated: true) }
            .store(in: &cancellables)

        env.settings.$settings
            .receive(on: RunLoop.main)
            .sink { [weak self] settings in self?.settingsChanged(settings) }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .merge(with: NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification))
            .merge(with: NotificationCenter.default.publisher(for: AppEnvironment.visibilityChanged))
            .sink { [weak self] _ in self?.updateOnScreen() }
            .store(in: &cancellables)
    }

    // MARK: - Settings

    private func settingsChanged(_ settings: AppSettings) {
        let old = lastSettings
        lastSettings = settings
        if settings.theme != old.theme || settings.accent != old.accent {
            palette = IslandPalette.make(theme: settings.theme, accent: settings.accent)
            applyPaletteToLayers()
            rebuildContent()
        }
        if settings.springParameters != old.springParameters {
            animator.updateParameters(settings.springParameters)
        }
        if settings.debugMode != old.debugMode { updateDebugLabel() }
        if settings.capsuleWidthScale != old.capsuleWidthScale || settings.cornerRadius != old.cornerRadius
            || settings.ambientGlow != old.ambientGlow || settings.tintFromArtwork != old.tintFromArtwork
            || settings.dashboardActions != old.dashboardActions || settings.customActions != old.customActions
            || settings.profiles != old.profiles {
            if settings.dashboardActions != old.dashboardActions || settings.customActions != old.customActions || settings.profiles != old.profiles {
                rebuildContent()
            }
            updateTarget(animated: true)
        }
    }

    private func rebuildContent() {
        for view in contentViews.values { view.removeFromSuperview() }
        for view in bubbleViews.values { view.removeFromSuperview() }
        contentViews.removeAll()
        bubbleViews.removeAll()
        ensureContentView(for: currentState.primary)
        if let secondary = currentState.secondary { ensureBubbleView(for: secondary) }
        updateTarget(animated: true)
        applyFrame()
    }

    // MARK: - Rendering

    func render(_ state: IslandLayoutState, animated: Bool) {
        currentState = state
        ensureContentView(for: state.primary)
        if let secondary = state.secondary { ensureBubbleView(for: secondary) }
        updateTarget(animated: animated)
        updateOnScreen()
        updateDebugLabel()
    }

    private func ensureContentView(for content: PresentationContent) {
        guard contentViews[content.id] == nil else { return }
        let view = ContentFactory.makeView(for: content, env: env, palette: palette)
        view.onLayoutChange = { [weak self] in self?.updateTarget(animated: true) }
        view.alphaValue = 0
        contentHost.addSubview(view)
        contentViews[content.id] = view
    }

    private func ensureBubbleView(for kind: LiveActivityKind) {
        let id = Self.bubbleID(kind)
        guard bubbleViews[id] == nil else { return }
        let view = ContentFactory.makeBubbleView(for: kind, env: env, palette: palette)
        view.alphaValue = 0
        bubbleHost.addSubview(view)
        bubbleViews[id] = view
    }

    private static func bubbleID(_ kind: LiveActivityKind) -> String { "bubble.\(kind.rawValue)" }

    /// Computes where everything should go and hands it to the animator.
    private func updateTarget(animated: Bool) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let settings = env.settings.settings
        let hasBubble = currentState.secondary != nil
        let bubbleDiameter = min(IslandMetrics.bubbleDiameter, bounds.height - 2)
        let bubbleReserve = hasBubble ? bubbleDiameter + IslandMetrics.bubbleGap : 0
        let available = max(IslandMetrics.minimumCapsuleWidth, bounds.width - 2 * IslandMetrics.edgeMargin - bubbleReserve)

        let id = currentState.primary.id
        guard let view = contentViews[id] else { return }
        let height = min(view.prefersCompactHeight ? IslandMetrics.compactHeight : IslandMetrics.expandedHeight, bounds.height)
        let width = min(max(view.preferredWidth(maxWidth: available).rounded(), IslandMetrics.minimumCapsuleWidth), available)
        contentSizes[id] = CGSize(width: width, height: height)

        let groupWidth = width + bubbleReserve
        let groupLeft = bounds.midX - groupWidth / 2
        let centerX = groupLeft + width / 2
        let corner = min(CGFloat(settings.cornerRadius) * height / IslandMetrics.expandedHeight, height / 2)

        if let tint = view.glowColor, settings.ambientGlow {
            glowTint = tint
        }
        let glow = (settings.ambientGlow && view.glowColor != nil) ? 1.0 : 0.0

        var bubble: BubbleTarget?
        if let secondary = currentState.secondary {
            bubble = BubbleTarget(contentID: Self.bubbleID(secondary), diameter: bubbleDiameter,
                                  centerX: groupLeft + width + IslandMetrics.bubbleGap + bubbleDiameter / 2)
        }

        let target = CapsuleTarget(width: width, height: height, centerX: centerX, cornerRadius: corner,
                                   contentID: id, glow: glow, bubble: bubble)
        animator.apply(target, animated: animated)
        pruneOrphanedViews()
        if animated {
            startFramesIfNeeded()
        } else {
            let removed = animator.step(0)
            removeViews(removed)
            applyFrame()
        }
    }

    /// Views whose slot no longer exists (e.g. after a non-animated transition) are detached,
    /// so nothing stale can linger invisibly — or visibly — behind the current content.
    private func pruneOrphanedViews() {
        let liveContent = Set(animator.slots.map(\.id))
        for (id, view) in contentViews where !liveContent.contains(id) {
            view.removeFromSuperview()
            contentViews[id] = nil
            contentSizes[id] = nil
        }
        let liveBubbles = Set(animator.bubbleSlots.map(\.id))
        for (id, view) in bubbleViews where !liveBubbles.contains(id) {
            view.removeFromSuperview()
            bubbleViews[id] = nil
        }
    }

    private func startFramesIfNeeded() {
        guard animator.isAnimating, !isRegisteredForFrames else {
            if !animator.isAnimating { applyFrame() }
            return
        }
        isRegisteredForFrames = true
        FrameDriver.shared.start(self)
    }

    func advanceFrame(by dt: Double) -> Bool {
        let removed = animator.step(dt)
        removeViews(removed)
        applyFrame()
        let animating = animator.isAnimating
        if !animating { isRegisteredForFrames = false }
        return animating
    }

    private func removeViews(_ removed: (removedContent: [String], removedBubbleContent: [String])) {
        for id in removed.removedContent where id != currentState.primary.id {
            contentViews[id]?.removeFromSuperview()
            contentViews[id] = nil
            contentSizes[id] = nil
        }
        for id in removed.removedBubbleContent {
            if let secondary = currentState.secondary, Self.bubbleID(secondary) == id { continue }
            bubbleViews[id]?.removeFromSuperview()
            bubbleViews[id] = nil
        }
    }

    /// Writes the animator's current values into layers and views. Runs once per frame while
    /// animating, inside a transaction with implicit animations disabled.
    private func applyFrame() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let midY = bounds.midY
        let width = max(0, animator.width.value)
        let height = max(0, animator.height.value)
        let centerX = animator.centerX.value
        let corner = max(0, min(animator.cornerRadius.value, height / 2))
        let capsuleFrame = CGRect(x: centerX - width / 2, y: midY - height / 2, width: width, height: height)

        capsuleLayer.frame = capsuleFrame
        capsuleLayer.cornerRadius = corner
        rimLayer.frame = capsuleFrame
        rimLayer.cornerRadius = corner
        rimMask.frame = rimLayer.bounds
        contentMask.frame = capsuleFrame
        contentMask.cornerRadius = corner

        let glowAmount = Float(min(max(animator.glow.value, 0), 1))
        glowLayer.frame = capsuleFrame.insetBy(dx: -28, dy: -14)
        glowLayer.colors = [glowTint.withAlphaComponent(palette.theme == .dark ? 0.42 : 0.3).cgColor, glowTint.withAlphaComponent(0).cgColor]
        glowLayer.opacity = glowAmount

        for slot in animator.slots {
            guard let view = contentViews[slot.id] else { continue }
            let size = contentSizes[slot.id] ?? view.frame.size
            let presence = CGFloat(min(max(slot.presence.value, 0), 1.05))
            let frame = CGRect(x: (centerX - size.width / 2).rounded(), y: (midY - size.height / 2).rounded(), width: size.width, height: size.height)
            if view.frame != frame { view.frame = frame }
            view.alphaValue = slot.isCurrent ? min(1, presence) : pow(min(1, presence), 1.6)
            let scale = 0.9 + 0.1 * min(1, presence)
            view.layer?.transform = Self.scaleTransform(scale, size: size)
        }

        // Bubble
        let bubblePresence = CGFloat(min(max(animator.bubblePresence.value, 0), 1.2))
        let diameter = max(0, animator.bubbleDiameter.value) * (0.55 + 0.45 * min(1, bubblePresence))
        let bubbleFrame = CGRect(x: animator.bubbleCenterX.value - diameter / 2, y: midY - diameter / 2, width: diameter, height: diameter)
        bubbleLayer.frame = bubbleFrame
        bubbleLayer.cornerRadius = diameter / 2
        bubbleLayer.opacity = Float(min(1, bubblePresence))
        bubbleRimLayer.frame = bubbleFrame
        bubbleRimLayer.cornerRadius = diameter / 2
        bubbleRimLayer.mask?.frame = bubbleRimLayer.bounds
        bubbleRimLayer.opacity = Float(min(1, bubblePresence))
        bubbleMask.frame = bubbleFrame
        bubbleMask.cornerRadius = diameter / 2
        for slot in animator.bubbleSlots {
            guard let view = bubbleViews[slot.id] else { continue }
            let side = IslandMetrics.bubbleDiameter
            view.frame = CGRect(x: animator.bubbleCenterX.value - side / 2, y: midY - side / 2, width: side, height: side)
            view.alphaValue = CGFloat(min(max(slot.presence.value, 0), 1)) * min(1, bubblePresence)
        }

        CATransaction.commit()
    }

    private static func scaleTransform(_ scale: CGFloat, size: CGSize) -> CATransform3D {
        // NSView layers are anchored at (0,0); scale about the center instead.
        var transform = CATransform3DMakeTranslation(size.width / 2, size.height / 2, 0)
        transform = CATransform3DScale(transform, scale, scale, 1)
        return CATransform3DTranslate(transform, -size.width / 2, -size.height / 2, 0)
    }

    override func layout() {
        super.layout()
        backgroundView.frame = bounds
        contentHost.frame = bounds
        bubbleHost.frame = bounds
        debugLabel?.frame = NSRect(x: 2, y: bounds.height - 9, width: 160, height: 9)
        if bounds.width > 0, bounds.height > 0, bounds.size != lastLaidOutSize {
            let isFirst = lastLaidOutSize == .zero
            lastLaidOutSize = bounds.size
            if role == .touchBar {
                Log.touchBar.info("Island laid out at \(Int(self.bounds.width))×\(Int(self.bounds.height)) pt")
            }
            updateTarget(animated: !isFirst)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateOnScreen()
        if window != nil, lastLaidOutSize == .zero { render(env.coordinator.state, animated: false) }
    }

    private func updateOnScreen() {
        let visible = window != nil && (role == .preview ? true : env.isIslandVisible || NSApp.isActive)
        for (id, view) in contentViews { view.setOnScreen(visible && id == currentState.primary.id) }
        for (id, view) in bubbleViews { view.setOnScreen(visible && currentState.secondary.map(Self.bubbleID) == id) }
    }

    private func updateDebugLabel() {
        guard env.settings.settings.debugMode else {
            debugLabel?.removeFromSuperview()
            debugLabel = nil
            return
        }
        if debugLabel == nil {
            let label = IslandLabel.make(font: .monospacedSystemFont(ofSize: 7, weight: .regular), color: .systemGreen)
            addSubview(label)
            debugLabel = label
            needsLayout = true
        }
        debugLabel?.stringValue = "\(currentState.primary.id)\(currentState.secondary.map { " + \($0.rawValue)" } ?? "")"
    }

    // MARK: - Inspection (tests, debug)

    var currentContentView: IslandContentView? { contentViews[currentState.primary.id] }
    var currentCapsuleFrame: CGRect { contentMask.frame }
    var currentBubbleFrame: CGRect? { currentState.secondary == nil ? nil : bubbleMask.frame }

    // MARK: - Interaction

    @objc private func handlePress(_ recognizer: NSPressGestureRecognizer) {
        let point = recognizer.location(in: self)
        switch recognizer.state {
        case .began:
            env.noteInteraction()
            tracking = target(at: point)
            if case .control(let control) = tracking {
                control.trackingBegan(at: control.convert(point, from: self))
            }
        case .changed:
            if case .control(let control) = tracking {
                control.trackingMoved(to: control.convert(point, from: self))
            }
        case .ended:
            env.noteInteraction()
            switch tracking {
            case .control(let control):
                control.trackingEnded(at: control.convert(point, from: self), cancelled: false)
            case .capsule(let start):
                if hypot(point.x - start.x, point.y - start.y) < 14 { env.coordinator.tapCapsule() }
            case .bubble:
                env.coordinator.tapBubble()
            case .none:
                break
            }
            tracking = .none
        case .cancelled, .failed:
            if case .control(let control) = tracking {
                control.trackingEnded(at: control.convert(point, from: self), cancelled: true)
            }
            tracking = .none
        default:
            break
        }
    }

    private func target(at point: NSPoint) -> TrackingTarget {
        let capsuleFrame = contentMask.frame
        let bubbleFrame = bubbleMask.frame.insetBy(dx: -4, dy: -4)
        if currentState.secondary != nil, bubbleFrame.contains(point) { return .bubble }
        guard capsuleFrame.insetBy(dx: -6, dy: -4).contains(point) else { return .none }
        if let view = contentViews[currentState.primary.id] {
            let local = contentHost.convert(point, from: self)
            var hit = view.hitTest(local)
            while let candidate = hit, candidate !== view {
                if let control = candidate as? IslandInteractive { return .control(control) }
                hit = candidate.superview
            }
            if let control = Self.nearestControl(in: view, to: view.convert(local, from: contentHost)) {
                return .control(control)
            }
        }
        return .capsule(start: point)
    }

    /// Fingers are wide: if a touch lands just outside a control, use the closest one within 10 pt.
    private static func nearestControl(in view: NSView, to point: NSPoint) -> IslandInteractive? {
        var best: (IslandInteractive, CGFloat)?
        func visit(_ node: NSView) {
            for child in node.subviews where !child.isHidden && child.alphaValue > 0.05 {
                if let control = child as? IslandInteractive {
                    let frame = view.convert(child.bounds, from: child)
                    let dx = max(frame.minX - point.x, 0, point.x - frame.maxX)
                    let dy = max(frame.minY - point.y, 0, point.y - frame.maxY)
                    let distance = hypot(dx, dy)
                    if distance <= 10, distance < (best?.1 ?? .infinity) { best = (control, distance) }
                } else {
                    visit(child)
                }
            }
        }
        visit(view)
        return best?.0
    }
}
