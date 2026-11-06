import SwiftUI
import UIKit

struct ContactsView: View {
    @EnvironmentObject private var dataManager: DataManager

    @State private var searchText = ""
    @State private var allContacts: [MyPeople] = []
    @State private var searchResults: [MyPeople] = []
    @State private var isSearching = false
    @State private var isBetaAlertPresented = false
    @State private var hasSetupVerifiedContacts = false
    @FocusState private var isSearchFocused: Bool

    private let verifiedContacts = [
        MyPeople(name: "Person 1", phoneNumber: "+918218517195"),
        MyPeople(name: "Person 2", phoneNumber: "+919149062964"),
        MyPeople(name: "Person 3", phoneNumber: "+918439007296"),
        MyPeople(name: "Person 4", phoneNumber: "+918941040875")
    ]

    private var contacts: [MyPeople] {
        allContacts
    }

    private var displayedContacts: [MyPeople] {
        isSearching ? searchResults : contacts
    }

    private var coachSteps: [CoachMarkStep] {
        if contacts.isEmpty {
            return [
                CoachMarkStep(
                    target: "contacts-empty-state",
                    message: "No contacts yet  - tap 'Import from Device' to get started.",
                    position: .above
                )
            ]
        }

        return [
            CoachMarkStep(
                target: "searchBar",
                message: "Type a name to quickly find a contact.",
                position: .below
            ),
            CoachMarkStep(
                target: "contactsTable",
                message: "Your contacts appear here. Swipe left on any contact to delete it.",
                position: .above
            )
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ZStack {
                Design.background

                if contacts.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "person.badge.plus")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 60, height: 60)
                            .foregroundStyle(Color(uiColor: .secondaryLabel))

                        Text("Add your immediate contacts\nto My People\n(at max 5)")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color(uiColor: .secondaryLabel))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .coachMarkTarget("contacts-empty-state")
                } else {
                    VStack(spacing: 0) {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.secondary)

                            TextField("Search", text: $searchText)
                                .focused($isSearchFocused)
                                .submitLabel(.search)
                                .onSubmit { isSearchFocused = false }
                                .onChange(of: searchText) { _, query in
                                    updateSearchResults(query: query)
                                }

                            if !searchText.isEmpty {
                                Button {
                                    searchText = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 36)
                        .background(Color(uiColor: .tertiarySystemFill))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 14)
                        .coachMarkTarget("searchBar")

                        List {
                            ForEach(displayedContacts) { person in
                                HStack(spacing: 12) {
                                    Text(person.avatarLetter)
                                        .font(.system(size: 14, weight: .medium))
                                        .frame(width: 34, height: 34)
                                        .background(Color(uiColor: person.avatarColor))
                                        .clipShape(Circle())

                                    Text(person.name)
                                        .font(.system(size: 16))

                                    Spacer(minLength: 0)
                                }
                                .frame(height: 50)
                                .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                                .listRowSeparator(.visible)
                                .listRowBackground(Design.background)
                            }
                        }
                        .listStyle(.plain)
                        .coachMarkTarget("contactsTable")
                    }
                }
            }
        }
        .background(Design.background)
        .toolbar(.hidden, for: .navigationBar)
        .alert(
            "Beta Testing Mode",
            isPresented: $isBetaAlertPresented,
            actions: {
                Button("OK", role: .cancel) { }
            },
            message: {
                Text("SMS sending is temporarily limited to the 4 verified contacts of the Team Members. Full contact support will be added in a future update.")
                    .font(.system(size: 13))
                    .multilineTextAlignment(.center)
            }
        )
        .onAppear(perform: viewWillAppear)
        .coachMarkTour(screenKey: "contacts", steps: coachSteps)
    }

    private var header: some View {
        HStack {
            Spacer(minLength: 44)

            Button {
                isBetaAlertPresented = true
            } label: {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 20, weight: .regular))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .tint(Color(red: 0.1137254902, green: 0.6313725490, blue: 0.9490196078, opacity: 1))
        }
        .overlay {
            Text("My People")
                .font(.system(size: 20, weight: .bold))
                .lineLimit(1)
                .allowsHitTesting(false)
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
        .background(Design.background)
    }

    private func setupVerifiedContacts() {
        let currentContacts = dataManager.getPeople()
        let verifiedNames = ["Person 1", "Person 2", "Person 3", "Person 4"]
        let hasAllVerified = verifiedNames.allSatisfy { name in
            currentContacts.contains { $0.name == name }
        }

        guard !hasAllVerified || currentContacts.count != 4 else { return }

        for contact in currentContacts {
            dataManager.remove(withId: contact.id)
        }
        for person in verifiedContacts {
            dataManager.add(person)
        }
    }

    private func viewWillAppear() {
        if !hasSetupVerifiedContacts {
            setupVerifiedContacts()
            hasSetupVerifiedContacts = true
        }
        allContacts = dataManager.getPeople()
        searchResults = allContacts
    }

    private func updateSearchResults(query: String) {
        if query.isEmpty {
            isSearching = false
            searchResults = allContacts
        } else {
            isSearching = true
            searchResults = dataManager.search(query: query)
        }
    }
}
