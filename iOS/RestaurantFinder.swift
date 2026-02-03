//
//  RestaurantFinder.swift
//  RestrauntPicker
//
//  Created by Liiban on 12/2/25.
//

import Foundation
import MapKit
import CoreLocation

final class RestaurantFinder: ObservableObject {

    enum FinderError: Error {
        case noResults
    }

    /// Find restaurants near a coordinate using Apple Maps (MapKit).
    /// - Parameters:
    ///   - query: "restaurants" or "halal restaurant"
    ///   - preferredMinDistanceMiles: optional lower bound (can be nil)
    ///   - maxDistanceMiles: upper bound (e.g. 10)
    func findRestaurants(
        near coordinate: CLLocationCoordinate2D,
        query: String = "restaurants",
        preferredMinDistanceMiles: Double?,
        maxDistanceMiles: Double,
        completion: @escaping (Result<[Restaurant], Error>) -> Void
    ) {
        // Expand radius intelligently (only up to maxDistanceMiles)
        let candidateSteps: [Double] = [1, 2, 3, 5, 7, 10]
        let steps = candidateSteps.filter { $0 <= maxDistanceMiles }

        let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

        var collected: [Restaurant] = []
        var collectedDistanceByKey: [String: Double] = [:] // used for sorting + filtering

        func searchStep(at index: Int) {
            if index >= steps.count {
                // Final filter/sort/dedupe
                var results = collected

                // Optional min distance filter
                if let minMiles = preferredMinDistanceMiles {
                    results = results.filter { r in
                        let key = uniqueKey(for: r)
                        let miles = collectedDistanceByKey[key] ?? 9999
                        return miles >= minMiles
                    }
                }

                // Hard max distance filter (safe)
                results = results.filter { r in
                    let key = uniqueKey(for: r)
                    let miles = collectedDistanceByKey[key] ?? 9999
                    return miles <= maxDistanceMiles
                }

                // Dedupe by key
                var seen = Set<String>()
                results = results.filter { r in
                    let key = uniqueKey(for: r)
                    if seen.contains(key) { return false }
                    seen.insert(key)
                    return true
                }

                // Sort closer first (classic closure sort; no SortComparator)
                results.sort { a, b in
                    let aMiles = collectedDistanceByKey[uniqueKey(for: a)] ?? 9999
                    let bMiles = collectedDistanceByKey[uniqueKey(for: b)] ?? 9999
                    return aMiles < bMiles
                }

                if results.isEmpty {
                    completion(.failure(FinderError.noResults))
                } else {
                    completion(.success(results))
                }
                return
            }

            let miles = steps[index]
            let meters = miles * 1609.34

            let region = MKCoordinateRegion(
                center: coordinate,
                latitudinalMeters: meters * 2.0,
                longitudinalMeters: meters * 2.0
            )

            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.resultTypes = .pointOfInterest
            request.region = region

            MKLocalSearch(request: request).start { response, error in
                if let error = error {
                    print("MKLocalSearch error: \(error.localizedDescription)")
                    // Try next radius anyway
                    searchStep(at: index + 1)
                    return
                }

                guard let items = response?.mapItems, !items.isEmpty else {
                    // No results at this radius; expand
                    searchStep(at: index + 1)
                    return
                }

                // Build Restaurant objects
                let newRestaurants: [Restaurant] = items.compactMap { (item: MKMapItem) -> Restaurant? in
                    guard let name = item.name,
                          !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        return nil
                    }
                    guard let loc = item.placemark.location else {
                        return nil
                    }

                    let distMeters = origin.distance(from: loc)
                    let distMiles = distMeters / 1609.34

                    // Respect max distance (hard cutoff)
                    if distMiles > maxDistanceMiles { return nil }

                    let distanceText = Self.formatDistance(miles: distMiles)

                    // ✅ FIX: Remove `id:` because your Restaurant model likely generates it internally
                    let restaurant = Restaurant(
                        name: name,
                        mapItem: item,
                        distanceText: distanceText
                    )


                    return restaurant
                }

                // Collect + store distances for sorting/filtering
                for r in newRestaurants {
                    let key = self.uniqueKey(for: r)
                    if collectedDistanceByKey[key] == nil {
                        collectedDistanceByKey[key] = Self.extractMiles(from: r.distanceText) ?? 9999
                        collected.append(r)
                    } else {
                        // Keep the smaller distance if we encounter same place again
                        let current = collectedDistanceByKey[key] ?? 9999
                        let candidate = Self.extractMiles(from: r.distanceText) ?? 9999
                        if candidate < current {
                            collectedDistanceByKey[key] = candidate
                        }
                    }
                }

                // If we already have a decent list, stop expanding to keep it snappy
                if collected.count >= 25 {
                    searchStep(at: steps.count) // jump to finalize
                } else {
                    searchStep(at: index + 1)
                }
            }
        }

        searchStep(at: 0)
    }

    // MARK: - Helpers

    private func uniqueKey(for r: Restaurant) -> String {
        if let coord = r.mapItem.placemark.location?.coordinate {
            return "\(r.name.lowercased())|\(coord.latitude),\(coord.longitude)"
        }
        return r.name.lowercased()
    }

    private static func formatDistance(miles: Double) -> String {
        if miles < 0.1 { return "Less than 0.1 miles away" }
        return String(format: "%.1f miles away", miles)
    }

    /// Pulls miles back out of the distanceText we set (so we can sort/filter without distanceMiles on the model)
    private static func extractMiles(from distanceText: String?) -> Double? {
        guard let s = distanceText?.lowercased() else { return nil }
        // "0.4 miles away" -> 0.4
        let parts = s.components(separatedBy: " ")
        if let first = parts.first, let val = Double(first) { return val }
        // "less than 0.1 miles away" -> 0.1
        if s.contains("less than"), s.contains("0.1") { return 0.1 }
        return nil
    }
}
