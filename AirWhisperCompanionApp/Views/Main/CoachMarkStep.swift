import Foundation

struct CoachMarkStep: Identifiable, Equatable {
    enum Position: Equatable {
        case above
        case below
    }

    let target: String
    let message: String
    let position: Position

    var id: String { target }
}
