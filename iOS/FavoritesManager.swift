//
//  FavoritesManager.swift
//  RestrauntPicker
//
//  Created by Liiban on 12/5/25.
//

import Foundation

class FavoritesManager: ObservableObject {
    @Published private(set) var favorites: [Restaurant] = []
    
    func isFavorite(_ restaurant: Restaurant) -> Bool {
        favorites.contains(where: { $0.id == restaurant.id })
    }
    
    func toggleFavorite(_ restaurant: Restaurant) {
        if let index = favorites.firstIndex(where: { $0.id == restaurant.id }) {
            favorites.remove(at: index)
        } else {
            favorites.append(restaurant)
        }
    }
}
