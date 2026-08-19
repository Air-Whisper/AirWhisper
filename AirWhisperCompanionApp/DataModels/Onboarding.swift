//
//  Onboarding.swift
//  AirWhisperCompanionApp
//
//  Created by GEU on 31/03/26.
//

import Foundation
struct OnboardingItem {
    let video: String
    let title: String
    let description: String
    
    static let items: [OnboardingItem] = [
        OnboardingItem(
            video: "HowToUse1Video",
            title: "Air Write",
            description: "Write letters in the air using natural wrist movements."
        ),
        OnboardingItem(
            video: "HowToUse2Video",
            title: "Orient Write",
            description: "Write using simple wrist movements like up, down, left or right."
        ),
        OnboardingItem(
            video: "HowToUse3Video",
            title: "Quick Speak",
            description: "Use predefined phrases for fast communication."
        ),
        OnboardingItem(
            video: "HowToUse4Video",
            title: "Surface Tap",
            description: "Use single or double surface taps on nearby objects to move through phrases."
        )
    ]
}
