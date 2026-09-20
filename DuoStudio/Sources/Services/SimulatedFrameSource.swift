#if targetEnvironment(simulator)
import CoreGraphics
import CoreImage
import Dispatch
import Foundation
import os
import PoseCore

/// A synthetic `CaptureSource` for the iOS Simulator, which has no camera and would otherwise show
/// a black preview with none of the pose/gesture UI exercisable. Feeds the real pipeline
/// (`StudioModel.receive(_:)`) a procedurally drawn frame ~10 times a second, a slowly perturbed
/// built-in pose, and a looping canned hand-gesture script — see `DuoStudio/plan.md`'s Simulator
/// section for exactly what this does and doesn't prove.
///
/// `@unchecked Sendable`: every stored mutable property lives in `State`, guarded by
/// `OSAllocatedUnfairLock` — the same primitive `FrameProcessor.cameraState` already uses for
/// state written from `MainActor` and read from a background queue. `timer` is the one property
/// outside that lock; it's only ever touched from `timerQueue`, and `start()`/`stop()` both hop
/// onto `timerQueue` before touching it, mirroring `CameraService`'s own "every public method
/// re-enters its queue before touching state" discipline. `ciContext` is documented thread-safe
/// for concurrent use (see `PhotoWriter`'s identical reasoning for its own shared `CIContext`).
final class SimulatedFrameSource: CaptureSource, @unchecked Sendable {
    /// Set once by `StudioModel` right after construction — same pattern, and the same reasoning
    /// for `weak` plus hopping to `MainActor` before use, as `FrameProcessor.model`.
    weak var model: StudioModel?

    private struct State {
        var mode: CaptureMode = .partner
        var filter: StudioFilter = .none
        var contrast: Double = 1
        /// Recorded but otherwise unused today — there's no hardware in the Simulator for exposure
        /// or white balance to affect. Kept so `apply(_:)` matches `CaptureSource`'s contract and a
        /// future visual tie-in (e.g. tinting the drawn frame by warmth) has somewhere to read from.
        var adjustments = Adjustments()
        /// Ticks since `start()`, never reset on a script loop wrap — see `tick()`.
        var sampleIndex = 0
        /// The last frame's filtered image, kept only so `capturePhoto()` can re-encode it as JPEG
        /// without redrawing.
        var lastImage: CIImage?
    }
    private let state = OSAllocatedUnfairLock(initialState: State())

    private let timerQueue = DispatchQueue(label: "tech.kioh.duostudio.simulator")
    /// `timerQueue`-confined: only ever read or written after `start()`/`stop()` hop onto the queue.
    private var timer: DispatchSourceTimer?
    private let ciContext = CIContext()

    private static let sampleInterval: TimeInterval = 0.1
    private static let scriptDuration: TimeInterval = 16
    private static let imageSize = CGSize(width: 900, height: 1200)

    func start() {
        timerQueue.async { [self] in
            guard timer == nil else { return }
            let source = DispatchSource.makeTimerSource(queue: timerQueue)
            source.schedule(deadline: .now(), repeating: Self.sampleInterval)
            source.setEventHandler { [weak self] in self?.tick() }
            timer = source
            source.resume()
        }
    }

    func stop() {
        timerQueue.async { [self] in
            timer?.cancel()
            timer = nil
        }
    }

    func apply(_ adjustments: Adjustments) {
        state.withLock { $0.adjustments = adjustments }
    }

    /// Recorded mode also flips the drawn figure horizontally in `tick()`, so switching between
    /// partner and self-portrait mode is visibly different even against a fake source.
    func setMode(_ mode: CaptureMode) {
        state.withLock { $0.mode = mode }
    }

    /// Same contract as `FrameProcessor.updateFilter(_:contrast:)`: called by `StudioModel`
    /// whenever the filter or contrast changes (gesture or inner-UI alike), so the next drawn frame
    /// picks it up.
    func updateFilter(_ filter: StudioFilter, contrast: Double) {
        state.withLock {
            $0.filter = filter
            $0.contrast = contrast
        }
    }

    func capturePhoto() async throws -> Data {
        guard let image = state.withLock({ $0.lastImage }),
              let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
              let data = ciContext.jpegRepresentation(of: image, format: .RGBA8, colorSpace: colorSpace)
        else {
            throw CameraServiceError.captureFailed
        }
        return data
    }

    // MARK: - Frame generation (timerQueue)

    private func tick() {
        let (time, mode, filter, contrast) = state.withLock { s -> (Double, CaptureMode, StudioFilter, Double) in
            let time = Double(s.sampleIndex) * Self.sampleInterval
            s.sampleIndex += 1
            return (time, s.mode, s.filter, s.contrast)
        }

        let pose = Self.perturbedPose(at: time)
        let hand = Self.handSample(at: time)

        guard let raw = Self.drawScene(pose: pose, mirrored: mode == .selfPortrait) else { return }
        var ciImage = CIImage(cgImage: raw)
        if let filterName = filter.coreImageName {
            ciImage = ciImage.applyingFilter(filterName)
        }
        ciImage = ciImage.applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: contrast])

        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }
        state.withLock { $0.lastImage = ciImage }

        let result = FrameResult(image: cgImage, pose: pose, hand: hand, isDetectionFrame: true)
        // Snapshot the weak reference to a local `let` first, same reasoning as `FrameProcessor`:
        // Swift 6's `sending` closure on `Task.init` needs a single, disconnected reference to hand
        // `model` (non-`Sendable`, `@MainActor`-isolated) over to the main actor without a race.
        guard let model else { return }
        Task { @MainActor in model.receive(result) }
    }

    // MARK: - Pose / hand synthesis (pure — no shared state)

    /// `PoseLibrary.builtIn[0]`'s pose, drifted a little as a whole and with wrists/elbows swinging
    /// on a slow sine, so the match % moves around instead of sitting at a constant.
    private static func perturbedPose(at time: Double) -> Pose {
        var pose = PoseLibrary.builtIn[0].pose
        let swing = sin(time * 0.9)
        let drift = sin(time * 0.15) * 0.02
        for (joint, point) in pose.joints {
            var moved = point
            moved.x += drift
            switch joint {
            case .leftWrist, .rightWrist:
                moved.y += swing * 0.05
                moved.x += swing * 0.03
            case .leftElbow, .rightElbow:
                moved.y += swing * 0.025
            default:
                break
            }
            pose.joints[joint] = moved
        }
        return pose
    }

    /// A canned gesture script looping every `scriptDuration` (~16 s), exercising every path
    /// `GestureRecognizer` recognises: idle → open-palm swipe (filter change) → growing pinch
    /// (zoom) → held fist (next parameter) → held pointUp (adjust up) → held pointDown (adjust
    /// down) → idle. `time` itself is never reset (see `tick()`), only the phase computed from it,
    /// so `GestureRecognizer`'s hold timers and swipe cooldown — which compare against the absolute
    /// sample time — never see time run backwards across a loop wrap.
    private static func handSample(at time: Double) -> HandSample {
        let phase = time.truncatingRemainder(dividingBy: scriptDuration)
        switch phase {
        case 0..<2:
            return HandSample(shape: nil, wrist: nil, pinchDistance: nil, time: time)
        case 2..<3:
            // Wrist x sweeps 0.15+ within under a second — clears `GestureRecognizer`'s
            // 0.15-within-0.6s swipe threshold.
            let local = phase - 2
            let wrist = Point2(x: 0.7 - 0.3 * local, y: 0.5)
            return HandSample(shape: .openPalm, wrist: wrist, pinchDistance: nil, time: time)
        case 3..<7:
            // Pinch distance grows steadily over ~40 samples, clearing the 3%-per-fire zoom
            // threshold many times over.
            let local = (phase - 3) / 4
            return HandSample(shape: .pinch, wrist: nil, pinchDistance: 0.2 + 0.9 * local, time: time)
        case 7..<8:
            return HandSample(shape: .fist, wrist: nil, pinchDistance: nil, time: time)
        case 8..<9.5:
            return HandSample(shape: .pointUp, wrist: nil, pinchDistance: nil, time: time)
        case 9.5..<11:
            return HandSample(shape: .pointDown, wrist: nil, pinchDistance: nil, time: time)
        default:
            return HandSample(shape: nil, wrist: nil, pinchDistance: nil, time: time)
        }
    }

    // MARK: - Drawing (pure — no shared state)

    /// Draws a soft vertical gradient plus a stick figure from `pose` into a fresh `CGContext`,
    /// then hands back the resulting `CGImage`. Cheap on purpose — this only ever runs in the
    /// Simulator, ~10 times a second.
    private static func drawScene(pose: Pose, mirrored: Bool) -> CGImage? {
        let width = Int(imageSize.width)
        let height = Int(imageSize.height)
        // UNVERIFIED (2026-09-20, written on Windows): `.noneSkipLast` + linear sRGB is a common,
        // long-standing combination for an opaque RGB `CGBitmapContext`, but not checked against
        // the current SDK from Windows.
        guard let colorSpace = CGColorSpace(name: CGColorSpace.linearSRGB),
              let context = CGContext(
                  data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              )
        else { return nil }

        // `CGContext`'s default space has its origin bottom-left, y-up; `Pose`/`Point2` (like the
        // rest of this app) use top-left, y-down (see `Pose.swift`). Flipping once here means every
        // point below is a plain `normalized * imageSize` — no per-point flip math.
        context.translateBy(x: 0, y: imageSize.height)
        context.scaleBy(x: 1, y: -1)

        drawBackground(into: context)
        drawFigure(pose, into: context, mirrored: mirrored)

        return context.makeImage()
    }

    private static func drawBackground(into context: CGContext) {
        let colorSpace = context.colorSpace ?? CGColorSpace(name: CGColorSpace.linearSRGB)!
        // Mirrors `Theme.Palette.paper`/`paper3` (see `Sources/Design/Theme.swift`) — this file
        // can't import SwiftUI's `Theme` (a Service, like `CameraService`/`FrameProcessor`, stays
        // UI-framework-free), so the same OKLCH triples are reused directly via `PoseCore.OKLCH`.
        let top = oklchColor(l: 0.13, c: 0.004, h: 260, colorSpace: colorSpace)
        let bottom = oklchColor(l: 0.23, c: 0.006, h: 260, colorSpace: colorSpace)
        guard let gradient = CGGradient(colorsSpace: colorSpace, colors: [top, bottom] as CFArray, locations: [0, 1])
        else { return }
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: imageSize.width / 2, y: 0),
            end: CGPoint(x: imageSize.width / 2, y: imageSize.height),
            options: []
        )
    }

    private static func drawFigure(_ pose: Pose, into context: CGContext, mirrored: Bool) {
        let colorSpace = context.colorSpace ?? CGColorSpace(name: CGColorSpace.linearSRGB)!
        let boneColor = oklchColor(l: 0.88, c: 0.19, h: 125, colorSpace: colorSpace) // Theme.Palette.accent
        let jointColor = oklchColor(l: 0.96, c: 0.003, h: 260, colorSpace: colorSpace) // Theme.Palette.ink

        func point(_ joint: Joint) -> CGPoint? {
            guard let p = pose.joints[joint] else { return nil }
            let x = mirrored ? 1 - p.x : p.x
            return CGPoint(x: CGFloat(x) * imageSize.width, y: CGFloat(p.y) * imageSize.height)
        }

        context.setLineCap(.round)
        context.setLineWidth(10)
        context.setStrokeColor(boneColor)
        for bone in Pose.bones {
            guard let from = point(bone.from), let to = point(bone.to) else { continue }
            context.move(to: from)
            context.addLine(to: to)
        }
        context.strokePath()

        context.setFillColor(jointColor)
        for joint in Joint.allCases {
            guard let p = point(joint) else { continue }
            context.fillEllipse(in: CGRect(x: p.x - 8, y: p.y - 8, width: 16, height: 16))
        }
    }

    private static func oklchColor(l: Double, c: Double, h: Double, colorSpace: CGColorSpace) -> CGColor {
        let rgb = OKLCH.linearSRGB(l: l, c: c, h: h)
        let components: [CGFloat] = [CGFloat(rgb.red), CGFloat(rgb.green), CGFloat(rgb.blue), 1]
        return CGColor(colorSpace: colorSpace, components: components)
            ?? CGColor(red: components[0], green: components[1], blue: components[2], alpha: 1)
    }
}
#endif
