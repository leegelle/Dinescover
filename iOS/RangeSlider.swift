//
//  RangeSlider.swift
//  RestrauntPicker
//
//  Created by Liiban on 12/5/25.
//

import SwiftUI

struct RangeSlider: View {
    @Binding var lower: Double
    @Binding var upper: Double
    let minValue: Double
    let maxValue: Double
    
    @State private var activeThumb: Thumb? = nil
    
    private enum Thumb {
        case lower
        case upper
    }
    
    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            
            ZStack {
                // Full track
                Capsule()
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 6)
                
                // Selected range
                Capsule()
                    .fill(Color.orange)
                    .frame(
                        width: rangeWidth(in: width),
                        height: 6
                    )
                    .offset(x: rangeOffset(in: width))
                
                // Upper knob
                knob
                    .offset(x: xOffset(for: upper, in: width))
                
                // Lower knob
                knob
                    .offset(x: xOffset(for: lower, in: width))
            }
            .contentShape(Rectangle()) // whole area responds to drag
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let locationX = value.location.x
                        let percent = clamp(locationX / width)
                        let newValue = minValue + Double(percent) * (maxValue - minValue)
                        
                        // Decide which thumb to move when drag starts
                        if activeThumb == nil {
                            let lowerX = xPos(for: lower, in: width)
                            let upperX = xPos(for: upper, in: width)
                            
                            let distToLower = abs(Double(locationX - lowerX))
                            let distToUpper = abs(Double(locationX - upperX))
                            
                            activeThumb = distToLower < distToUpper ? .lower : .upper
                        }
                        
                        switch activeThumb {
                        case .lower:
                            // lower can't exceed upper
                            let clamped = min(max(newValue, minValue), upper)
                            lower = clamped
                        case .upper:
                            // upper can't go below lower
                            let clamped = max(min(newValue, maxValue), lower)
                            upper = clamped
                        case .none:
                            break
                        }
                    }
                    .onEnded { _ in
                        activeThumb = nil
                    }
            )
        }
        .frame(height: 44)
    }
    
    // MARK: - Visual pieces
    
    private var knob: some View {
        Circle()
            .fill(Color.white)
            .shadow(radius: 3)
            .frame(width: 28, height: 28)
    }
    
    // MARK: - Geometry helpers
    
    private func clamp(_ value: CGFloat) -> CGFloat {
        max(0, min(1, value))
    }
    
    private func xPos(for value: Double, in width: CGFloat) -> CGFloat {
        let percent = (value - minValue) / (maxValue - minValue)
        return CGFloat(percent) * width
    }
    
    private func xOffset(for value: Double, in width: CGFloat) -> CGFloat {
        xPos(for: value, in: width) - width / 2
    }
    
    private func rangeWidth(in width: CGFloat) -> CGFloat {
        let lowerX = xPos(for: lower, in: width)
        let upperX = xPos(for: upper, in: width)
        return max(upperX - lowerX, 0)
    }
    
    private func rangeOffset(in width: CGFloat) -> CGFloat {
        let lowerX = xPos(for: lower, in: width)
        let upperX = xPos(for: upper, in: width)
        let mid = (lowerX + upperX) / 2
        return mid - width / 2
    }
}
