import Foundation

/// A bundled legal document and the rendered paragraphs used by its view.
struct LegalDocument: Identifiable {

    enum Kind: String, Identifiable {
        case termsOfService
        case privacyPolicy

        var id: String { rawValue }

        var resourceName: String {
            switch self {
            case .termsOfService: "TERMS_OF_SERVICE"
            case .privacyPolicy: "PRIVACY_POLICY"
            }
        }

        var title: String {
            switch self {
            case .termsOfService: "Terms of Service"
            case .privacyPolicy: "Privacy Policy"
            }
        }
    }

    struct Block: Identifiable {
        enum Style {
            case title2
            case title3
            case headline
            case body
        }

        let id: Int
        let inlineText: AttributedString
        let style: Style
        let isListItem: Bool
        let paragraphSpacing: Double
        let blankLineSpacing: Double
    }

    let kind: Kind
    let blocks: [Block]

    var id: String { kind.id }
    var title: String { kind.title }

    static func load(_ kind: Kind) -> LegalDocument {
        do {
            guard let url = Bundle.main.url(forResource: kind.resourceName, withExtension: "md") else {
                throw DocumentLoadError.missingResource
            }
            let markdown = try String(contentsOf: url, encoding: .utf8)
            let baseURL = url.deletingLastPathComponent()

            _ = try AttributedString(
                markdown: Data(markdown.utf8),
                options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .full),
                baseURL: baseURL
            )

            return LegalDocument(kind: kind, blocks: try makeBlocks(markdown, baseURL: baseURL))
        } catch {
            return LegalDocument(
                kind: kind,
                blocks: [
                    Block(
                        id: 0,
                        inlineText: AttributedString("Unable to load this document. Please try again later."),
                        style: .body,
                        isListItem: false,
                        paragraphSpacing: 6,
                        blankLineSpacing: 0
                    )
                ]
            )
        }
    }

    private static func makeBlocks(_ markdown: String, baseURL: URL) throws -> [Block] {
        var blocks: [Block] = []
        var pendingBlankLine = false

        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else {
                pendingBlankLine = true
                continue
            }

            let parsedLine = MarkdownLine(line)
            let inlineText = try AttributedString(
                markdown: Data(parsedLine.text.utf8),
                options: AttributedString.MarkdownParsingOptions(
                    interpretedSyntax: .inlineOnlyPreservingWhitespace
                ),
                baseURL: baseURL
            )

            blocks.append(
                Block(
                    id: blocks.count,
                    inlineText: inlineText,
                    style: parsedLine.style,
                    isListItem: parsedLine.isListItem,
                    paragraphSpacing: parsedLine.paragraphSpacing,
                    blankLineSpacing: pendingBlankLine && !blocks.isEmpty ? 12 : 0
                )
            )
            pendingBlankLine = false
        }

        return blocks
    }

    private enum DocumentLoadError: Error {
        case missingResource
    }

    private struct MarkdownLine {
        let text: String
        let style: Block.Style
        let isListItem: Bool
        let paragraphSpacing: Double

        init(_ line: String) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("### ") {
                text = String(trimmed.dropFirst(4))
                style = .headline
                isListItem = false
                paragraphSpacing = 6
            } else if trimmed.hasPrefix("## ") {
                text = String(trimmed.dropFirst(3))
                style = .title3
                isListItem = false
                paragraphSpacing = 8
            } else if trimmed.hasPrefix("# ") {
                text = String(trimmed.dropFirst(2))
                style = .title2
                isListItem = false
                paragraphSpacing = 10
            } else if trimmed.hasPrefix("- ") {
                text = String(trimmed.dropFirst(2))
                style = .body
                isListItem = true
                paragraphSpacing = 4
            } else {
                text = line
                style = .body
                isListItem = false
                paragraphSpacing = 6
            }
        }
    }
}
