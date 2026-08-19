//  LegalDocumentViewController.swift
//  AirWhisperCompanionApp

import UIKit

enum LegalDocumentKind {
    case termsOfService
    case privacyPolicy

    var filename: String {
        switch self {
        case .termsOfService:
            return "TERMS_OF_SERVICE.md"
        case .privacyPolicy:
            return "PRIVACY_POLICY.md"
        }
    }

    var title: String {
        switch self {
        case .termsOfService:
            return "Terms of Service"
        case .privacyPolicy:
            return "Privacy Policy"
        }
    }
}

final class LegalDocumentViewController: UIViewController {

    var documentKind: LegalDocumentKind = .termsOfService

    @IBOutlet weak var textView: UITextView!

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = documentKind.title
        configureView()
        loadDocument()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(contentSizeCategoryDidChange),
            name: UIContentSizeCategory.didChangeNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func enableModalDismissButton() {
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(dismissButtonTapped)
        )
    }

    private func configureView() {
        view.backgroundColor = .systemBackground
        navigationItem.largeTitleDisplayMode = .never

        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = true
        textView.adjustsFontForContentSizeCategory = true
        textView.backgroundColor = .clear
        textView.textColor = .label
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 24, right: 0)
        textView.textContainer.lineFragmentPadding = 0
        textView.linkTextAttributes = [
            .foregroundColor: UIColor.link,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        configureTypography()
    }

    private func configureTypography() {
        textView.font = UIFont.preferredFont(forTextStyle: .body)
    }

    private func loadDocument() {
        do {
            guard let url = bundledURL(for: documentKind.filename) else {
                throw LegalDocumentError.missingResource(documentKind.filename)
            }

            let markdown = try String(contentsOf: url, encoding: .utf8)
            textView.attributedText = try renderMarkdown(markdown, baseURL: url.deletingLastPathComponent())
        } catch {
            textView.attributedText = NSAttributedString(
                string: "Unable to load this document. Please try again later.",
                attributes: [
                    .font: UIFont.preferredFont(forTextStyle: .body),
                    .foregroundColor: UIColor.secondaryLabel
                ]
            )
        }
    }

    private func bundledURL(for filename: String) -> URL? {
        let file = filename as NSString
        let name = file.deletingPathExtension
        let fileExtension = file.pathExtension.isEmpty ? "md" : file.pathExtension
        return Bundle.main.url(forResource: name, withExtension: fileExtension)
    }

    private func renderMarkdown(_ markdown: String, baseURL: URL) throws -> NSAttributedString {
        _ = try NSAttributedString(
            markdown: Data(markdown.utf8),
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .full),
            baseURL: baseURL
        )

        let result = NSMutableAttributedString()
        var pendingBlankLine = false

        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else {
                pendingBlankLine = true
                continue
            }

            if result.length > 0 {
                result.append(NSAttributedString(string: pendingBlankLine ? "\n\n" : "\n"))
            }
            pendingBlankLine = false

            result.append(try renderLine(line, baseURL: baseURL))
        }

        return result
    }

    private func renderLine(_ line: String, baseURL: URL) throws -> NSAttributedString {
        let block = MarkdownBlock(line)
        let renderedText = block.isListItem ? "• \(block.text)" : block.text
        let data = Data(renderedText.utf8)
        let parsed = try NSMutableAttributedString(
            markdown: data,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace),
            baseURL: baseURL
        )

        let fullRange = NSRange(location: 0, length: parsed.length)
        parsed.addAttributes(
            [
                .font: font(for: block.textStyle, weight: block.weight),
                .foregroundColor: UIColor.label,
                .paragraphStyle: paragraphStyle(for: block)
            ],
            range: fullRange
        )

        parsed.enumerateAttribute(.inlinePresentationIntent, in: fullRange) { value, range, _ in
            guard let rawValue = (value as? NSNumber)?.intValue else { return }
            let intent = InlinePresentationIntent(rawValue: UInt(rawValue))
            parsed.addAttribute(.font, value: font(for: block.textStyle, weight: block.weight, inlineIntent: intent), range: range)
        }

        return parsed
    }

    private func paragraphStyle(for block: MarkdownBlock) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 3
        style.paragraphSpacing = block.paragraphSpacing

        if block.isListItem {
            style.firstLineHeadIndent = 0
            style.headIndent = 18
        }

        return style
    }

    private func font(
        for textStyle: UIFont.TextStyle,
        weight: UIFont.Weight,
        inlineIntent: InlinePresentationIntent? = nil
    ) -> UIFont {
        if inlineIntent?.contains(.code) == true {
            let pointSize = UIFont.preferredFont(forTextStyle: textStyle).pointSize
            return UIFont.monospacedSystemFont(ofSize: pointSize, weight: .regular)
        }

        let resolvedWeight = inlineIntent?.contains(.stronglyEmphasized) == true ? UIFont.Weight.semibold : weight
        var font = weightedPreferredFont(for: textStyle, weight: resolvedWeight)

        if inlineIntent?.contains(.emphasized) == true,
           let descriptor = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(.traitItalic)) {
            font = UIFont(descriptor: descriptor, size: font.pointSize)
        }

        return font
    }

    private func weightedPreferredFont(for textStyle: UIFont.TextStyle, weight: UIFont.Weight) -> UIFont {
        let baseFont = UIFont.preferredFont(forTextStyle: textStyle)
        let descriptor = baseFont.fontDescriptor.addingAttributes([
            .traits: [
                UIFontDescriptor.TraitKey.weight: weight
            ]
        ])
        return UIFont(descriptor: descriptor, size: baseFont.pointSize)
    }

    @objc private func dismissButtonTapped() {
        dismiss(animated: true)
    }

    @objc private func contentSizeCategoryDidChange() {
        configureTypography()
        loadDocument()
    }
}

private enum LegalDocumentError: LocalizedError {
    case missingResource(String)

    var errorDescription: String? {
        switch self {
        case .missingResource(let filename):
            return "Missing bundled legal document: \(filename)"
        }
    }
}

private struct MarkdownBlock {
    let text: String
    let textStyle: UIFont.TextStyle
    let weight: UIFont.Weight
    let isListItem: Bool
    let paragraphSpacing: CGFloat

    init(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if trimmed.hasPrefix("### ") {
            text = String(trimmed.dropFirst(4))
            textStyle = .headline
            weight = .semibold
            isListItem = false
            paragraphSpacing = 6
        } else if trimmed.hasPrefix("## ") {
            text = String(trimmed.dropFirst(3))
            textStyle = .title3
            weight = .semibold
            isListItem = false
            paragraphSpacing = 8
        } else if trimmed.hasPrefix("# ") {
            text = String(trimmed.dropFirst(2))
            textStyle = .title2
            weight = .bold
            isListItem = false
            paragraphSpacing = 10
        } else if trimmed.hasPrefix("- ") {
            text = String(trimmed.dropFirst(2))
            textStyle = .body
            weight = .regular
            isListItem = true
            paragraphSpacing = 4
        } else {
            text = line
            textStyle = .body
            weight = .regular
            isListItem = false
            paragraphSpacing = 6
        }
    }
}

final class LegalAgreementLabelController: NSObject {

    private let fullText = "I agree to the Terms of Service and Privacy Policy"
    private let termsText = "Terms of Service"
    private let privacyText = "Privacy Policy"

    private weak var label: UILabel?
    private let selectionHandler: (LegalDocumentKind) -> Void

    init(label: UILabel, selectionHandler: @escaping (LegalDocumentKind) -> Void) {
        self.label = label
        self.selectionHandler = selectionHandler
        super.init()

        configureLabel()
        label.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(labelTapped(_:))))

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(contentSizeCategoryDidChange),
            name: UIContentSizeCategory.didChangeNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func configureLabel() {
        guard let label = label else { return }

        let attributedText = NSMutableAttributedString(
            string: fullText,
            attributes: [
                .font: UIFont.preferredFont(forTextStyle: .footnote),
                .foregroundColor: UIColor.secondaryLabel
            ]
        )

        let fullNSString = fullText as NSString
        [termsText, privacyText].forEach { linkText in
            attributedText.addAttributes(
                [
                    .foregroundColor: UIColor.link,
                    .underlineStyle: NSUnderlineStyle.single.rawValue
                ],
                range: fullNSString.range(of: linkText)
            )
        }

        label.attributedText = attributedText
        label.numberOfLines = 0
        label.isUserInteractionEnabled = true
        label.adjustsFontForContentSizeCategory = true
        label.accessibilityLabel = fullText
        label.accessibilityHint = "Activates the Terms of Service or Privacy Policy."
        label.accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "View Terms of Service", target: self, selector: #selector(viewTermsFromAccessibility)),
            UIAccessibilityCustomAction(name: "View Privacy Policy", target: self, selector: #selector(viewPrivacyFromAccessibility))
        ]

        var traits = label.accessibilityTraits
        traits.insert(.link)
        label.accessibilityTraits = traits
    }

    @objc private func labelTapped(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended,
              let label = label,
              let characterIndex = characterIndex(at: recognizer.location(in: label), in: label),
              let document = document(at: characterIndex) else {
            return
        }

        selectionHandler(document)
    }

    @objc private func contentSizeCategoryDidChange() {
        configureLabel()
    }

    @objc private func viewTermsFromAccessibility() -> Bool {
        selectionHandler(.termsOfService)
        return true
    }

    @objc private func viewPrivacyFromAccessibility() -> Bool {
        selectionHandler(.privacyPolicy)
        return true
    }

    private func document(at characterIndex: Int) -> LegalDocumentKind? {
        let text = fullText as NSString
        let termsRange = text.range(of: termsText)
        let privacyRange = text.range(of: privacyText)

        if NSLocationInRange(characterIndex, termsRange) {
            return .termsOfService
        }

        if NSLocationInRange(characterIndex, privacyRange) {
            return .privacyPolicy
        }

        return nil
    }

    private func characterIndex(at point: CGPoint, in label: UILabel) -> Int? {
        guard let attributedText = label.attributedText, attributedText.length > 0 else {
            return nil
        }

        let textStorage = NSTextStorage(attributedString: attributedText)
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(size: label.bounds.size)
        textContainer.lineFragmentPadding = 0
        textContainer.maximumNumberOfLines = label.numberOfLines
        textContainer.lineBreakMode = label.lineBreakMode

        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)

        let usedRect = layoutManager.usedRect(for: textContainer)
        let textOffset = CGPoint(
            x: horizontalTextOffset(for: label, usedRect: usedRect),
            y: (label.bounds.height - usedRect.height) / 2 - usedRect.minY
        )
        let textContainerPoint = CGPoint(x: point.x - textOffset.x, y: point.y - textOffset.y)

        guard textContainerPoint.x >= usedRect.minX,
              textContainerPoint.y >= usedRect.minY,
              textContainerPoint.x <= usedRect.maxX,
              textContainerPoint.y <= usedRect.maxY else {
            return nil
        }

        let glyphIndex = layoutManager.glyphIndex(for: textContainerPoint, in: textContainer)
        let glyphRange = NSRange(location: glyphIndex, length: 1)
        guard layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer).contains(textContainerPoint) else {
            return nil
        }

        return layoutManager.characterIndexForGlyph(at: glyphIndex)
    }

    private func horizontalTextOffset(for label: UILabel, usedRect: CGRect) -> CGFloat {
        switch label.textAlignment {
        case .center:
            return (label.bounds.width - usedRect.width) / 2 - usedRect.minX
        case .right:
            return label.bounds.width - usedRect.width - usedRect.minX
        default:
            return -usedRect.minX
        }
    }
}

extension UIViewController {
    func presentLegalDocument(_ document: LegalDocumentKind) {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        guard let documentViewController = storyboard.instantiateViewController(
            withIdentifier: "LegalDocumentViewController"
        ) as? LegalDocumentViewController else {
            assertionFailure("LegalDocumentViewController missing storyboard ID")
            return
        }
        documentViewController.documentKind = document

        if let navigationController = navigationController {
            navigationController.pushViewController(documentViewController, animated: true)
            return
        }

        documentViewController.enableModalDismissButton()
        let navigationController = UINavigationController(rootViewController: documentViewController)
        navigationController.modalPresentationStyle = .pageSheet
        present(navigationController, animated: true)
    }
}
