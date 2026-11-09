import Foundation

/// A run of an answer's lines: prose, or the inside of one fenced code block.
struct AnswerBlock: Equatable {
    enum Kind: Equatable {
        case prose
        /// A fenced block and its info string's first word, lowercased (`toml`, `python`, or empty).
        case code(String)
    }

    let kind: Kind
    let lines: [String]

    var text: String {
        lines.joined(separator: "\n")
    }
}

enum AnswerBlocks {
    static func split(_ text: String) -> [AnswerBlock] {
        var blocks: [AnswerBlock] = []
        var prose: [String] = []
        var code: [String] = []
        var fence: String?
        var tag = ""
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let open = fence {
                if trimmed.hasPrefix(open), trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "`~")).isEmpty {
                    blocks.append(AnswerBlock(kind: .code(tag), lines: code))
                    code = []
                    fence = nil
                } else {
                    code.append(line)
                }
            } else if let marker = ["```", "~~~"].first(where: { trimmed.hasPrefix($0) }) {
                if !prose.isEmpty { blocks.append(AnswerBlock(kind: .prose, lines: prose)) }
                prose = []
                fence = marker
                tag = Self.tag(trimmed)
            } else {
                prose.append(line)
            }
        }
        if fence != nil { blocks.append(AnswerBlock(kind: .code(tag), lines: code)) }
        if !prose.isEmpty { blocks.append(AnswerBlock(kind: .prose, lines: prose)) }
        return blocks
    }

    /// The info string's first word, before any space, colon or brace (```` ```toml:pyproject.toml ````).
    static func tag(_ fenceLine: String) -> String {
        let info = fenceLine.drop { "`~".contains($0) }
        return String(info.prefix { !" :{".contains($0) }).lowercased()
    }
}
