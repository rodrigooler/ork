import SwiftUI

/// Rolling feed of deck activity: spawns, exits, freezes, team traffic.
/// The notch shows it live, collapsed and expanded. Local only, capped.
final class EventFeed: ObservableObject {
    static let shared = EventFeed()

    struct Event: Identifiable {
        let id = UUID()
        let date = Date()
        let symbol: String
        let tintHex: UInt32
        let text: String
    }

    @Published private(set) var events: [Event] = []

    var latest: Event? { events.last }

    func post(symbol: String, tintHex: UInt32 = 0xF96B2F, text: String) {
        let event = Event(symbol: symbol, tintHex: tintHex, text: text)
        DispatchQueue.main.async {
            self.events.append(event)
            if self.events.count > 60 {
                self.events.removeFirst(self.events.count - 60)
            }
        }
    }
}
