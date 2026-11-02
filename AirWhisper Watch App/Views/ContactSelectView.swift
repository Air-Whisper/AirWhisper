import SwiftUI
struct ContactSelectView: View
{
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var connectivity: WatchConnectivityClient

    let messageText: String
    var isFromQuickPhrase: Bool = false
    
    @State private var showSuccessAlert = false
    @State private var showErrorAlert = false
    @State private var errorMessage: String = ""
    @State private var isSending = false
    @State private var focusedIndex: Int = 0
    
    @AccessibilityFocusState private var focusedContactId: UUID?

    var body: some View 
    {
        ScrollView 
        {
            VStack(spacing: 10) 
            {
                let contacts = connectivity.receivedContacts

                if contacts.isEmpty
                {
                    Text("No synced contacts yet")
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } 
                else 
                {
                    ForEach(contacts) { contact in
                        Button {
                            sendMessage(to: contact)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(contact.name)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                if let phoneNumber = contact.phoneNumber, !phoneNumber.isEmpty {
                                    Text(phoneNumber)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 12)
                            .background(Color.gray.opacity(0.2))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .glassEffect(in: .rect(cornerRadius: 10))
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(connectivity.receivedTapDetectorEnabled && isFocused(contact, in: contacts) ? Color.green : Color.clear, lineWidth: 4)
                        )
                        .buttonStyle(.plain)
                        .disabled(isSending)
                        .accessibilityLabel(contact.name)
                        .accessibilityFocused($focusedContactId, equals: contact.id)
                    }
                }
                
                if isSending {
                    ProgressView("Sending…")
                        .padding(.top, 8)
                }
            }
            .padding(.vertical, 8)
        }
        .navigationTitle("Contacts")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: focusedContactId) { _, newValue in
            if let id = newValue, let contact = connectivity.receivedContacts.first(where: { $0.id == id }) {
                VoiceGuidanceManager.shared.speak(contact.name)
            }
        }
        .alert("Message Sent", isPresented: $showSuccessAlert) {
            Button("OK") { dismiss() }
        } message: {
            Text("Your message was sent successfully via SMS.")
        }
        .alert("Send Failed", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            setupTapDetector()
        }
        .onDisappear {
            SurfaceTapDetector.shared.stop(for: "ContactSelectView")
        }
        .onChange(of: connectivity.receivedTapDetectorEnabled) { _, _ in
            setupTapDetector()
        }
        .onChange(of: connectivity.receivedContacts.map { $0.id }) { _, _ in
            resetFocusedContact(using: connectivity.receivedContacts, speakCurrent: connectivity.receivedTapDetectorEnabled && !isSending)
        }
    }
    
    private func sendMessage(to contact: AWContact) 
    {
        guard !isSending else { return }

        guard let phoneNumber = contact.phoneNumber, !phoneNumber.isEmpty else {
            errorMessage = "No phone number for this contact"
            showErrorAlert = true
            return
        }

        let cleanNumber = phoneNumber.filter { "+0123456789".contains($0) }
        
        isSending = true
        
        Task {
            do {
                let _ = try await RenderSMSSender.shared.sendSMS(to: cleanNumber, body: messageText)
                
                await MainActor.run {
                    isSending = false
                    
                    connectivity.sendMessageToHistory(
                        message: messageText,
                        contactId: contact.id,
                        contactName: contact.name
                    )
                    
                    if isFromQuickPhrase {
                        PhraseManager.shared.markPhraseUsed(messageText)
                    }
                    
                    showSuccessAlert = true
                }
            } catch {
                await MainActor.run {
                    isSending = false
                    errorMessage = error.localizedDescription
                    showErrorAlert = true
                }
            }
        }
    }
    
    private func setupTapDetector() {
        if connectivity.receivedTapDetectorEnabled {
            resetFocusedContact(using: connectivity.receivedContacts, speakCurrent: true)
            
            SurfaceTapDetector.shared.onSingleTap = {
                guard !isSending else { return }

                let contacts = connectivity.receivedContacts
                if let contact = advanceFocusedContact(using: contacts) {
                    VoiceGuidanceManager.shared.speak(contact.name)
                }
            }
            
            SurfaceTapDetector.shared.onDoubleTap = {
                guard !isSending else { return }

                let contacts = connectivity.receivedContacts
                if let contact = focusedContact(using: contacts) {
                    sendMessage(to: contact)
                }
            }
            
            SurfaceTapDetector.shared.start(for: "ContactSelectView")
        } else {
            SurfaceTapDetector.shared.stop(for: "ContactSelectView")
        }
    }

    private func isFocused(_ contact: AWContact, in contacts: [AWContact]) -> Bool {
        guard contacts.indices.contains(focusedIndex) else { return false }
        return contacts[focusedIndex].id == contact.id
    }

    private func resetFocusedContact(using contacts: [AWContact], speakCurrent: Bool = false) {
        focusedIndex = 0

        guard let first = contacts.first else {
            focusedContactId = nil
            return
        }

        focusedContactId = first.id

        if speakCurrent {
            VoiceGuidanceManager.shared.speak(first.name)
        }
    }

    private func advanceFocusedContact(using contacts: [AWContact]) -> AWContact? {
        guard !contacts.isEmpty else {
            focusedIndex = 0
            focusedContactId = nil
            return nil
        }

        if contacts.indices.contains(focusedIndex) {
            focusedIndex = (focusedIndex + 1) % contacts.count
        } else {
            focusedIndex = 0
        }

        let contact = contacts[focusedIndex]
        focusedContactId = contact.id
        return contact
    }

    private func focusedContact(using contacts: [AWContact]) -> AWContact? {
        guard !contacts.isEmpty else {
            focusedIndex = 0
            focusedContactId = nil
            return nil
        }

        if !contacts.indices.contains(focusedIndex) {
            focusedIndex = 0
        }

        let contact = contacts[focusedIndex]
        focusedContactId = contact.id
        return contact
    }
}
