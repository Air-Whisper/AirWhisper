import SwiftUI

/// Scrollable, inline-markdown presentation of a Terms or Privacy document.
struct LegalDocumentView: View {

    @Environment(\.dismiss) private var dismiss

    let document: LegalDocument
    private let onDone: (() -> Void)?

    init(document: LegalDocument, onDone: (() -> Void)? = nil) {
        self.document = document
        self.onDone = onDone
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(document.blocks) { block in
                        if block.isListItem {
                            HStack(alignment: .top, spacing: 0) {
                                Text("•")
                                    .font(font(for: block.style))
                                    .frame(width: 18, alignment: .leading)

                                Text(block.inlineText)
                                    .font(font(for: block.style))
                                    .lineSpacing(3)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.bottom, blockSpacing(for: block))
                        } else {
                            Text(block.inlineText)
                                .font(font(for: block.style))
                                .lineSpacing(3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.bottom, blockSpacing(for: block))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Design.background)
            .tint(Design.link)
            .navigationTitle(document.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: doneTapped)
                }
            }
        }
    }

    private func font(for style: LegalDocument.Block.Style) -> Font {
        switch style {
        case .title2: .title2.weight(.bold)
        case .title3: .title3.weight(.semibold)
        case .headline: .headline.weight(.semibold)
        case .body: .body
        }
    }

    private func blockSpacing(for block: LegalDocument.Block) -> CGFloat {
        CGFloat(block.paragraphSpacing + block.blankLineSpacing)
    }

    private func doneTapped() {
        if let onDone {
            onDone()
        } else {
            dismiss()
        }
    }
}
