//
//  SpinView.swift
//  RestrauntPicker
//
//  Dinescover - SpinView
//
//  ✅ Food filters: All / Strict Halal / Vegetarian / Kosher
//  ✅ Plan-ahead: Change City (autocomplete + clear X)
//  ✅ Vibe line: ETA • distance • clickable phone • why this pick
//  ✅ Avoid re-spinning + Not Interested + Reset Spins
//  ✅ Safe map region (prevents invalid huge spans; far city > 500 mi focuses on restaurant)
//  ✅ iPad-friendly (no NavigationView split behavior)
//

import SwiftUI
import MapKit
import CoreLocation
import UIKit

struct SpinView: View {

    // MARK: - Dependencies
    @StateObject private var locationManager = LocationManager()
    @StateObject private var restaurantFinder = RestaurantFinder()

    @EnvironmentObject var historyManager: HistoryManager
    @EnvironmentObject var favoritesManager: FavoritesManager

    // MARK: - UI State
    @State private var isSearching = false
    @State private var currentRestaurant: Restaurant?
    @State private var errorMessage: String?

    // Avoid repeats + “not interested”
    @State private var shownKeys: Set<String> = SpinStore.loadShown()
    @State private var dislikedKeys: Set<String> = SpinStore.loadDisliked()

    // Notes
    @State private var notesByKey: [String: String] = NotesStore.load()
    @State private var isNotesSheetPresented = false
    @State private var notesDraft = ""

    // ETA + “why this pick?”
    @State private var etaTextByKey: [String: String] = [:]
    @State private var whyTextByKey: [String: String] = [:]

    // MARK: - Filters
    enum FoodFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case strictHalal = "Halal"
        case vegetarian = "Vegetarian"
        case kosher = "Kosher"

        var id: String { rawValue }

        var query: String {
            switch self {
            case .all: return "restaurants"
            case .strictHalal: return "halal restaurant"
            case .vegetarian: return "vegetarian restaurant"
            case .kosher: return "kosher restaurant"
            }
        }

        var icon: String {
            switch self {
            case .all: return "fork.knife"
            case .strictHalal: return "checkmark.seal.fill"
            case .vegetarian: return "leaf.fill"
            case .kosher: return "star.circle.fill"
            }
        }
    }

    @State private var selectedFilter: FoodFilter = .all

    // MARK: - Plan-ahead City
    struct CitySelection: Equatable {
        var title: String
        var subtitle: String
        var coordinate: CLLocationCoordinate2D

        static func == (lhs: CitySelection, rhs: CitySelection) -> Bool {
            lhs.title == rhs.title &&
            lhs.subtitle == rhs.subtitle &&
            lhs.coordinate.latitude == rhs.coordinate.latitude &&
            lhs.coordinate.longitude == rhs.coordinate.longitude
        }
    }

    @State private var selectedCity: CitySelection? = nil
    @State private var isCityOverlayPresented = false

    // MARK: - Map
    @State private var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
    )

    private let maxSearchDistanceMiles: Double = 10.0
    private let farAwayCityThresholdMiles: Double = 500.0

    // MARK: - View
    var body: some View {
        ZStack {
            background

            ScrollView {
                VStack(spacing: 14) {
                    header
                    topRow
                    filterRow
                    spinButton
                    resetButton

                    if let restaurant = currentRestaurant {
                        restaurantCard(restaurant)
                            .padding(.top, 2)
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    }

                    if let msg = errorMessage {
                        Text(msg)
                            .font(.footnote)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    Spacer(minLength: 22)
                }
                .padding(.top, 18)
                .padding(.horizontal, 16)
                .frame(maxWidth: 560) // iPad-friendly
                .frame(maxWidth: .infinity)
            }

            if isCityOverlayPresented {
                ChooseCityOverlay(
                    isPresented: $isCityOverlayPresented,
                    userHintCoordinate: locationManager.lastLocation?.coordinate,
                    onUseCurrent: {
                        selectedCity = nil
                        errorMessage = nil
                        updateMapRegion()
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    },
                    onUseCity: { sel in
                        selectedCity = sel
                        errorMessage = nil
                        updateMapRegion()
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                )
                .transition(.opacity.combined(with: .scale))
                .zIndex(2)
            }
        }
        .onAppear {
            locationManager.start()
            updateMapRegion()
        }
        .onChange(of: locationManager.lastLocation) { _ in
            updateMapRegion()
        }
        .onChange(of: currentRestaurant) { _ in
            updateMapRegion()
            if let r = currentRestaurant { computeETAIfNeeded(for: r) }
        }
        .onChange(of: selectedCity) { _ in
            updateMapRegion()
        }
        .sheet(isPresented: $isNotesSheetPresented) {
            notesSheet
        }
    }

    // MARK: - Background / Header

    private var background: some View {
        LinearGradient(
            colors: [Color.orange.opacity(0.18), Color.pink.opacity(0.22)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("Dinescover")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(
                    LinearGradient(colors: [.orange, .pink], startPoint: .leading, endPoint: .trailing)
                )

        
        }
    }

    // MARK: - Top Row (Location + Change City)

    private var topRow: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: selectedCity == nil ? "location.circle.fill" : "airplane.circle.fill")
                    .foregroundColor(.blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text(spinningLocationLabel())
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                    if let miles = distanceUserToSelectedCityMiles(), let city = selectedCity {
                        Text("From you → \(city.title): \(String(format: "%.0f", miles)) miles")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            Button {
                withAnimation(.spring(response: 0.26, dampingFraction: 0.92)) {
                    isCityOverlayPresented = true
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                    Text("Change City")
                }
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
            }
        }
    }

    private func spinningLocationLabel() -> String {
        if let city = selectedCity {
            return "Spinning near: \(city.title)"
        }
        return "Spinning near: your current location"
    }

    // MARK: - Filter Row

    private var filterRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Food Preference")
                .font(.footnote.weight(.semibold))
                .foregroundColor(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(FoodFilter.allCases) { f in
                        Button {
                            selectedFilter = f
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            currentRestaurant = nil
                            errorMessage = nil
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: f.icon)
                                Text(f.rawValue)
                            }
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .foregroundColor(selectedFilter == f ? .white : .primary)
                            .background {
                                if selectedFilter == f {
                                    LinearGradient(
                                        colors: [.orange, .pink],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                } else {
                                    Color.white.opacity(0.68)
                                }
                            }
                            .clipShape(Capsule())
                            .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 3)
                        }
                    }
                }
            }
        }
        .padding(.top, 2)
    }

    // MARK: - Spin Button / Reset

    private var spinButton: some View {
        Button(action: spinForRestaurant) {
            HStack(spacing: 10) {
                Image(systemName: "fork.knife.circle.fill")
                Text(isSearching ? "Finding something tasty..." : "Spin for a Restaurant")
                    .font(.headline.weight(.bold))
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(colors: [.orange, .pink], startPoint: .leading, endPoint: .trailing)
            )
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .orange.opacity(0.25), radius: 10, x: 0, y: 6)
        }
        .disabled(isSearching)
        .padding(.top, 4)
    }

    private var resetButton: some View {
        Button {
            shownKeys.removeAll()
            dislikedKeys.removeAll()
            SpinStore.saveShown(shownKeys)
            SpinStore.saveDisliked(dislikedKeys)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.counterclockwise")
                Text("Reset Spins for This Area")
                    .fontWeight(.semibold)
            }
            .font(.footnote)
            .foregroundColor(.blue)
            .padding(.vertical, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Restaurant Card

    private func restaurantCard(_ restaurant: Restaurant) -> some View {
        let key = restaurantKey(restaurant)

        return VStack(alignment: .leading, spacing: 12) {

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(restaurantDisplayName(restaurant))
                        .font(.title2.weight(.bold))
                        .lineLimit(2)

                    Text(vibeLine(for: restaurant))
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Button {
                    favoritesManager.toggleFavorite(restaurant)
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                } label: {
                    Image(systemName: favoritesManager.isFavorite(restaurant) ? "heart.fill" : "heart")
                        .foregroundColor(.red)
                        .font(.title2)
                }
            }

            if let address = restaurant.mapItem.placemark.title {
                Text(address)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            // Click-to-call
            if let tel = telLink(for: restaurant) {
                Link(destination: tel) {
                    HStack(spacing: 8) {
                        Image(systemName: "phone.fill")
                        Text(displayPhone(for: restaurant))
                            .font(.footnote.weight(.semibold))
                    }
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(Color.white.opacity(0.78))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }

            HStack(spacing: 10) {
                Button {
                    openInMaps(restaurant)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "map")
                        Text("Open in Maps")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                shareLinkButton(for: restaurant)
            }

            HStack {
                Button {
                    notesDraft = notesByKey[key] ?? ""
                    isNotesSheetPresented = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "note.text")
                        Text((notesByKey[key] ?? "").isEmpty ? "Add Note" : "Edit Note")
                    }
                    .font(.footnote.weight(.semibold))
                }

                Spacer()

                Button(role: .destructive) {
                    markNotInterested(restaurant)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "hand.thumbsdown.fill")
                        Text("Not Interested")
                    }
                    .font(.footnote.weight(.semibold))
                }
            }

            mapPreview(for: restaurant)
                .frame(height: 230)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 6)
        )
    }

    private func shareLinkButton(for restaurant: Restaurant) -> some View {
        let title = restaurantDisplayName(restaurant)
        let url = shareURL(for: restaurant)

        if let url {
            return AnyView(
                ShareLink(item: url) {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Share")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.85))
                    .foregroundColor(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            )
        } else {
            return AnyView(
                ShareLink(item: title) {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Share")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.85))
                    .foregroundColor(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            )
        }
    }

    // MARK: - Map Preview

    private func mapPreview(for restaurant: Restaurant) -> some View {
        let userCoord = locationManager.lastLocation?.coordinate
        let restCoord = restaurant.mapItem.placemark.location?.coordinate
        let forceRestaurantOnly = isSelectedCityFarAwayOver500Miles()

        if #available(iOS 17.0, *) {
            return AnyView(
                Map(position: .constant(.region(mapRegion))) {
                    if let r = restCoord {
                        Annotation(restaurantDisplayName(restaurant), coordinate: r, anchor: .bottom) {
                            VStack(spacing: 6) {
                                Text(restaurantDisplayName(restaurant))
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.red.opacity(0.92))
                                    .clipShape(Capsule())
                                    .shadow(radius: 3)

                                Image(systemName: "mappin.and.ellipse")
                                    .font(.title2)
                                    .foregroundColor(.red)
                                    .shadow(radius: 3)
                            }
                        }
                    }

                    if !forceRestaurantOnly, let u = userCoord {
                        Annotation("You", coordinate: u) {
                            ZStack {
                                Circle().fill(Color.blue.opacity(0.18)).frame(width: 30, height: 30)
                                Circle().fill(Color.blue).frame(width: 14, height: 14)
                            }
                            .shadow(radius: 3)
                        }
                    }
                }
            )
        } else {
            return AnyView(Map(coordinateRegion: $mapRegion))
        }
    }

    // MARK: - Spin Logic

    private func spinForRestaurant() {
        errorMessage = nil

        let spinCenter: CLLocationCoordinate2D? = {
            if let city = selectedCity { return city.coordinate }
            return locationManager.lastLocation?.coordinate
        }()

        guard let center = spinCenter else {
            errorMessage = "Unable to get a location yet. Turn on location or choose a city."
            locationManager.start()
            return
        }

        isSearching = true

        restaurantFinder.findRestaurants(
            near: center,
            query: selectedFilter.query,
            preferredMinDistanceMiles: nil,
            maxDistanceMiles: maxSearchDistanceMiles
        ) { result in
            DispatchQueue.main.async {
                isSearching = false

                switch result {
                case .success(let restaurants):
                    guard !restaurants.isEmpty else {
                        self.errorMessage = "No results found. Try another filter or city."
                        return
                    }

                    let strictPool: [Restaurant] = {
                        guard self.selectedFilter == .strictHalal else { return restaurants }
                        let keywords = ["halal", "zabiha", "zabihah"]
                        let filtered = restaurants.filter { r in
                            let hay = "\(self.restaurantDisplayName(r)) \(r.mapItem.placemark.title ?? "")".lowercased()
                            return keywords.contains(where: { hay.contains($0) })
                        }
                        return filtered.isEmpty ? restaurants : filtered
                    }()

                    let unseen = strictPool.filter { r in
                        let k = self.restaurantKey(r)
                        return !self.dislikedKeys.contains(k) && !self.shownKeys.contains(k)
                    }

                    let pickPool = unseen.isEmpty
                    ? strictPool.filter { !self.dislikedKeys.contains(self.restaurantKey($0)) }
                    : unseen

                    guard let picked = pickPool.randomElement() else {
                        self.errorMessage = "No restaurants available. Try resetting spins."
                        return
                    }

                    let k = self.restaurantKey(picked)
                    self.shownKeys.insert(k)
                    SpinStore.saveShown(self.shownKeys)

                    if self.selectedFilter == .strictHalal {
                        self.whyTextByKey[k] = "Matches Halal search"
                    } else if !unseen.isEmpty {
                        self.whyTextByKey[k] = "Fresh pick you haven’t seen"
                    } else {
                        self.whyTextByKey[k] = "Top nearby option"
                    }

                    self.historyManager.add(picked)

                    withAnimation(.easeInOut(duration: 0.22)) {
                        self.currentRestaurant = picked
                    }

                    self.computeETAIfNeeded(for: picked)
                    self.updateMapRegion()

                case .failure:
                    self.errorMessage = "Unable to find places. Try again."
                }
            }
        }
    }

    private func markNotInterested(_ restaurant: Restaurant) {
        let key = restaurantKey(restaurant)
        dislikedKeys.insert(key)
        SpinStore.saveDisliked(dislikedKeys)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        currentRestaurant = nil
        spinForRestaurant()
    }

    // MARK: - Vibe Line

    private func vibeLine(for restaurant: Restaurant) -> String {
        let key = restaurantKey(restaurant)
        let eta = etaTextByKey[key] ?? "ETA…"
        let distance = restaurant.distanceText ?? "Distance…"
        let phone = displayPhone(for: restaurant)
        let why = whyTextByKey[key] ?? "New pick"
        return "\(eta) • \(distance) • \(phone) • \(why)"
    }

    // MARK: - ETA

    private func computeETAIfNeeded(for restaurant: Restaurant) {
        guard let userLoc = locationManager.lastLocation else { return }
        guard let destCoord = restaurant.mapItem.placemark.location?.coordinate else { return }

        let key = restaurantKey(restaurant)
        if etaTextByKey[key] != nil { return }

        if isSelectedCityFarAwayOver500Miles() {
            etaTextByKey[key] = "ETA N/A"
            return
        }

        let source = MKMapItem(placemark: MKPlacemark(coordinate: userLoc.coordinate))
        let dest = MKMapItem(placemark: MKPlacemark(coordinate: destCoord))

        let req = MKDirections.Request()
        req.source = source
        req.destination = dest
        req.transportType = .automobile

        MKDirections(request: req).calculateETA { response, _ in
            DispatchQueue.main.async {
                if let eta = response?.expectedTravelTime {
                    self.etaTextByKey[key] = self.formatETA(seconds: eta)
                } else {
                    self.etaTextByKey[key] = "ETA N/A"
                }
            }
        }
    }

    private func formatETA(seconds: TimeInterval) -> String {
        let minutes = Int(round(seconds / 60.0))
        if minutes < 1 { return "<1 min" }
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let rem = minutes % 60
        return rem == 0 ? "\(hours) hr" : "\(hours) hr \(rem) min"
    }

    // MARK: - Map Region Logic

    private func updateMapRegion() {
        let userCoord = locationManager.lastLocation?.coordinate
        let restCoord = currentRestaurant?.mapItem.placemark.location?.coordinate
        let cityCoord = selectedCity?.coordinate

        if isSelectedCityFarAwayOver500Miles(), let r = restCoord {
            mapRegion = safeRegion(center: r, spanDelta: 0.06)
            return
        }

        if let r = restCoord {
            let anchor = (selectedCity != nil) ? cityCoord : userCoord
            if let a = anchor {
                mapRegion = regionThatFits(a, r)
            } else {
                mapRegion = safeRegion(center: r, spanDelta: 0.06)
            }
            return
        }

        if let c = cityCoord {
            mapRegion = safeRegion(center: c, spanDelta: 0.14)
        } else if let u = userCoord {
            mapRegion = safeRegion(center: u, spanDelta: 0.16)
        }
    }

    private func safeRegion(center: CLLocationCoordinate2D, spanDelta: Double) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(
                latitudeDelta: clamp(spanDelta, min: 0.01, max: 120),
                longitudeDelta: clamp(spanDelta, min: 0.01, max: 120)
            )
        )
    }

    private func regionThatFits(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> MKCoordinateRegion {
        let minLat = min(a.latitude, b.latitude)
        let maxLat = max(a.latitude, b.latitude)
        let minLon = min(a.longitude, b.longitude)
        let maxLon = max(a.longitude, b.longitude)

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )

        var latDelta = (maxLat - minLat) * 1.8
        var lonDelta = (maxLon - minLon) * 1.8

        if latDelta == 0 { latDelta = 0.02 }
        if lonDelta == 0 { lonDelta = 0.02 }

        latDelta = clamp(latDelta, min: 0.01, max: 120)
        lonDelta = clamp(lonDelta, min: 0.01, max: 120)

        return MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta))
    }

    private func clamp(_ v: Double, min: Double, max: Double) -> Double {
        Swift.max(min, Swift.min(max, v))
    }

    private func isSelectedCityFarAwayOver500Miles() -> Bool {
        guard let user = locationManager.lastLocation?.coordinate,
              let city = selectedCity?.coordinate else { return false }
        return distanceMiles(from: user, to: city) > farAwayCityThresholdMiles
    }

    private func distanceUserToSelectedCityMiles() -> Double? {
        guard let user = locationManager.lastLocation?.coordinate,
              let city = selectedCity?.coordinate else { return nil }
        return distanceMiles(from: user, to: city)
    }

    private func distanceMiles(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude)) / 1609.34
    }

    // MARK: - Actions

    private func openInMaps(_ restaurant: Restaurant) {
        restaurant.mapItem.openInMaps(
            launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving]
        )
    }

    private func shareURL(for restaurant: Restaurant) -> URL? {
        if let url = restaurant.mapItem.url { return url }
        if let coord = restaurant.mapItem.placemark.location?.coordinate {
            let encoded = restaurantDisplayName(restaurant)
                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "Restaurant"
            return URL(string: "http://maps.apple.com/?ll=\(coord.latitude),\(coord.longitude)&q=\(encoded)")
        }
        return nil
    }

    // MARK: - Phone (Clickable)

    private func displayPhone(for restaurant: Restaurant) -> String {
        if let p = restaurant.mapItem.phoneNumber, !p.isEmpty {
            return "Call \(p)"
        }
        return "No phone"
    }

    private func telLink(for restaurant: Restaurant) -> URL? {
        guard let raw = restaurant.mapItem.phoneNumber, !raw.isEmpty else { return nil }
        let allowed = Set("0123456789+")
        let cleaned = raw.filter { allowed.contains($0) }
        guard !cleaned.isEmpty else { return nil }
        return URL(string: "tel://\(cleaned)")
    }

    // MARK: - Helpers

    private func restaurantDisplayName(_ r: Restaurant) -> String {
        if let v = r.mapItem.name, !v.isEmpty { return v }
        return r.name
    }

    private func restaurantKey(_ r: Restaurant) -> String {
        let name = restaurantDisplayName(r).lowercased()
        if let c = r.mapItem.placemark.location?.coordinate {
            return "\(name)|\(c.latitude),\(c.longitude)"
        }
        return name
    }

    // MARK: - Notes Sheet

    private var notesSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Notes")
                .font(.title3.bold())

            Text("Save a reminder for later (dish ideas, vibe, who to go with).")
                .font(.footnote)
                .foregroundColor(.secondary)

            TextEditor(text: $notesDraft)
                .frame(minHeight: 180)
                .padding(10)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            Spacer()

            HStack {
                Button("Cancel") { isNotesSheetPresented = false }
                    .foregroundColor(.secondary)

                Spacer()

                Button("Save") {
                    guard let r = currentRestaurant else { isNotesSheetPresented = false; return }
                    let key = restaurantKey(r)
                    notesByKey[key] = notesDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    NotesStore.save(notesByKey)
                    isNotesSheetPresented = false
                }
                .fontWeight(.semibold)
            }
        }
        .padding()
    }
}

// MARK: - Centered “Choose City” Overlay (autocomplete + clear X)

private struct ChooseCityOverlay: View {
    @Binding var isPresented: Bool
    let userHintCoordinate: CLLocationCoordinate2D?
    var onUseCurrent: () -> Void
    var onUseCity: (SpinView.CitySelection) -> Void

    @StateObject private var vm = CitySearchViewModel()

    var body: some View {
        ZStack {
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .onTapGesture { withAnimation { isPresented = false } }

            VStack(spacing: 14) {
                Text("Choose a City")
                    .font(.title3.weight(.bold))

                Text("Plan ahead by spinning restaurants in another city.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 6)

                VStack(alignment: .leading, spacing: 8) {
                    Text("City, State or Country")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)

                    HStack(spacing: 10) {
                        TextField("e.g., Dallas, TX or Sydney", text: $vm.query)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled(true)
                            .onChange(of: vm.query) { _ in
                                vm.updateCompleter(regionHint: userHintCoordinate)
                            }

                        if !vm.query.isEmpty {
                            Button {
                                vm.query = ""
                                vm.results = []
                                vm.updateCompleter(regionHint: userHintCoordinate)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                if !vm.results.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(vm.results.prefix(6), id: \.self) { item in
                            Button {
                                vm.resolve(displayString: item) { selection in
                                    guard let selection else { return }
                                    onUseCity(selection)
                                    withAnimation { isPresented = false }
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "mappin.and.ellipse")
                                        .foregroundColor(.pink)
                                    Text(item)
                                        .foregroundColor(.primary)
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 12)
                            }
                            .buttonStyle(.plain)

                            Divider().opacity(0.5)
                        }
                    }
                    .background(Color.white.opacity(0.88))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                Button {
                    vm.resolveTypedQuery { selection in
                        if let selection {
                            onUseCity(selection)
                            withAnimation { isPresented = false }
                        }
                    }
                } label: {
                    Text(vm.isResolving ? "Working..." : "Use This City")
                        .font(.headline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundColor(.white)
                        .background(
                            LinearGradient(colors: [.orange, .pink], startPoint: .leading, endPoint: .trailing)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .disabled(vm.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || vm.isResolving)

                Button {
                    onUseCurrent()
                    withAnimation { isPresented = false }
                } label: {
                    Text("Use Current Location Instead")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.blue)
                }

                Button {
                    withAnimation { isPresented = false }
                } label: {
                    Text("Close")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.secondary)
                }
                .padding(.top, 2)
            }
            .padding(18)
            .frame(maxWidth: 420)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: 10)
            .padding(.horizontal, 20)
        }
        .onAppear {
            vm.updateCompleter(regionHint: userHintCoordinate)
        }
    }
}

// MARK: - City search VM (autocomplete + safe resolve)

private final class CitySearchViewModel: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var query: String = ""
    @Published var results: [String] = []
    @Published var isResolving: Bool = false

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address]
    }

    func updateCompleter(regionHint: CLLocationCoordinate2D?) {
        completer.queryFragment = query
        if let hint = regionHint {
            completer.region = MKCoordinateRegion(
                center: hint,
                span: MKCoordinateSpan(latitudeDelta: 1.2, longitudeDelta: 1.2)
            )
        }
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        results = completer.results.map { $0.title + ( $0.subtitle.isEmpty ? "" : ", " + $0.subtitle ) }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        results = []
    }

    func resolveTypedQuery(completion: @escaping (SpinView.CitySelection?) -> Void) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { completion(nil); return }
        resolve(displayString: trimmed, completion: completion)
    }

    func resolve(displayString: String, completion: @escaping (SpinView.CitySelection?) -> Void) {
        isResolving = true

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = displayString
        request.resultTypes = .address

        MKLocalSearch(request: request).start { response, error in
            DispatchQueue.main.async {
                self.isResolving = false

                guard error == nil,
                      let item = response?.mapItems.first,
                      let coord = item.placemark.location?.coordinate else {
                    completion(nil)
                    return
                }

                let title = item.name ?? displayString
                let subtitle = item.placemark.title ?? ""
                completion(SpinView.CitySelection(title: title, subtitle: subtitle, coordinate: coord))
            }
        }
    }
}

// MARK: - Persistence

private enum SpinStore {
    private static let shownKey = "dinescover_spun_keys_v1"
    private static let dislikedKey = "dinescover_disliked_keys_v1"

    static func loadShown() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: shownKey) ?? [])
    }
    static func saveShown(_ set: Set<String>) {
        UserDefaults.standard.set(Array(set), forKey: shownKey)
    }

    static func loadDisliked() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: dislikedKey) ?? [])
    }
    static func saveDisliked(_ set: Set<String>) {
        UserDefaults.standard.set(Array(set), forKey: dislikedKey)
    }
}

private enum NotesStore {
    private static let key = "dinescover_notes_v1"

    static func load() -> [String: String] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    static func save(_ dict: [String: String]) {
        if let data = try? JSONEncoder().encode(dict) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
