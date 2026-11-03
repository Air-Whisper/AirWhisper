import SwiftUI
import UIKit

struct HistoryView: View {
    @EnvironmentObject private var dataManager: DataManager
    @State private var sections: [HistorySection] = []

    private var coachSteps: [CoachMarkStep] {
        if sections.isEmpty {
            return [
                CoachMarkStep(
                    target: "emptyState",
                    message: "No messages sent yet  - they'll appear here after you send one from the Watch.",
                    position: .above
                )
            ]
        }

        return [
            CoachMarkStep(
                target: "historyTable",
                message: "Messages you've sent are grouped by date. Each row shows the contact, message, and time.",
                position: .above
            )
        ]
    }

    var body: some View {
        ZStack {
            Design.background

            if sections.isEmpty {
                VStack(spacing: 0) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 60, height: 60)
                        .foregroundStyle(Color(uiColor: .secondaryLabel))

                    Text("No chat history yet")
                        .font(.callout)
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                        .multilineTextAlignment(.center)
                        .padding(.top, 16)

                    Text("Messages you send will appear here")
                        .font(.subheadline)
                        .foregroundStyle(Color(uiColor: .tertiaryLabel))
                        .multilineTextAlignment(.center)
                        .padding(.top, 6)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .coachMarkTarget("emptyState")
            } else {
                List {
                    ForEach(sections, id: \.title) { section in
                        Section {
                            ForEach(section.items, id: \.messageHistory.id) { item in
                                HStack(spacing: 12) {
                                    Text(item.avatarLetter)
                                        .font(.system(size: 16, weight: .medium))
                                        .frame(width: 40, height: 40)
                                        .background(Color(uiColor: item.avatarColor))
                                        .clipShape(Circle())

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.name)
                                            .font(.body)
                                            .lineLimit(1)

                                        Text(item.message)
                                            .font(.caption)
                                            .foregroundStyle(Color(uiColor: .systemGray))
                                            .lineLimit(1)
                                    }

                                    Spacer(minLength: 8)

                                    Text(item.time)
                                        .font(.caption2)
                                        .foregroundStyle(Color(uiColor: .systemGray))
                                        .frame(maxHeight: .infinity, alignment: .top)
                                        .padding(.top, 12)
                                }
                                .frame(height: 60)
                                .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Design.background)
                            }
                        } header: {
                            Text(section.title)
                                .textCase(nil)
                        }
                    }
                }
                .listStyle(.plain)
                .coachMarkTarget("historyTable")
            }
        }
        .background(Design.background)
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .coachMarkTour(screenKey: "history", steps: coachSteps)
        .onAppear(perform: loadHistoryData)
    }

    private func loadHistoryData() {
        sections = dataManager.getGroupedHistory()
    }
}
