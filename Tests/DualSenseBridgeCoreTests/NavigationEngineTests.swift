import Foundation
import Testing

@testable import DualSenseBridgeCore

@Suite("normalized stick axes stay independent of any input framework")
struct StickAxisTests {
    @Test("a stick position clamps each component to the unit range")
    func componentsAreClamped() {
        let position = StickVector(x: 3.5, y: -9)

        #expect(position.x == 1)
        #expect(position.y == -1)
    }

    @Test("a non-finite axis value can never reach the cursor")
    func nonFiniteValuesAreNeutralized() {
        let position = StickVector(x: .nan, y: .infinity)

        #expect(position == .centered)
        #expect(position.isCentered)
    }

    @Test("magnitude is clamped so a diagonal is not faster than a cardinal push")
    func magnitudeIsClamped() {
        #expect(StickVector(x: 1, y: 1).magnitude == 1)
        #expect(isClose(StickVector(x: 0.6, y: 0).magnitude, 0.6))
    }

    @Test("direction is normalized by the unclamped length, so diagonals are unit length")
    func directionIsUnitLength() {
        let diagonal = StickVector(x: 1, y: 1).direction

        #expect(isClose(hypot(diagonal.x, diagonal.y), 1))
        #expect(isClose(diagonal.x, 0.5.squareRoot()))
        #expect(isClose(diagonal.y, 0.5.squareRoot()))
    }

    @Test("a stick at rest has no direction to report")
    func restingStickHasNoDirection() {
        #expect(StickVector.centered.direction == .centered)
    }

    @Test("a stick position describes itself for diagnostics")
    func positionDescription() {
        #expect(StickVector(x: 0.5, y: -0.25).description == "x=+0.50 y=-0.25")
    }

    @Test("an axis event records stick, position, timestamp, and source")
    func axisEventCarriesContext() {
        let controller = ControllerIdentity(id: "controller-1", displayName: "DualSense")
        let event = ControllerAxisEvent(
            controller: controller,
            stick: .right,
            position: StickVector(x: 0.5, y: -0.25),
            timestamp: 4.5,
            source: .fake
        )

        #expect(event.stick == .right)
        #expect(event.position == StickVector(x: 0.5, y: -0.25))
        #expect(event.timestamp == 4.5)
        #expect(event.source == .fake)
        #expect(ControllerInput.axis(event).controller == controller)
    }

    @Test("sticks are named in configuration-friendly text")
    func stickNames() {
        #expect(ControllerStick.left.rawValue == "left")
        #expect(ControllerStick.right.rawValue == "right")
        #expect(ControllerStick.allCases.count == 2)
    }
}

@Suite("the navigation engine turns held axes into bounded motion")
struct NavigationEngineTests {
    /// Linear response and round numbers, so every expectation below is exact
    /// arithmetic rather than a tolerance on a curve.
    private static let linear = NavigationSettings(
        pointer: NavigationAxisSettings(deadzone: 0.2, responseExponent: 1, speed: 100),
        scroll: NavigationAxisSettings(deadzone: 0.2, responseExponent: 1, speed: 100),
        tickInterval: 0.01,
        maximumTickInterval: 0.05
    )

    private let controller = ControllerIdentity(id: "controller-1", displayName: "Fake DualSense")

    /// An engine whose clock baseline is already established, which is the
    /// steady state of a run loop that ticks continuously.
    private func makeEngine(
        _ settings: NavigationSettings = NavigationEngineTests.linear
    ) -> (NavigationEngine, Double) {
        var engine = NavigationEngine(settings: settings)
        let start = 10.0
        #expect(engine.tick(at: start).isEmpty)
        return (engine, start)
    }

    private func push(
        _ stick: ControllerStick,
        x: Double,
        y: Double,
        at timestamp: Double = 0
    ) -> ControllerAxisEvent {
        ControllerAxisEvent(
            controller: controller,
            stick: stick,
            position: StickVector(x: x, y: y),
            timestamp: timestamp,
            source: .fake
        )
    }

    // MARK: - Deadzone and clamping

    @Test("a stick resting inside the deadzone produces nothing")
    func deadzoneSwallowsRest() {
        var (engine, now) = makeEngine()

        engine.update(push(.right, x: 0.15, y: -0.1))
        now += 0.01

        #expect(engine.tick(at: now).isEmpty)
        #expect(engine.isIdle)
    }

    @Test("deflection past the deadzone is rescaled from zero, not stepped")
    func deadzoneIsRescaled() throws {
        var (engine, now) = makeEngine()

        // Just past a 0.2 deadzone, so the response must be near zero rather
        // than jumping straight to a fifth of full speed.
        engine.update(push(.right, x: 0.21, y: 0))
        now += 0.01
        let justPast = engine.tick(at: now)

        #expect(justPast.count == 1)
        let delta = try #require(justPast.first?.cursorDelta)
        #expect(isClose(delta.dx, 100 * 0.01 * (0.01 / 0.8)))
        #expect(delta.dy == 0)
    }

    @Test("half deflection moves the cursor at half speed")
    func linearResponse() throws {
        var (engine, now) = makeEngine()

        engine.update(push(.right, x: 0.6, y: 0))
        now += 0.01
        let delta = try #require(engine.tick(at: now).first?.cursorDelta)

        // (0.6 - 0.2) / (1 - 0.2) = 0.5 of full speed for 0.01 seconds.
        #expect(isClose(delta.dx, 0.5))
    }

    @Test("a response curve makes small deflections finer without capping the top")
    func responseCurveIsApplied() throws {
        var settings = NavigationEngineTests.linear
        settings.pointer.responseExponent = 2
        var (engine, now) = makeEngine(settings)

        engine.update(push(.right, x: 0.6, y: 0))
        now += 0.01
        let half = try #require(engine.tick(at: now).first?.cursorDelta)
        #expect(isClose(half.dx, 0.25))

        engine.update(push(.right, x: 1, y: 0))
        now += 0.01
        let full = try #require(engine.tick(at: now).first?.cursorDelta)
        #expect(isClose(full.dx, 1.0))
    }

    @Test("a diagonal push is clamped to the same speed as a cardinal push")
    func diagonalIsClamped() throws {
        var (engine, now) = makeEngine()

        engine.update(push(.right, x: 1, y: 1))
        now += 0.01
        let delta = try #require(engine.tick(at: now).first?.cursorDelta)

        #expect(isClose(hypot(delta.dx, delta.dy), 1.0))
        #expect(isClose(delta.dx, 0.5.squareRoot()))
        // Screen coordinates grow downwards, so a stick pushed up moves up.
        #expect(isClose(delta.dy, -0.5.squareRoot()))
    }

    @Test("motion never exceeds the configured speed however hard the stick is pushed")
    func speedIsBounded() throws {
        var (engine, now) = makeEngine()

        engine.update(push(.right, x: 5, y: -5))
        now += 0.01
        let delta = try #require(engine.tick(at: now).first?.cursorDelta)

        #expect(isClose(hypot(delta.dx, delta.dy), 1.0))
    }

    // MARK: - Continuous motion

    @Test("a held stick keeps moving without any further axis callback")
    func heldStickKeepsMoving() throws {
        var (engine, now) = makeEngine()
        engine.update(push(.right, x: 1, y: 0))

        var deltas: [Double] = []
        for _ in 0..<3 {
            now += 0.01
            deltas.append(try #require(engine.tick(at: now).first?.cursorDelta).dx)
        }

        #expect(deltas.count == 3)
        #expect(deltas.allSatisfy { isClose($0, 1.0) })
        #expect(!engine.isIdle)
    }

    @Test("motion is proportional to elapsed time, not to tick count")
    func motionFollowsElapsedTime() throws {
        var (engine, now) = makeEngine()
        engine.update(push(.right, x: 1, y: 0))

        now += 0.02
        let delta = try #require(engine.tick(at: now).first?.cursorDelta)

        #expect(isClose(delta.dx, 2.0))
    }

    @Test("a stalled process cannot fling the cursor across the screen")
    func longStallIsClamped() throws {
        var (engine, now) = makeEngine()
        engine.update(push(.right, x: 1, y: 0))

        now += 30
        let delta = try #require(engine.tick(at: now).first?.cursorDelta)

        // Clamped to maximumTickInterval (0.05s), not 30 seconds of travel.
        #expect(isClose(delta.dx, 5.0))
    }

    @Test("a clock that does not advance produces no motion")
    func zeroElapsedProducesNothing() {
        var (engine, now) = makeEngine()
        engine.update(push(.right, x: 1, y: 0))

        #expect(engine.tick(at: now).isEmpty)
    }

    @Test("the first tick only establishes the clock baseline")
    func firstTickIsABaseline() throws {
        var engine = NavigationEngine(settings: NavigationEngineTests.linear)
        engine.update(push(.right, x: 1, y: 0))

        #expect(engine.tick(at: 1_000).isEmpty)
        #expect(isClose(try #require(engine.tick(at: 1_000.01).first?.cursorDelta).dx, 1.0))
    }

    // MARK: - Release and cleanup

    @Test("releasing the stick stops output immediately")
    func releaseStopsOutput() {
        var (engine, now) = makeEngine()
        engine.update(push(.right, x: 1, y: 0))
        now += 0.01
        #expect(!engine.tick(at: now).isEmpty)

        engine.update(push(.right, x: 0, y: 0))
        now += 0.01

        #expect(engine.tick(at: now).isEmpty)
        #expect(engine.isIdle)
    }

    @Test("clearing one controller leaves another controller moving")
    func clearIsScopedToOneController() throws {
        var (engine, now) = makeEngine()
        let other = ControllerIdentity(id: "controller-2", displayName: "Second")

        engine.update(push(.right, x: 1, y: 0))
        engine.update(
            ControllerAxisEvent(
                controller: other,
                stick: .right,
                position: StickVector(x: 1, y: 0),
                timestamp: 0,
                source: .fake
            )
        )
        now += 0.01
        #expect(engine.tick(at: now).count == 2)

        engine.clear(controller: controller)
        now += 0.01
        let remaining = engine.tick(at: now)

        #expect(remaining.count == 1)
        #expect(!engine.isIdle)
    }

    @Test("clearing everything stops all motion")
    func clearAllStopsMotion() {
        var (engine, now) = makeEngine()
        engine.update(push(.right, x: 1, y: 0))
        engine.update(push(.left, x: 0, y: 1))

        engine.clearAll()
        now += 0.01

        #expect(engine.tick(at: now).isEmpty)
        #expect(engine.isIdle)
        #expect(engine.activeAxisCount == 0)
    }

    // MARK: - Roles

    @Test("the right stick moves the pointer and the left stick scrolls")
    func stickRoles() throws {
        var (engine, now) = makeEngine()

        engine.update(push(.right, x: 1, y: 0))
        engine.update(push(.left, x: 0, y: 1))
        now += 0.01
        let outputs = engine.tick(at: now)

        #expect(outputs.count == 2)
        // Pointer output is emitted first so a log reads in a stable order.
        #expect(outputs.first?.cursorDelta != nil)
        let scroll = try #require(outputs.last?.scrollDelta)
        // A stick pushed up scrolls up, so vertical scroll keeps the stick sign.
        #expect(isClose(scroll.dy, 1.0))
        #expect(scroll.dx == 0)
    }

    @Test("each axis can be inverted without recompiling")
    func axesCanBeInverted() throws {
        var settings = NavigationEngineTests.linear
        settings.pointer.invertY = true
        settings.scroll.invertX = true
        var (engine, now) = makeEngine(settings)

        engine.update(push(.right, x: 0, y: 1))
        engine.update(push(.left, x: 1, y: 0))
        now += 0.01
        let outputs = engine.tick(at: now)

        #expect(isClose(try #require(outputs.first?.cursorDelta).dy, 1.0))
        #expect(isClose(try #require(outputs.last?.scrollDelta).dx, -1.0))
    }

    @Test("replacing settings stops motion so a mapping change cannot run away")
    func replacingSettingsClearsAxes() {
        var (engine, now) = makeEngine()
        engine.update(push(.right, x: 1, y: 0))

        engine.replaceSettings(with: .default)
        now += 0.01

        #expect(engine.tick(at: now).isEmpty)
        #expect(engine.settings == .default)
    }

    @Test("outputs describe themselves for diagnostics")
    func outputDescriptions() {
        #expect(NavigationOutput.moveCursor(dx: 1.5, dy: -2).description == "moveCursor dx=+1.50 dy=-2.00")
        #expect(NavigationOutput.scroll(dx: 0, dy: 3).description == "scroll dx=+0.00 dy=+3.00")
    }
}
