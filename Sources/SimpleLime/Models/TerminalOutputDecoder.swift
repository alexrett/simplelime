import Foundation

final class TerminalOutputDecoder {
    private enum ParserState {
        case normal
        case escape
        case controlSequence
        case operatingSystemCommand
        case operatingSystemCommandEscape
        case characterSet
    }

    private var state: ParserState = .normal
    private var pendingCarriageReturn = false

    func append(_ rawOutput: [UInt8], to output: inout String) {
        append(String(decoding: rawOutput, as: UTF8.self), to: &output)
    }

    func append(_ rawOutput: String, to output: inout String) {
        for scalar in rawOutput.unicodeScalars {
            consume(scalar, output: &output)
        }
    }

    func reset() {
        state = .normal
        pendingCarriageReturn = false
    }

    private func consume(_ scalar: UnicodeScalar, output: inout String) {
        if pendingCarriageReturn {
            if scalar.value == 0x0A {
                pendingCarriageReturn = false
                output.append("\n")
                return
            }

            pendingCarriageReturn = false
            replaceCurrentLine(in: &output, with: "")
        }

        switch state {
        case .normal:
            consumeNormal(scalar, output: &output)
        case .escape:
            consumeEscape(scalar)
        case .controlSequence:
            if scalar.isANSISequenceTerminator {
                state = .normal
            }
        case .operatingSystemCommand:
            if scalar.value == 0x07 {
                state = .normal
            } else if scalar.value == 0x1B {
                state = .operatingSystemCommandEscape
            }
        case .operatingSystemCommandEscape:
            state = scalar.value == 0x5C ? .normal : .operatingSystemCommand
        case .characterSet:
            state = .normal
        }
    }

    private func consumeNormal(_ scalar: UnicodeScalar, output: inout String) {
        switch scalar.value {
        case 0x1B:
            state = .escape
        case 0x9B:
            state = .controlSequence
        case 0x9D:
            state = .operatingSystemCommand
        case 0x0D:
            pendingCarriageReturn = true
        case 0x08, 0x7F:
            removeLastPrintableCharacter(from: &output)
        case 0x07, 0x00:
            break
        default:
            if scalar.isPrintableTerminalScalar {
                output.append(String(scalar))
            }
        }
    }

    private func consumeEscape(_ scalar: UnicodeScalar) {
        switch scalar.value {
        case 0x5B:
            state = .controlSequence
        case 0x5D:
            state = .operatingSystemCommand
        case 0x28, 0x29:
            state = .characterSet
        default:
            state = .normal
        }
    }

    private func replaceCurrentLine(in output: inout String, with replacement: String) {
        if let newlineIndex = output.lastIndex(of: "\n") {
            let start = output.index(after: newlineIndex)
            output.replaceSubrange(start..<output.endIndex, with: replacement)
        } else {
            output = replacement
        }
    }

    private func removeLastPrintableCharacter(from output: inout String) {
        guard let last = output.last, last != "\n" else { return }
        output.removeLast()
    }
}

private extension UnicodeScalar {
    var isANSISequenceTerminator: Bool {
        return value >= 0x40 && value <= 0x7E
    }

    var isPrintableTerminalScalar: Bool {
        if value == 0x0A || value == 0x09 {
            return true
        }

        return value >= 0x20 && value != 0x7F && !(value >= 0x80 && value <= 0x9F)
    }
}
