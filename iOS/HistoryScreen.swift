import SwiftUI
import MapKit

struct HistoryScreen: View {
    @EnvironmentObject var historyManager: HistoryManager
    
    var body: some View {
        ZStack {
            // Match SpinView gradient
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
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.title2)
                                .foregroundStyle(.orange)
                            
                            Text("Spin History")
                                .font(.system(size: 30, weight: .heavy, design: .rounded))
                        }
                        
                        Text("See where fate has sent you lately.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 24)
                    
                    // CONTENT
                    if historyManager.entries.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "fork.knife")
                                .font(.largeTitle)
                                .foregroundColor(.secondary)
                            Text("No spins yet")
                                .font(.headline)
                            Text("Spin for a restaurant and your picks will appear here.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else {
                        VStack(spacing: 12) {
                            ForEach(historyManager.entries) { entry in
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    openInMaps(entry.restaurant)
                                } label: {
                                    HistoryRow(entry: entry)
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

struct HistoryRow: View {
    let entry: HistoryEntry
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Icon bubble
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.2))
                    .frame(width: 40, height: 40)
                Image(systemName: "clock")
                    .foregroundColor(.orange)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.restaurant.name)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                
                if let distance = entry.restaurant.distanceText {
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
                
                Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundColor(.secondary)
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
