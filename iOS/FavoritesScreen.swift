import SwiftUI
import MapKit

struct FavoritesScreen: View {
    @EnvironmentObject var favoritesManager: FavoritesManager
    
    var body: some View {
        ZStack {
            // Same gradient as Spin / History
            LinearGradient(
                colors: [Color.orange.opacity(0.2),
                         Color.pink.opacity(0.25)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    
                    // HEADER
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Image(systemName: "heart.fill")
                                .font(.title2)
                                .foregroundStyle(.pink)
                            
                            Text("Favorites")
                                .font(.system(size: 30, weight: .heavy, design: .rounded))
                        }
                        
                        Text("Save spots you love and jump back to them anytime.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 24)
                    
                    // CONTENT
                    if favoritesManager.favorites.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "heart")
                                .font(.largeTitle)
                                .foregroundColor(.secondary)
                            Text("No favorites yet")
                                .font(.headline)
                            Text("Tap the heart on a restaurant card to save it here.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else {
                        VStack(spacing: 12) {
                            ForEach(favoritesManager.favorites) { restaurant in
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    openInMaps(restaurant)
                                } label: {
                                    FavoriteRow(restaurant: restaurant)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    
                    Spacer(minLength: 16)
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: 600, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }
    
    private func openInMaps(_ restaurant: Restaurant) {
        restaurant.mapItem.openInMaps(
            launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving]
        )
    }
}

struct FavoriteRow: View {
    let restaurant: Restaurant
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Icon bubble
            ZStack {
                Circle()
                    .fill(Color.pink.opacity(0.18))
                    .frame(width: 40, height: 40)
                Image(systemName: "fork.knife")
                    .foregroundColor(.pink)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text(restaurant.name)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                
                if let distance = restaurant.distanceText {
                    HStack(spacing: 6) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.caption)
                        Text(distance)
                            .font(.caption)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.08))
                    .foregroundColor(.blue)
                    .cornerRadius(10)
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)
        )
    }
}
