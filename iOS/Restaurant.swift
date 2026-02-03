//
//  Restaurant.swift
//  RestrauntPicker
//
//  Created by Liiban on 12/2/25.
//
import Foundation
import MapKit

struct Restaurant: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let mapItem: MKMapItem
    let distanceText: String?
}



