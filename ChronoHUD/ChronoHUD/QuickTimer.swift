import AppKit
import Foundation
import Observation

enum QuickTimerParseError: Error, Equatable {
    case empty
    case invalidFormat
    case outOfRange
}

struct QuickTimerParser {
    private static let maximumDuration: TimeInterval = 86_400

    static func parse(_ input: String) throws -> TimeInterval {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw QuickTimerParseError.empty }
        guard value.unicodeScalars.allSatisfy({ $0.isASCII }) else {
            throw QuickTimerParseError.invalidFormat
        }

        let lowered = value.lowercased()
        let seconds: TimeInterval
        if let components = match(#"^([0-9]+)h([0-9]+)m?$"#, in: lowered) {
            let hours = try asciiInteger(components[1])
            let minutes = try asciiInteger(components[2])
            guard hours > 0 else { throw QuickTimerParseError.invalidFormat }
            guard minutes < 60 else { throw QuickTimerParseError.invalidFormat }
            seconds = try combinedSeconds(hours: hours, minutes: minutes)
        } else if let components = match(#"^([0-9]+)h[ ]+([0-9]+)m$"#, in: lowered) {
            let hours = try asciiInteger(components[1])
            let minutes = try asciiInteger(components[2])
            guard hours > 0 else { throw QuickTimerParseError.invalidFormat }
            guard minutes < 60 else { throw QuickTimerParseError.invalidFormat }
            seconds = try combinedSeconds(hours: hours, minutes: minutes)
        } else if let components = match(#"^([0-9]+)h$"#, in: lowered) {
            seconds = try multipliedSeconds(components[1], multiplier: 3_600)
        } else if let components = match(#"^([0-9]+)m$"#, in: lowered) {
            seconds = try multipliedSeconds(components[1], multiplier: 60)
        } else if let components = match(#"^([0-9]+)s$"#, in: lowered) {
            seconds = try multipliedSeconds(components[1], multiplier: 1)
        } else if lowered.allSatisfy({ $0.isASCII && $0.isNumber }) {
            seconds = try multipliedSeconds(lowered, multiplier: 60)
        } else {
            throw QuickTimerParseError.invalidFormat
        }

        guard seconds >= 1, seconds <= maximumDuration else { throw QuickTimerParseError.outOfRange }
        return seconds
    }

    private static func match(_ pattern: String, in value: String) -> [String]? {
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let result = expression.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              result.range == NSRange(value.startIndex..., in: value) else { return nil }
        return (0..<result.numberOfRanges).map { index in
            let range = result.range(at: index)
            guard range.location != NSNotFound, let swiftRange = Range(range, in: value) else { return "" }
            return String(value[swiftRange])
        }
    }

    private static func asciiInteger(_ value: String) throws -> UInt64 {
        guard !value.isEmpty, value.allSatisfy({ $0.isASCII && $0.isNumber }), let number = UInt64(value) else {
            throw QuickTimerParseError.outOfRange
        }
        return number
    }

    private static func multipliedSeconds(_ value: String, multiplier: UInt64) throws -> TimeInterval {
        let number = try asciiInteger(value)
        let (result, overflow) = number.multipliedReportingOverflow(by: multiplier)
        guard !overflow else { throw QuickTimerParseError.outOfRange }
        return TimeInterval(result)
    }

    private static func combinedSeconds(hours: UInt64, minutes: UInt64) throws -> TimeInterval {
        let (hourSeconds, multiplyOverflow) = hours.multipliedReportingOverflow(by: 3_600)
        let (result, addOverflow) = hourSeconds.addingReportingOverflow(minutes * 60)
        guard !multiplyOverflow, !addOverflow else { throw QuickTimerParseError.outOfRange }
        return TimeInterval(result)
    }
}

enum QuickTimerConfirmationOrigin: Equatable {
    case sessionKnownAtSubmit
    case sessionBecameActive
}

enum QuickTimerPanelPhase: Equatable {
    case entry(error: QuickTimerParseError?)
    case confirmation(duration: TimeInterval, origin: QuickTimerConfirmationOrigin)
}

enum QuickTimerSubmissionPolicy: Equatable {
    case requireIdle
    case replaceIfActive
}

enum QuickTimerSubmissionResult: Equatable {
    case started
    case confirmationRequired(QuickTimerConfirmationOrigin)
}

@MainActor @Observable
final class QuickTimerPanelModel {
    var input = "" {
        didSet {
            if case .entry(let error) = phase, error != nil { phase = .entry(error: nil) }
        }
    }
    var phase: QuickTimerPanelPhase = .entry(error: nil)

    @discardableResult
    func submit(
        optionPressed: Bool,
        sessionIsActive: Bool,
        validationFeedback: () -> Void = {},
        action: (TimeInterval, QuickTimerSubmissionPolicy) throws -> QuickTimerSubmissionResult
    ) throws -> Bool {
        let duration: TimeInterval
        switch phase {
        case .entry:
            do { duration = try QuickTimerParser.parse(input) }
            catch let error as QuickTimerParseError {
                phase = .entry(error: error)
                validationFeedback()
                return false
            } catch {
                phase = .entry(error: .invalidFormat)
                validationFeedback()
                return false
            }
            if sessionIsActive && !optionPressed {
                phase = .confirmation(duration: duration, origin: .sessionKnownAtSubmit)
                return false
            }
        case .confirmation(let confirmedDuration, _):
            duration = confirmedDuration
        }

        let policy: QuickTimerSubmissionPolicy = (optionPressed || sessionIsActive || isConfirming) ? .replaceIfActive : .requireIdle
        switch try action(duration, policy) {
        case .started: return true
        case .confirmationRequired(let origin):
            phase = .confirmation(duration: duration, origin: origin)
            return false
        }
    }

    func escape() -> Bool {
        if case .confirmation = phase {
            phase = .entry(error: nil)
            return false
        }
        return true
    }

    func sessionActivityChanged(isActive: Bool) {
        guard !isActive, case .confirmation = phase else { return }
        phase = .entry(error: nil)
    }

    private var isConfirming: Bool {
        if case .confirmation = phase { return true }
        return false
    }
}

struct QuickTimerPlacementTarget {
    let mouseLocation: NSPoint
    let screenFrame: NSRect
    let visibleFrame: NSRect

    @MainActor
    static func capture() -> QuickTimerPlacementTarget? {
        let location = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(location) }) ?? NSScreen.main ?? NSScreen.screens.first else {
            return nil
        }
        return QuickTimerPlacementTarget(mouseLocation: location, screenFrame: screen.frame, visibleFrame: screen.visibleFrame)
    }
}
