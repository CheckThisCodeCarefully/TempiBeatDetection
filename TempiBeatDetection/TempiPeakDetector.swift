//
//  TempiPeakDetector.swift
//  TempiBeatDetection
//
//  Created by John Scalo on 3/24/16.
//  Copyright © 2016 John Scalo. See accompanying License.txt for terms.

import Foundation
import Accelerate

struct TempiPeak {
    var timeStamp: Double
    var magnitude: Float
}

typealias TempiPeakDetectionCallback = (
    timeStamp: Double,
    magnitude: Float
    ) -> Void

class TempiPeakDetector: NSObject {
    
    /// The rate at which the peak detector samples magnitudes, not the sample rate at which audio is captured
    var sampleRate: Float
    
    /// The detector will coalesce peaks around this many samples, selecting the largest.
    var coalesceInterval: Double = 0.0
    
    private var sampleInterval: Double
    
    private var trailingSamples: [Float] = [Float]()
    private var peakQueue: [TempiPeak] = [TempiPeak]()

    private var isOnsetting: Bool = false
    
    // We save recentHistoryDuration worth (currently 1s) of recent magnitudes. For an incoming magnitude m
    // to be considered a peak (in addition to satisfying other requirements) it must also satisfy:
    // m > max(recentMags) * recentMaxThresholdRatio. Lower threshold ratios will result in more peaks
    // but potentially more noise. Higher ratios will result in fewer peaks and less noise but may miss valid data.
    // NB: 0.6 and 1.25 were found by trial and error to be optimal choices.
    private var recentMaxThresholdRatio: Float = 0.6
    private var recentHistoryDuration: Float = 1.25
    
    private var counter: Int = 0
    private var lastMagnitude: Float = 0.0
    private var peakDetectionCallback: TempiPeakDetectionCallback!
    
    private var lastPeakTick: Int = 0

    init(peakDetectionCallback callback: TempiPeakDetectionCallback, sampleRate: Float) {
        self.peakDetectionCallback = callback
        self.sampleRate = sampleRate
        self.sampleInterval = 1.0 / Double(sampleRate)
    }
    
    // Add a magnitude to the analysis window and return whether it resulted in a peak or not.
    func addMagnitude(timeStamp timeStamp: Double, magnitude: Float) {
        var recentMax: Float = 0.0
        
        // Make our reference for the overall max go back 1 second
        let trailingWindowSize: Int = Int(sampleRate * self.recentHistoryDuration)
        
        // What's the largest previous value over our long window length?
        if (self.trailingSamples.count > 0) {
            vDSP_maxv(self.trailingSamples, 1, &recentMax, UInt(self.trailingSamples.count))
        }
        
        // recentMax * recentMaxThresholdRatio must also be exceeded
        let longWindowThreshold = recentMax * recentMaxThresholdRatio

        // Push the latest value into trailingSamples
        self.trailingSamples.append(magnitude)
        if self.trailingSamples.count > trailingWindowSize {
            self.trailingSamples.removeFirst()
        }
        
        if self.counter > Int(self.sampleRate) && // Don't start returning peaks until we have at least 1 second worth of data
           magnitude < self.lastMagnitude &&
           self.isOnsetting
        {
            // We previously detected an onset on the way to a peak, and now we're descending again, so potentially call this a peak.
            // NB: self.lastMagnitude is the peak, not magnitude.
            let actualTimeStamp = timeStamp - sampleInterval
            self.handlePeak(timeStamp: actualTimeStamp, magnitude: self.lastMagnitude, longWindowThreshold: longWindowThreshold)
        } else {
            self.isOnsetting = magnitude > self.lastMagnitude
        }
        
        self.counter += 1
        self.lastMagnitude = magnitude
        
        self.evaluatePeakQueue(timeStamp)
    }
    
    private func handlePeak(timeStamp timeStamp: Double, magnitude: Float, longWindowThreshold: Float) {
        self.isOnsetting = false
        
        // We might have a peak, but only if the incoming magnitude > some fraction of the loudest recent (1s) mag
        if magnitude >= longWindowThreshold {
            if (self.coalesceInterval == 0.0) {
                self.peakDetectionCallback(timeStamp: timeStamp, magnitude: magnitude)
            } else {
                peakQueue.append(TempiPeak(timeStamp: timeStamp, magnitude: magnitude))
            }
        }
    }
    
    private func evaluatePeakQueue(timeStamp: Double) {
        if (self.coalesceInterval == 0.0) {
            return;
        }
        
        // If it's been longer than coalesceInterval since last sending a peak, coalesce them and send.
        guard let oldestPeak: TempiPeak = self.peakQueue.first else {
            // Nothing in the q. Return.
            return
        }
        
        if timeStamp - oldestPeak.timeStamp > self.coalesceInterval {
            var max: TempiPeak = TempiPeak(timeStamp: 0, magnitude: 0)
            for p: TempiPeak in self.peakQueue {
                if p.magnitude > max.magnitude {
                    max = p
                }
            }

            self.peakQueue.removeAll()
            self.peakDetectionCallback(timeStamp: max.timeStamp, magnitude: max.magnitude)
        }
    }
    
    
}
