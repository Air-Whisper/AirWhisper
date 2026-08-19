//Edited by   .
// defines the phrase button for quickSpeak view, navigates to actionrequiredView when tapped.


import SwiftUI
struct PhraseButton: View {
    let title: String // contains text of the phrase.

    var body: some View {
        NavigationLink {
            ActionRequiredView(text: title, isFromQuickPhrase: true) // navigates to ActionRequiredView when tapped, passing the phrase text and a flag indicating it's from quick phrases.
        } label: {
            LargeActionButton(title: title)
        }
        .buttonStyle(.plain)
    }
}
