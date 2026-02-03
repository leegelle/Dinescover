//
//  MainView.swift
//  RestrauntPicker
//
//  Created by Liiban on 12/5/25.
//

import SwiftUI

struct MainView: View {
    @StateObject private var historyManager = HistoryManager()
    @StateObject private var favoritesManager = FavoritesManager()
    
    var body: some View {
        TabView {
            // SPIN TAB
            SpinView()
                .environmentObject(historyManager)
                .environmentObject(favoritesManager)
                .tabItem {
                    Label("Spin", systemImage: "fork.knife.circle")
                }
            
            // HISTORY TAB
            HistoryScreen()
                .environmentObject(historyManager)
                .tabItem {
                    Label("History", systemImage: "clock")
                }
            
            // FAVORITES TAB
            FavoritesScreen()
                .environmentObject(favoritesManager)
                .tabItem {
                    Label("Favorites", systemImage: "heart")
                }
        }
    }
}
