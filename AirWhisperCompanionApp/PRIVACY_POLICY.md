
**Last Updated:** June 1, 2026

This Privacy Policy explains how AirWhisper ("we", "us", or "our") collects, uses, and shares your information when you use the AirWhisper iOS Companion App and the WAAirWhisper Watch App (collectively, the "App").

## 1. Information We Collect

### A. Personal and Account Information
When you create an account, we may collect your name, email address, phone number, and authentication credentials. If you choose to use **Sign In with Apple**, we receive an Apple-provided user identifier and the information you choose to share during that process.

### B. Device Motion and Sensor Data
To provide our core "AirWrite" and "OrientWrite" features, the App relies on Apple Watch sensors (CoreMotion) to capture device motion and orientation samples. This data is converted into preprocessed tensors to predict the letters you are writing in the air or via wrist orientation.

### C. Contacts and Communications
If you grant permission, the App accesses your device's Contacts (`ContactsUI`) so you can select recipients for messages. We also store your custom "QuickSpeak" phrases and the history of messages you have composed.

### D. Settings and Usage Data
We collect your preferences, including watch sensitivity settings and accessibility toggles, to customize your experience.

## 2. How We Process and Use Your Information

- **Local Machine Learning:** In "AirWrite" mode, motion data is primarily processed on-device using Apple's CoreML to predict letters without sending raw sensor data to external servers.
- **Cloud Sync:** Your user profile, selected contacts, custom phrases, message history, and settings are synchronized across your devices using Apple's iCloud Key-Value Store (`NSUbiquitousKeyValueStore`).
- **Communication Features:** We use your collected data to initiate Voice Guidance (text-to-speech) and to transmit text messages on your behalf.
- **Authentication:** We use your data to manage active sessions and refresh access tokens securely.

## 3. Third-Party Services and Data Sharing

We do not sell your personal information. We may share specific data with third-party service providers solely to facilitate App functionality:

- **Google Handwriting API:** In certain writing modes, your recognized handwriting curves/inputs may be securely transmitted to the Google Handwriting Service to improve character recognition.
- **SMS Infrastructure:** When you choose to send an SMS, the composed text and the recipient's contact information are routed through our backend (`RenderSMSSender`) which interfaces with third-party messaging APIs (such as Twilio).
- **Apple Services:** iCloud is used for data synchronization, and Sign In with Apple is used for authentication. Data sharing with Apple is subject to Apple's own Privacy Policy.

## 4. Data Security

We implement standard security measures, including SSL/TLS encryption for network requests (e.g., authentication, SMS sending, and API calls), to protect your information. 

## 5. Contact Us

If you have any questions or concerns about this Privacy Policy, please contact the AirWhisper support team.
