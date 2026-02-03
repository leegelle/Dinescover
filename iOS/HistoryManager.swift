import Foundation
import Combine

/// One item in the history list: which restaurant, and when it was chosen.
struct HistoryEntry: Identifiable {
    let id = UUID()
    let restaurant: Restaurant
    let date: Date
}

final class HistoryManager: ObservableObject {
    @Published var entries: [HistoryEntry] = []
    
    /// Add a restaurant to history (called from SpinView when a spin succeeds)
    func add(_ restaurant: Restaurant) {
        let entry = HistoryEntry(restaurant: restaurant, date: Date())
        // Insert at the top so newest is first
        entries.insert(entry, at: 0)
    }
    
    /// Clear all history (if you ever want a button for this later)
    func clear() {
        entries.removeAll()
    }
}
