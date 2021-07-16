//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation

func minMaxNormalization(_ x: Double, min: Double, max: Double) -> Double {
    precondition(min < max)
    let x = clamp(x, min: min, max: max)
    return (x - min) / (max - min)
}

func easeInOut(_ t: Double) -> Double {
    return t * t * (3 - 2 * t)
}

func clamp<T: Comparable>(_ x: T, min: T, max: T) -> T {
    return x < min ? min : x > max ? max : x
}
