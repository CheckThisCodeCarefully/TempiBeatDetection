//
//  TempiUtilities.swift
//  TempiBeatDetection
//
//  Created by John Scalo on 1/8/16.
//  Copyright © 2016 John Scalo. See accompanying License.txt for terms.

import Foundation
import Accelerate

func tempi_dispatch_delay(delay:Double, closure:()->()) {
    dispatch_after(
        dispatch_time(
            DISPATCH_TIME_NOW,
            Int64(delay * Double(NSEC_PER_SEC))
        ),
        dispatch_get_main_queue(), closure)
}

func tempi_is_power_of_2 (n: Int) -> Bool {
    let lg2 = logbf(Float(n))
    return remainderf(Float(n), powf(2.0, lg2)) == 0
}

func tempi_max(a: [Float]) -> Float {
    var max: Float = 0.0
    
    vDSP_maxv(a, 1, &max, UInt(a.count))
    return max
}

func tempi_smooth(a: [Float], w: Int) -> [Float] {
    var newA: [Float] = [Float]()
    
    for i in 0..<a.count {
        let realW = min(w, a.count - i)
        var avg: Float = 0.0
        let subArray: [Float] = Array(a[i..<i+realW])
        vDSP_meanv(subArray, 1, &avg, UInt(realW))
        newA.append(avg)
    }
    
    return newA
}

func tempi_median(a: [Float]) -> Float {
    // I tried to make this an Array extension and failed. See below.
    let sortedArray : [Float] = a.sort( { $0 < $1 } )
    var median : Float
    
    if sortedArray.count == 1 {
        return sortedArray[0]
    }
    
    if sortedArray.count % 2 == 0 {
        let f1 : Float = sortedArray[sortedArray.count / 2 - 1]
        let f2 : Float = sortedArray[sortedArray.count / 2]
        median = (f1 + f2) / 2.0
    } else {
        median = sortedArray[sortedArray.count / 2]
    }
    
    return median
}

func tempi_mean(a: [Float]) -> Float {
    // Again, would be better as an Array extension.
    var total : Float = 0
    for (_, f) in a.enumerate() {
        total += f
    }
    return total/Float(a.count)
}

//extension Array where Element : IntegerArithmeticType {
//    func median() -> Float {
//        let sortedArray : [Float] = a.sort( { $0 < $1 } )
//        var median : Float
//        
//        if sortedArray.count == 1 {
//            return sortedArray[0]
//        }
//        
//        if sortedArray.count % 2 == 0 {
//            let f1 : Float = sortedArray[sortedArray.count / 2 - 1]
//            let f2 : Float = sortedArray[sortedArray.count / 2]
//            median = (f1 + f2) / 2.0
//        } else {
//            median = sortedArray[sortedArray.count / 2]
//        }
//        
//        return median
//    }
//}
