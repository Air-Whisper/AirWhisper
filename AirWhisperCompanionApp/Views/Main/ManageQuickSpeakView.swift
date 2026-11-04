import SwiftUI

struct ManageQuickSpeakView: View {
    @EnvironmentObject private var dataManager: DataManager
    @FocusState private var isPhraseFieldFocused: Bool

    @State private var phrases: [QuickPhrase] = []
    @State private var phraseText = ""
    @State private var shakeTrigger = 0
    @State private var isShowingReplacementAlert = false

    private let accentColor = Color(
        red: 0.1137254902,
        green: 0.631372549,
        blue: 0.9490196078,
        opacity: 1
    )

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Add New Phrase")
                .font(.subheadline)
                .padding(.top, 20)
                .padding(.horizontal, 20)

            TextField("Enter phrase", text: $phraseText)
                .font(.system(size: 17))
                .textFieldStyle(.plain)
                .padding(.horizontal, 16)
                .frame(height: 44)
                .background(Design.background)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            isPhraseFieldFocused ? Color(uiColor: .systemBlue) : Color(uiColor: .systemGray4),
                            lineWidth: isPhraseFieldFocused ? 2 : 1
                        )
                }
                .focused($isPhraseFieldFocused)
                .keyframeAnimator(initialValue: CGFloat.zero, trigger: shakeTrigger) { content, offset in
                    content.offset(x: offset)
                } keyframes: { _ in
                    KeyframeTrack {
                        MoveKeyframe(-8)
                        LinearKeyframe(8, duration: 0.4 / 6)
                        LinearKeyframe(-6, duration: 0.4 / 6)
                        LinearKeyframe(6, duration: 0.4 / 6)
                        LinearKeyframe(-4, duration: 0.4 / 6)
                        LinearKeyframe(4, duration: 0.4 / 6)
                        LinearKeyframe(0, duration: 0.4 / 6)
                    }
                }
                .coachMarkTarget("quickspeak-input")
                .padding(.top, 10)
                .padding(.horizontal, 20)

            Button(action: addPhrase) {
                Text("+ Add")
                    .font(.system(size: 17))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .coachMarkTarget("quickspeak-add")
            .padding(.top, 10)
            .padding(.horizontal, 20)

            Text("Current Phrases")
                .font(.subheadline)
                .padding(.top, 20)
                .padding(.bottom, 10)
                .padding(.horizontal, 20)

            List {
                ForEach(phrases) { phrase in
                    Text(phrase.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .moveDisabled(isHelpPhrase(phrase.text))
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            if !isHelpPhrase(phrase.text) {
                                Button("Delete", role: .destructive) {
                                    removePhrase(phrase)
                                }
                            }
                        }
                }
                .onMove(perform: movePhrases)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .coachMarkTarget("quickspeak-list")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Design.background)
        .navigationTitle("Manage Quick Speak")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
        .coachMarkTour(
            screenKey: "quickspeak",
            steps: [
                CoachMarkStep(
                    target: "quickspeak-input",
                    message: "Type a new phrase you want quick access to.",
                    position: .below
                ),
                CoachMarkStep(
                    target: "quickspeak-add",
                    message: "Tap to save the phrase. Duplicates will shake the text field.",
                    position: .below
                ),
                CoachMarkStep(
                    target: "quickspeak-list",
                    message: "Your saved phrases appear here. Swipe left to delete. When full, the least-used phrase is auto-replaced.",
                    position: .above
                )
            ]
        )
        .onAppear(perform: loadPhrases)
        .onReceive(NotificationCenter.default.publisher(for: .dataDidChangeRemotely)) { _ in
            loadPhrases()
        }
        .alert("Phrase Replaced", isPresented: $isShowingReplacementAlert) {
            Button("OK") { }
        } message: {
            Text("Quick Speak is full (max \(DataManager.maxPhrases)). The least-used phrase was replaced.")
        }
    }

    private func loadPhrases() {
        phrases = dataManager.getQuickPhrases()
    }

    private func addPhrase() {
        guard !phraseText.isEmpty else { return }

        let isFull = dataManager.getQuickPhrases().count >= DataManager.maxPhrases
        let added = dataManager.addQuickPhraseIfUnique(text: phraseText)

        if !added {
            shakeTrigger += 1
        } else if isFull {
            isShowingReplacementAlert = true
        }

        loadPhrases()
        phraseText = ""
        isPhraseFieldFocused = false
    }

    private func removePhrase(_ phrase: QuickPhrase) {
        guard let index = phrases.firstIndex(where: { $0.id == phrase.id }) else { return }
        withAnimation {
            dataManager.removeQuickPhrase(at: index)
            phrases.remove(at: index)
        }
    }

    private func movePhrases(from source: IndexSet, to destination: Int) {
        guard !source.contains(where: { isHelpPhrase(phrases[$0].text) }) else { return }

        var reordered = phrases
        reordered.move(fromOffsets: source, toOffset: destination)

        if let helpIndex = reordered.firstIndex(where: { isHelpPhrase($0.text) }) {
            let helpPhrase = reordered.remove(at: helpIndex)
            reordered.insert(helpPhrase, at: 0)
        }

        withAnimation {
            dataManager.reorderQuickPhrases(reordered)
            phrases = dataManager.getQuickPhrases()
        }
    }

    private func isHelpPhrase(_ phrase: String) -> Bool {
        phrase.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "HELP"
    }
}
