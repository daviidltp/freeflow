import SwiftUI

// Indicador de grabación "Dot scope": un campo de puntos iluminado por dos trazas
// trenzadas que siguen la voz. Port a Swift del indicador de Hex
// (https://github.com/anomalyco/hex, licencia MIT, src/rune_hud/dot_scope).
// Se portan las fases de grabar, procesar (look "Flow") y terminar; las variantes Sweep,
// Pulse y notch de Hex no se usan aquí.

// MARK: - Parámetros

enum DotScopeTuning {
    static let columns = 43
    static let rows = 9
    static let spacing: Float = 2.6
    /// Ancho de la placa al grabar y al procesar, en puntos.
    static let width: Float = 112
    static let processingWidth: Float = 76
    static let height: Float = 26
    static let braidSpeed: Float = 1
    static let helixCycles: Float = 1.6
    static let gain: Float = 1
    static let response: Float = 6.5
    static let release: Float = 0.15
    static let historySpeed: Float = 150
    static let phosphor: Float = 0.6
    static let glow: Float = 1
    static let shimmerPass: Float = 0.55
    static let shimmer: Float = 1
    static let transition: Float = 0.30
    static let bounce: Float = 0.15
}

enum DotScopeStage {
    case recording
    case processing
    /// Terminado: el campo se borra desde el centro hacia fuera y la placa se recoge.
    case done
}

/// Lo que dura la animación de terminar antes de cerrar la isla, en segundos: el borrado
/// dura 0,3 s y la placa empieza a recogerse a los 0,1 s (con su propio muelle de 0,3 s).
let dotScopeDoneDuration: TimeInterval = 0.42

// MARK: - Muelle analítico

/// Oscilador amortiguado exacto, independiente de la tasa de refresco.
struct DotSpring {
    var x: Float
    var v: Float = 0
    var target: Float

    init(at x: Float) {
        self.x = x
        self.target = x
    }

    mutating func jump(_ x: Float) {
        self.x = x
        v = 0
        target = x
    }

    mutating func step(to target: Float, duration: Float, bounce: Float, dt: Float) {
        self.target = target
        guard dt > 0, dt.isFinite else { return }
        let omega = 2 * Float.pi / max(duration, 0.01)
        let zeta: Float = bounce >= 0 ? max(1 - bounce, 0) : 1 / max(1 + bounce, 0.01)
        let x0 = x - target
        let v0 = v
        if zeta < 1 - 1e-4 {
            let decay = zeta * omega
            let omegaD = omega * (1 - zeta * zeta).squareRoot()
            let e = exp(-decay * dt)
            let s = sin(omegaD * dt)
            let c = cos(omegaD * dt)
            let sOverD = s / omegaD
            x = target + e * (x0 * (c + decay * sOverD) + v0 * sOverD)
            v = e * (-x0 * omega * omega * sOverD + v0 * (c - decay * sOverD))
        } else {
            // Amortiguamiento crítico: es el único otro caso que se usa aquí.
            let e = exp(-omega * dt)
            let b = v0 + omega * x0
            x = target + e * (x0 + b * dt)
            v = e * (b - omega * (x0 + b * dt))
        }
    }
}

// MARK: - Simulación

private func smoothstep(_ a: Float, _ b: Float, _ x: Float) -> Float {
    let t = min(max((x - a) / (b - a), 0), 1)
    return t * t * (3 - 2 * t)
}

private func bump(_ d: Float, _ w: Float) -> Float {
    exp(-(d / w) * (d / w))
}

private func passPosition(_ p: Float) -> Float {
    0.5 - 0.5 * cos(Float.pi * min(max(p, 0), 1))
}

private let step: Float = 1.0 / 240.0
private let historyLength = 512
private let samplesPerColumn = 3
private let speeds: [Float] = [0.8, 1.25, 1.85, 2.6]
private let baseWeights: [Float] = [0.55, 0.42, 0.3, 0.2]
private let spatialFreqs: [Float] = [1.4, 2.4, 3.8, 5.6]
private let startWidth: Float = 30
private let enterTime: Float = 0.42
private let phosphorHead: Float = 0.15
private let breathPeriod: Float = 5.5
private let hiddenScale: Float = 0.9
private let workHelix: Float = 2.6
private let flowSpacingShare: Float = 0.7
private let carrierRest: Float = 0.14
private let wipe: Float = 0.3
private let hiddenSoftness: Float = 3
/// Cuánto se ve el "hecho" antes de que la placa se recoja.
private let completedVisible: Float = 0.1

/// De `start` moviéndose a `speed` hasta parar en `end` mientras `t` va de 0 a 1 durante
/// el borrado: un Hermite cúbico, para que el final recoja el movimiento que interrumpe.
private func hermite(_ start: Float, _ speed: Float, _ end: Float, _ t0: Float) -> Float {
    let t = min(max(t0, 0), 1)
    let t2 = t * t
    let t3 = t2 * t
    return (2 * t3 - 3 * t2 + 1) * start
        + (t3 - 2 * t2 + t) * wipe * speed
        + (3 * t2 - 2 * t3) * end
}

/// Luz de las bandas de "Flow" en `x`.
private func flowLight(_ x: Float, offset: Float, spacing: Float) -> Float {
    let shifted = x - offset + spacing / 2
    let d = shifted - spacing * (shifted / spacing).rounded(.down) - spacing / 2
    return bump(d, 7)
}

private struct Voice {
    var level: Float = 0
    var reservoir: Float = 0
    var energy: Float = 0
    var kick: Float = 0
    var kickVelocity: Float = 0
    var band: Float = 0

    mutating func step(raw: Float, h: Float) {
        let previous = level
        let time: Float = raw > level ? 0.035 : 0.095
        level += (raw - level) * (1 - exp(-h / time))
        let rise = max((level - previous) / h, 0)
        reservoir += (1.75 * level * level - reservoir / 1.8) * h
        energy = 1 - exp(-reservoir * 1.45)
        let w = 2 * Float.pi * 1.3
        let z: Float = 0.22
        kickVelocity += (-w * w * kick - 2 * z * w * kickVelocity + 15 * rise + 2.2 * level) * h
        kick += kickVelocity * h
        let bandTime: Float = raw > band ? 0.025 : 0.14
        band += (raw - band) * (1 - exp(-h / bandTime))
    }
}

private struct Trace {
    var envelope: Float = 0
    var amplitude: Float = 0
    var amplitudeVelocity: Float = 0
    var glowFast: Float = 0
    var glowSpring: Float = 0
    var glowSpringVelocity: Float = 0
    var glowSlow: Float = 0
    var glow: Float = 0
    var phases: [Float]
    var history = [Float](repeating: 0, count: historyLength * 5)
    var head = 0

    init(phases: [Float]) {
        self.phases = phases
    }

    mutating func tick(voice: Voice, live: Float, speed: Float, h: Float) {
        func follow(_ value: inout Float, _ target: Float, _ rise: Float, _ fall: Float) {
            let time = target > value ? rise : fall
            value += (target - value) * (1 - exp(-h / time))
        }
        follow(&envelope, voice.level, 0.022, DotScopeTuning.release)
        let w = 2 * Float.pi * DotScopeTuning.response
        let z: Float = 0.52
        amplitudeVelocity += (-w * w * (amplitude - envelope) - 2 * z * w * amplitudeVelocity) * h
        amplitude += amplitudeVelocity * h
        follow(&glowFast, voice.level, 0.045, 0.13)
        let gw = 2 * Float.pi * 3.6
        let gz: Float = 0.5
        glowSpringVelocity += (-gw * gw * (glowSpring - glowFast) - 2 * gz * gw * glowSpringVelocity) * h
        glowSpring += glowSpringVelocity * h
        follow(&glowSlow, voice.level, 0.15, 0.7)
        let swell = 0.8 * max(glowSpring - 0.25, 0) + 0.04 * max(voice.kick, -0.5)
        glow = min(max(swell, 0) + 0.42 * glowSlow + 0.2 * voice.energy, 1.15) * live
        let go = 0.6 + 1.1 * min(envelope * 1.6, 1)
        for i in 0..<4 {
            phases[i] = (phases[i] + h * 2 * Float.pi * speeds[i] * go * speed)
                .truncatingRemainder(dividingBy: 2 * Float.pi)
        }
        let emphasis = 0.35 + 0.65 * min(voice.band / (voice.band + 0.06), 2)
        let offset = head * 5
        let amp = max(amplitude, 0) * live
        history[offset] = amp
        for c in 0..<4 {
            history[offset + 1 + c] = amp * baseWeights[c] * emphasis
        }
        head = (head + 1) % historyLength
    }

    func past(delay: Float, channel: Int) -> Float {
        let d = min(delay / step, Float(historyLength - 2))
        let i = Int(d.rounded(.down))
        let k = d - Float(i)
        let a = (head + 2 * historyLength - 1 - i) % historyLength
        let b = (a + historyLength - 1) % historyLength
        return history[a * 5 + channel] * (1 - k) + history[b * 5 + channel] * k
    }
}

/// Cómo se dibuja la traza ahora: el escáner que la despliega al empezar, o la luz que
/// la recorre mientras se procesa.
private enum Envelope {
    case enter(reach: Float, head: Float, unfold: Float)
    case work(offset: Float, spacing: Float, head: Float, swell: Float)
    /// Terminado: un frente borra el campo desde el centro mientras la luz de delante se apaga.
    case clear(front: Float, head: Float, offset: Float, spacing: Float, glow: Float, swell: Float)
}

private struct Scan {
    var helix: Float
    var grid: Float
    var decay: Float = 1
    var tail: Float = 1
    var envelope: Envelope

    /// (amplitud, brillo, hinchazón) en `x`.
    func at(_ x: Float) -> (Float, Float, Float) {
        switch envelope {
        case let .enter(reach, head, unfold):
            let d = abs(x)
            let drawn = unfold * (1 - smoothstep(max(reach - 14, 0), max(reach, 0.001), d))
            let amplitude = drawn * (1 - smoothstep(max(reach - 22, 0), max(reach - 3, 0.001), d))
            let beam = head * bump(d - reach, 6)
            let swell = 1.8 * unfold * (head / 2.8) * bump(d - max(reach - 14, 0), 14)
            return (amplitude, amplitude + beam, swell)
        case let .work(offset, spacing, head, swell):
            let light = flowLight(x, offset: offset, spacing: spacing)
            return (1, 1 + head * light, swell * light)
        case let .clear(front, head, offset, spacing, glow, swell):
            let d = abs(x)
            let keep = smoothstep(front - 12, front - 2, d)
            let light = flowLight(x, offset: offset, spacing: spacing)
            return (keep, keep * (1 + glow * light) + head * bump(d - front, 6), keep * swell * light)
        }
    }
}

/// Simulación del indicador. Se avanza en pasos fijos de 240 Hz, así cualquier tasa de
/// refresco dibuja lo mismo.
/// Todo su estado se toca solo desde `queue`.
final class DotScopeSimulation: @unchecked Sendable {
    private let columns = DotScopeTuning.columns
    private let rows = DotScopeTuning.rows
    private let sampleCount: Int

    private var stage: DotScopeStage = .recording
    private var elapsed: Float = 0
    private var flowOffset: Float = 0
    private var flowTurn: Float = 0
    private var voices = [Voice(), Voice()]
    private var traces = [
        Trace(phases: [0.1, 1.7, 3.3, 4.6]),
        Trace(phases: [2.4, 0.6, 5.1, 1.9]),
    ]
    private var live: Float = 0
    private var carrier: Float = 0
    private var time: Float = 0
    private var steps: UInt64 = 0
    private var pending: Float = 0
    /// Velocidad del frente de borrado al empezar a terminar, pt/s.
    private var speedAtDone: Float = 0
    private var reducedMotion = false
    private var headLight: [[Float]]
    private var tailLight: [[Float]]
    private var ys: [[Float]]
    private var brightness: [[Float]]
    private(set) var grid: Float = 0
    private var width = DotSpring(at: startWidth)
    private var opacitySpring = DotSpring(at: 0)
    private var scaleSpring = DotSpring(at: hiddenScale)
    private var softnessSpring = DotSpring(at: hiddenSoftness)
    private var coolSpring = DotSpring(at: 0)
    private var lastDate: Date?

    /// Para cada punto, (brillo, frescura), fila a fila.
    private(set) var dots: [(Float, Float)]

    init() {
        let dotCount = DotScopeTuning.columns * DotScopeTuning.rows
        sampleCount = (DotScopeTuning.columns - 1) * samplesPerColumn + 1
        headLight = [[Float](repeating: 0, count: dotCount), [Float](repeating: 0, count: dotCount)]
        tailLight = headLight
        ys = [[Float](repeating: 0, count: sampleCount), [Float](repeating: 0, count: sampleCount)]
        brightness = ys
        dots = [(Float, Float)](repeating: (0, 0), count: dotCount)
    }

    /// Cola donde vive la simulación: el dibujo va fuera del hilo principal, así la animación
    /// no se para cuando la app está ocupada (por ejemplo, justo al dejar de grabar).
    let queue = DispatchQueue(label: "app.freeflow.dotscope", qos: .userInteractive)

    /// Empieza una grabación desde cero. Se puede llamar desde cualquier hilo.
    func restart() {
        queue.async { self.resetState() }
    }

    private func resetState() {
        let fresh = DotScopeSimulation()
        stage = .recording
        elapsed = 0
        flowOffset = 0
        flowTurn = 0
        voices = fresh.voices
        traces = fresh.traces
        live = 0
        carrier = 0
        time = 0
        steps = 0
        pending = 0
        headLight = fresh.headLight
        tailLight = fresh.tailLight
        ys = fresh.ys
        brightness = fresh.brightness
        grid = 0
        width = DotSpring(at: startWidth)
        opacitySpring = DotSpring(at: 0)
        scaleSpring = DotSpring(at: hiddenScale)
        softnessSpring = DotSpring(at: hiddenSoftness)
        coolSpring = DotSpring(at: 0)
        speedAtDone = 0
        dots = fresh.dots
        lastDate = nil
    }

    var opacity: Float { min(max(opacitySpring.x, 0), 1) }
    var scale: Float { max(scaleSpring.x, 0.01) }
    var cool: Float { min(max(coolSpring.x, 0), 1) }
    /// Desenfoque de la placa al aparecer y al recogerse, en puntos.
    var softness: Float { min(max(softnessSpring.x, 0), hiddenSoftness) }
    var plateWidth: Float { max(width.x, DotScopeTuning.height) }
    var presence: Float { 0.5 + 0.5 * max(live, cool) }

    /// Brillo del halo detrás de la voz, 0 a 1.15.
    var glow: Float {
        (traces[0].glow + traces[1].glow) / 2 * DotScopeTuning.glow
    }

    /// Avanza hasta `date`. `level` es el nivel de la voz, de 0 a 1.
    func advance(to date: Date, stage newStage: DotScopeStage, level: Float, reduceMotion: Bool = false) {
        let dt = Float(lastDate.map { date.timeIntervalSince($0) } ?? 0)
        lastDate = date
        reducedMotion = reduceMotion
        if newStage != stage {
            if newStage == .processing {
                flowOffset = -width.x / 2 - 4
            }
            if newStage == .done {
                speedAtDone = 1.5 * pulseSpeed
            }
            stage = newStage
            elapsed = 0
        }
        pending += min(max(dt, 0), 0.25)
        while pending >= step {
            pending -= step
            advanceStep(level: level, reduceMotion: reduceMotion)
        }
    }

    private var workPeriod: Float { 2 * max(DotScopeTuning.shimmerPass, 0.05) }
    private var flowSpacing: Float { flowSpacingShare * DotScopeTuning.processingWidth }
    private var flowSpeed: Float { flowSpacing / workPeriod }
    private var pulseSpeed: Float {
        (DotScopeTuning.processingWidth / 2 + 12) / (1.4 * workPeriod)
    }
    private var flowTurnHz: Float {
        flowSpeed * DotScopeTuning.helixCycles / max(width.x, 1)
    }

    private func advanceStep(level raw: Float, reduceMotion: Bool) {
        let h = step
        let recording = stage == .recording
        let level = recording ? min(max(raw * DotScopeTuning.gain, 0), 1) : 0
        voices[0].step(raw: level, h: h)
        voices[1].step(raw: level * 0.85, h: h)
        live += ((recording ? 1 : 0) - live) * (1 - exp(-h / 0.55))
        let speed: Float = reduceMotion ? 0 : DotScopeTuning.braidSpeed
        for k in 0..<2 {
            traces[k].tick(voice: voices[k], live: live, speed: speed, h: h)
        }
        let energy = max(voices[0].energy, voices[1].energy)
        let working = stage == .processing || stage == .done
        flowTurn += ((working ? 1 : 0) - flowTurn) * (1 - exp(-h / 0.25))
        if working {
            flowOffset += flowSpeed * h
        }
        let rest = carrierRest + 0.22 * energy
        let turn = rest + (flowTurnHz - rest) * flowTurn
        carrier = (carrier + h * 2 * Float.pi * turn * speed).truncatingRemainder(dividingBy: 2 * Float.pi)

        let targetWidth = recording ? DotScopeTuning.width : DotScopeTuning.processingWidth
        let duration = DotScopeTuning.transition
        let bounce = DotScopeTuning.bounce
        // Al terminar, la placa se ve un instante y luego se recoge.
        let visible = !(stage == .done && elapsed >= completedVisible)
        if reduceMotion {
            width.jump(targetWidth)
            scaleSpring.jump(1)
            softnessSpring.jump(0)
            opacitySpring.step(to: visible ? 1 : 0, duration: 0.16, bounce: 0, dt: h)
            coolSpring.step(to: working ? 1 : 0, duration: 0.16, bounce: 0, dt: h)
        } else {
            width.step(to: targetWidth, duration: duration, bounce: bounce, dt: h)
            opacitySpring.step(to: visible ? 1 : 0, duration: duration, bounce: 0, dt: h)
            scaleSpring.step(to: visible ? 1 : hiddenScale, duration: duration, bounce: bounce, dt: h)
            softnessSpring.step(to: visible ? 0 : hiddenSoftness, duration: duration, bounce: 0, dt: h)
            coolSpring.step(to: working ? 1 : 0, duration: duration, bounce: 0, dt: h)
        }

        elapsed += h
        time += h
        steps += 1
        if steps % 2 == 0 {
            beam(hb: 2 * h)
        }
    }

    private func scan(width: Float) -> Scan {
        let e = elapsed
        switch stage {
        case .recording:
            return Scan(
                helix: 1,
                grid: min(e / 0.3, 1),
                envelope: .enter(
                    reach: (width / 2 + 12) * passPosition(e / enterTime),
                    head: 2.8 * (1 - smoothstep(0.08, enterTime, e)),
                    unfold: smoothstep(0, 0.1, e)
                )
            )
        case .processing:
            let enter = smoothstep(0, 0.35, e)
            return Scan(
                helix: 1 + (workHelix - 1) * enter,
                grid: 1,
                envelope: .work(
                    offset: flowOffset,
                    spacing: flowSpacing,
                    head: 2.5 * smoothstep(0.05, 0.3, e) * DotScopeTuning.shimmer,
                    swell: 0.9 * enter
                )
            )
        case .done:
            return Scan(
                helix: workHelix,
                grid: 1 - smoothstep(0.2, 0.4, e),
                decay: 1 - 0.6 * smoothstep(0, 0.12, e),
                tail: 1 - smoothstep(0, 0.15, e),
                envelope: .clear(
                    front: hermite(0, speedAtDone, width / 2 + 8, e / wipe),
                    head: 2.8 * smoothstep(0, 0.04, e) * (1 - smoothstep(0.22, 0.32, e)),
                    offset: flowOffset,
                    spacing: flowSpacing,
                    glow: 2.5 * DotScopeTuning.shimmer * (1 - smoothstep(0, 0.18, e)),
                    swell: 0.9
                )
            )
        }
    }

    /// Dibuja las dos trazas en el campo de puntos y apaga el fósforo.
    private func beam(hb: Float) {
        let sub = samplesPerColumn
        let samples = sampleCount
        let pitch = DotScopeTuning.spacing
        let width = plateWidth
        let scan = scan(width: width)
        grid = scan.grid
        let mid = Float(rows - 1) / 2
        let half = mid - 0.55
        let breath: Float = reducedMotion ? 0.5 : 0.5 + 0.5 * sin(time * 2 * Float.pi / breathPeriod)
        let rest = (0.55 + 0.35 * breath) * (0.4 + 0.6 * live) * scan.helix
        let halfWidth = width / 2

        for k in 0..<2 {
            let sign: Float = k == 0 ? 1 : -1
            for s in 0..<samples {
                let x = (Float(s) / Float(sub) - Float(columns - 1) / 2) * pitch
                if abs(x) > halfWidth {
                    ys[k][s] = mid
                    brightness[k][s] = 0
                    continue
                }
                let (amplitude, bright, swell) = scan.at(x)
                let own = abs(x)
                let xn = (x + halfWidth) / width
                let ends = min(
                    smoothstep(-halfWidth + 3, -halfWidth + 17, x),
                    smoothstep(-halfWidth + 3, -halfWidth + 17, -x)
                )
                let reach = 1 - 0.8 * smoothstep(14, halfWidth, own)
                let delay = own / DotScopeTuning.historySpeed
                let a = traces[k].past(delay: delay, channel: 0)
                var spread: Float = 0
                for c in 0..<4 {
                    spread += traces[k].past(delay: delay, channel: 1 + c)
                        * sin(2 * Float.pi * spatialFreqs[c] * xn - traces[k].phases[c])
                }
                let helix = (rest + swell + half * 0.55 * a * reach)
                    * sin(2 * Float.pi * DotScopeTuning.helixCycles * xn - carrier)
                let y = half * tanh((helix + half * 0.7 * spread * reach) / half) * ends * amplitude
                ys[k][s] = mid - sign * y
                let spatial = (0.3 + 0.7 * min(a * 1.8, 1)) * (0.45 + 0.55 * ends)
                brightness[k][s] = spatial * amplitude + 0.36 * max(bright - amplitude, 0)
            }
            for s in 0..<samples {
                let slope = (ys[k][min(s + 1, samples - 1)] - ys[k][max(s - 1, 0)]) * Float(sub) / 2
                brightness[k][s] *= 1 - 0.55 + 0.55 / (1 + 0.22 * slope * slope).squareRoot()
            }
        }

        let headKeep = exp(-hb / (phosphorHead * scan.decay))
        let tailKeep = exp(-hb / (DotScopeTuning.phosphor * scan.decay))
        let dx = 1 / Float(sub)
        for i in 0..<columns {
            let s0 = max(i - 3, 0) * sub
            let s1 = min((i + 3) * sub, samples - 1)
            for j in 0..<rows {
                let n = j * columns + i
                var now: Float = 0
                var total: Float = 0
                var lit: [Float] = [0, 0]
                for k in 0..<2 {
                    var best = Float.greatestFiniteMagnitude
                    var nearest = i * sub
                    for s in s0..<s1 {
                        let ay = ys[k][s]
                        let dy = ys[k][s + 1] - ay
                        let px = Float(i) - Float(s) * dx
                        let py = Float(j) - ay
                        let t = min(max((px * dx + py * dy) / (dx * dx + dy * dy), 0), 1)
                        let ex = px - t * dx
                        let ey = py - t * dy
                        let d2 = ex * ex + ey * ey
                        if d2 < best {
                            best = d2
                            nearest = s
                        }
                    }
                    let b = brightness[k][nearest]
                    let onBeam = exp(-best / 0.25)
                    let instant = min(onBeam + 0.5 * exp(-best.squareRoot() / 0.8), 1.2) * b
                    let core = onBeam * b
                    headLight[k][n] = max(headLight[k][n] * headKeep, core)
                    tailLight[k][n] = max(tailLight[k][n] * tailKeep, core)
                    let light = max(instant, headLight[k][n], 0.55 * scan.tail * tailLight[k][n])
                    lit[k] = light
                    now += instant
                    total += light
                }
                let power = 1 - (1 - min(lit[0], 1)) * (1 - min(lit[1], 1))
                dots[n] = (min(max(power, 0), 1), min(now / max(total, 1e-4), 1))
            }
        }
    }
}

// MARK: - Estilo del chip

/// Qué se ve en la isla mientras grabas y procesas: las barras de siempre o los puntos de Hex.
enum IslandChipStyle: String, CaseIterable, Identifiable {
    case classic
    case dots

    static let storageKey = "island_chip_style"

    var id: String { rawValue }

    static var current: IslandChipStyle {
        IslandChipStyle(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .classic
    }

    var label: String {
        switch self {
        case .classic: return "Clásico"
        case .dots: return "Puntos (Hex)"
        }
    }
}

// MARK: - Tema

/// Tema del chip mientras grabas y procesas: sigue al sistema o se fija en claro u oscuro.
enum IslandThemePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let storageKey = "island_theme"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "Automático"
        case .light: return "Claro"
        case .dark: return "Oscuro"
        }
    }

    /// Si el chip va oscuro, dado el aspecto actual del sistema.
    func isDark(system: ColorScheme) -> Bool {
        switch self {
        case .system: return system == .dark
        case .light: return false
        case .dark: return true
        }
    }
}

/// Colores de Hex para cada tema: perla cálida al grabar y azul al procesar.
struct DotScopePalette {
    let you: [Float]
    let youCore: [Float]
    let agent: [Float]
    let agentCore: [Float]
    let plate: Color
    let rim: Color
    /// Transparencia de los puntos apagados, del brillo máximo y curva de encendido.
    let unlit: Float
    let full: Float
    let curve: Float
    let glowStrength: Float
    /// Los mismos colores de placa y borde para dibujar con Core Graphics fuera del hilo principal.
    let plateCG: CGColor
    let rimCG: CGColor

    static func forDark(_ dark: Bool) -> DotScopePalette {
        dark
            ? DotScopePalette(
                you: [0.86, 0.83, 0.77], youCore: [0.98, 0.96, 0.92],
                agent: [0.70, 0.78, 0.90], agentCore: [0.92, 0.95, 1.0],
                plate: Color(.sRGB, red: 17 / 255, green: 17 / 255, blue: 20 / 255, opacity: 0.94),
                rim: Color.white.opacity(0.11),
                unlit: 0.07, full: 0.96, curve: 0.9, glowStrength: 0.3,
                plateCG: CGColor(srgbRed: 17 / 255, green: 17 / 255, blue: 20 / 255, alpha: 0.94),
                rimCG: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.11)
            )
            : DotScopePalette(
                you: [0.62, 0.53, 0.40], youCore: [0.47, 0.38, 0.26],
                agent: [0.40, 0.47, 0.58], agentCore: [0.24, 0.31, 0.43],
                plate: Color(.sRGB, red: 252 / 255, green: 251 / 255, blue: 249 / 255, opacity: 0.96),
                rim: Color.black.opacity(0.09),
                unlit: 0.085, full: 1.0, curve: 0.75, glowStrength: 0.19,
                plateCG: CGColor(srgbRed: 252 / 255, green: 251 / 255, blue: 249 / 255, alpha: 0.96),
                rimCG: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.09)
            )
    }
}

// MARK: - Vista

/// Lo que la vista pide a la simulación; se comparte entre el hilo principal y el de dibujo.
private struct DotScopeInputs {
    var stage: DotScopeStage = .recording
    var level: Float = 0
    var vertical = false
    var dark = true
    var reduceMotion = false
}

/// Capa que dibuja el indicador en su propia cola a 60 fps. Core Animation compone la imagen
/// sin pasar por el hilo principal, así que el indicador sigue fluido aunque la app esté ocupada.
/// Las entradas van protegidas por `lock` y el dibujo solo ocurre en la cola de la simulación.
final class DotScopeLayerView: NSView, @unchecked Sendable {
    private let simulation: DotScopeSimulation
    private let lock = NSLock()
    private var inputs = DotScopeInputs()
    private var timer: DispatchSourceTimer?
    private var backingScale: CGFloat = 2
    private let plateSize: CGSize
    /// Capa propia: se toca desde la cola de dibujo sin pasar por la API de NSView.
    private let drawLayer = CALayer()
    static let margin: CGFloat = 10

    init(simulation: DotScopeSimulation) {
        self.simulation = simulation
        plateSize = CGSize(width: CGFloat(DotScopeTuning.width), height: CGFloat(DotScopeTuning.height))
        super.init(frame: .zero)
        drawLayer.contentsGravity = .resize
        drawLayer.masksToBounds = false
        layer = drawLayer
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func update(stage: DotScopeStage, level: Float, vertical: Bool, dark: Bool, reduceMotion: Bool) {
        lock.lock()
        inputs = DotScopeInputs(stage: stage, level: level, vertical: vertical, dark: dark, reduceMotion: reduceMotion)
        lock.unlock()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {
            backingScale = window.backingScaleFactor
            drawLayer.contentsScale = backingScale
            start()
        } else {
            stop()
        }
    }

    private func start() {
        guard timer == nil else { return }
        let source = DispatchSource.makeTimerSource(queue: simulation.queue)
        source.schedule(deadline: .now(), repeating: .nanoseconds(16_666_667), leeway: .milliseconds(1))
        source.setEventHandler { [weak self] in self?.tick() }
        timer = source
        source.resume()
    }

    private func stop() {
        timer?.cancel()
        timer = nil
    }

    deinit {
        timer?.cancel()
    }

    /// En la cola de la simulación.
    private func tick() {
        lock.lock()
        let current = inputs
        lock.unlock()
        simulation.advance(to: Date(), stage: current.stage, level: current.level, reduceMotion: current.reduceMotion)
        guard let image = render(current) else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        drawLayer.contents = image
        CATransaction.commit()
    }

    // MARK: Dibujo

    private func render(_ inputs: DotScopeInputs) -> CGImage? {
        let m = Self.margin
        let along = plateSize.width + m * 2
        let across = plateSize.height + m * 2
        let size = inputs.vertical ? CGSize(width: across, height: along) : CGSize(width: along, height: across)
        let scale = backingScale
        guard let ctx = CGContext(
            data: nil,
            width: Int(size.width * scale),
            height: Int(size.height * scale),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        // Origen en el centro y el eje y hacia abajo, como en el resto del dibujo.
        ctx.translateBy(x: size.width / 2, y: size.height / 2)
        ctx.scaleBy(x: 1, y: -1)
        if inputs.vertical {
            ctx.rotate(by: .pi / 2)
        }
        draw(in: ctx, dark: inputs.dark)
        return ctx.makeImage()
    }

    private func mix(_ a: [Float], _ b: [Float], _ t: Float) -> [Float] {
        [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t]
    }

    private func cg(_ c: [Float], _ alpha: Float) -> CGColor {
        CGColor(srgbRed: CGFloat(c[0]), green: CGFloat(c[1]), blue: CGFloat(c[2]), alpha: CGFloat(min(max(alpha, 0), 1)))
    }

    private func draw(in ctx: CGContext, dark: Bool) {
        let sim = simulation
        let palette = DotScopePalette.forDark(dark)
        let cool = sim.cool
        let base = mix(palette.you, palette.agent, cool)
        let core = mix(palette.youCore, palette.agentCore, cool)

        ctx.setAlpha(CGFloat(sim.opacity))
        let scale = CGFloat(sim.scale)
        ctx.scaleBy(x: scale, y: scale)

        let pitch = DotScopeTuning.spacing
        let halfW = sim.plateWidth / 2
        let halfH = DotScopeTuning.height / 2
        let radius = halfH
        let glow = sim.glow

        // Placa con sombra y borde fino.
        let plateRect = CGRect(x: CGFloat(-halfW), y: CGFloat(-halfH), width: CGFloat(halfW * 2), height: CGFloat(halfH * 2))
        let platePath = CGPath(roundedRect: plateRect, cornerWidth: CGFloat(radius), cornerHeight: CGFloat(radius), transform: nil)
        ctx.saveGState()
        let shadow = dark
            ? CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.45)
            : CGColor(srgbRed: 20 / 255, green: 24 / 255, blue: 40 / 255, alpha: 0.2)
        // La sombra no sigue la transformación: en el espacio del bitmap, hacia abajo es negativo.
        ctx.setShadow(offset: CGSize(width: 0, height: -3 * backingScale), blur: 10 * backingScale, color: shadow)
        ctx.addPath(platePath)
        ctx.setFillColor(palette.plateCG)
        ctx.fillPath()
        ctx.restoreGState()
        let rimRect = plateRect.insetBy(dx: 0.5, dy: 0.5)
        ctx.addPath(CGPath(roundedRect: rimRect, cornerWidth: CGFloat(radius) - 0.5, cornerHeight: CGFloat(radius) - 0.5, transform: nil))
        ctx.setStrokeColor(palette.rimCG)
        ctx.setLineWidth(1)
        ctx.strokePath()

        ctx.saveGState()
        ctx.addPath(platePath)
        ctx.clip()

        // Halo detrás de la voz.
        if glow > 0.01 {
            let reach = CGFloat(34 + 20 * glow)
            let strength = palette.glowStrength * 0.55 * min(1, glow)
            let middle = mix(base, core, 0.5)
            if let gradient = CGGradient(
                colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                colors: [cg(middle, strength), cg(base, 0)] as CFArray,
                locations: [0, 1]
            ) {
                ctx.drawRadialGradient(gradient, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: reach, options: [])
            }
        }

        let presence = sim.presence
        let grid = sim.grid
        let dots = sim.dots
        let columns = DotScopeTuning.columns
        let centerX = Float(columns - 1) / 2
        let centerY = Float(DotScopeTuning.rows - 1) / 2

        for j in 0..<DotScopeTuning.rows {
            for i in 0..<columns {
                let cx = (Float(i) - centerX) * pitch
                let cy = (Float(j) - centerY) * pitch
                let qx = abs(cx) - halfW + radius
                let qy = abs(cy) - halfH + radius
                let outside = (max(qx, 0) * max(qx, 0) + max(qy, 0) * max(qy, 0)).squareRoot()
                let distance = outside + min(max(qx, qy), 0) - radius
                let mask = smoothstep(1.4, 4.6, -distance)
                if mask <= 0 { continue }

                let (power0, fresh) = dots[j * columns + i]
                let power = max(power0, 1e-5)
                let row = abs(cy) / halfH
                let floorAlpha = palette.unlit * (1 - 0.7 * smoothstep(0.35, 0.95, row)) * presence * grid
                let alpha = floorAlpha + (palette.full - floorAlpha)
                    * pow(power, palette.curve * (1.4 - 0.4 * fresh))
                let dotRadius = (0.25 + 0.17 * pow(power, 0.6))
                    * (1 + ((0.82 + 0.18 * fresh) - 1) * smoothstep(0.03, 0.2, power)) * pitch
                let coreMix = min(max(power * power * 1.1, 0), 0.9) * (0.3 + 0.7 * fresh)
                let color = mix(base, core, coreMix)
                let x = CGFloat(cx)
                let y = CGFloat(cy)
                if power > 0.05 {
                    let r = CGFloat(dotRadius * 2)
                    ctx.setFillColor(cg(color, 0.132 * power * power * mask))
                    ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
                }
                let r = CGFloat(dotRadius)
                ctx.setFillColor(cg(color, alpha * mask))
                ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
            }
        }
        ctx.restoreGState()
    }
}

/// Dibuja el indicador sobre su propia placa, con los colores de Hex.
struct DotScopeView: NSViewRepresentable {
    let simulation: DotScopeSimulation
    let stage: DotScopeStage
    /// Nivel de la voz de 0 a 1 (el que ya normaliza AudioRecorder).
    let level: Float
    /// En los bordes laterales la isla va en vertical: se dibuja girada 90°.
    var vertical = false
    var dark = true
    var reduceMotion = false

    func makeNSView(context: Context) -> DotScopeLayerView {
        let view = DotScopeLayerView(simulation: simulation)
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: DotScopeLayerView, context: Context) {
        view.update(stage: stage, level: level, vertical: vertical, dark: dark, reduceMotion: reduceMotion)
    }

    /// El lienzo es algo más grande que la placa (por la sombra), pero ocupa lo que la placa.
    func sized() -> some View {
        let m = DotScopeLayerView.margin
        let along = CGFloat(DotScopeTuning.width)
        let across = CGFloat(DotScopeTuning.height)
        return self
            .frame(width: (vertical ? across : along) + m * 2, height: (vertical ? along : across) + m * 2)
            .frame(width: vertical ? across : along, height: vertical ? along : across)
            .allowsHitTesting(false)
    }
}
