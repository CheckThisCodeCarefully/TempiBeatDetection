//
//  TempiBeatDetector.swift
//  TempiBeatDetection
//
//  Created by John Scalo on 4/27/16.
//  Copyright © 2016 John Scalo. See accompanying License.txt for terms.

import Foundation
import Accelerate

typealias TempiBeatDetectionCallback = (
    timeStamp: Double,
    bpm: Float
    ) -> Void

struct TempiPeakInterval {
    var timeStamp: Double
    var magnitude: Float
    var interval: Float
}

class TempiBeatDetector: NSObject {
    
    // All 3 of sampleRate, chunkSize, and hopSize must be changed in conjunction. (Halve one, halve all of them.)
    var sampleRate: Float = 22050
    
    /// The size in samples of the audio buffer that gets analyzed during each pass
    var chunkSize: Int = 2048
    
    /// The size in samples that we skip between passes
    var hopSize: Int = 90
    
    /// Minimum/maximum tempos that the beat detector can detect. Smaller ranges yield greater accuracy.
    var minTempo: Float = 60
    var maxTempo: Float = 220

    /// The number of bands to split the audio signal into. 6, 12, or 30 supported.
    var frequencyBands: Int = 12

    var beatDetectionHandler: TempiBeatDetectionCallback!
    
    private var audioInput: TempiAudioInput!
    private var peakDetector: TempiPeakDetector!
    private var lastMagnitudes: [Float]!
    
    // Bucketing
    private var peakHistoryLength: Double = 4.0 // The time in seconds that we want intervals for before we do a bucket analysis to predict a tempo
    private var peakHistory: [TempiPeakInterval]! // Stores the last n peaks
    private var bucketCnt: Int = 10 // We'll separate the intervals into this many buckets. i.e. each will have a range of ((60/minTempo) - (60/maxTempo))/bucketCnt.
    
    // Audio input
    private var queuedSamples: [Float]!
    private var queuedSamplesPtr: Int = 0
    private var savedTimeStamp: Double!
    
    // Peak detection
    private var lastPeakTimeStamp: Double!
    
    // Confidence ratings
    private var confidence: Int = 0
    private var lastMeasuredTempo: Float = 0.0

    private var firstPass: Bool = true
    
    // For validation
    var startTime: Double = 0.0
    var endTime: Double = 0.0
    var savePlotData: Bool = false
    var testTotal: Int = 0
    var testCorrect: Int = 0
    var testSetResults: [Float]!
    var testActualTempo: Float = 0
    var currentTestName, currentTestSetName: String!
    var plotFFTDataFile, plotMarkersFile, plotAudioSamplesFile: UnsafeMutablePointer<FILE>!
    var allow2XResults: Bool = true
    var allowedTempoVariance: Float = 2.0
    
#if os(iOS)
    func startFromMic() {
        if self.audioInput == nil {
            self.audioInput = TempiAudioInput(audioInputCallback: { (timeStamp, numberOfFrames, samples) in
                self.handleMicAudio(timeStamp: timeStamp, numberOfFrames: numberOfFrames, samples: samples)
                }, sampleRate: self.sampleRate, numberOfChannels: 1)
        }

        self.setupCommon()
        self.setupInput()
        self.audioInput.startRecording()
    }
    
    func stop() {
        self.audioInput.stopRecording()
    }
    
    private func handleMicAudio(timeStamp timeStamp: Double, numberOfFrames:Int, samples:[Float]) {
        
        if (self.queuedSamples.count + numberOfFrames < self.chunkSize) {
            // We're not going to have enough samples for analysis. Queue the samples and save off the timeStamp.
            self.queuedSamples.appendContentsOf(samples)
            if self.savedTimeStamp == nil {
                self.savedTimeStamp = timeStamp
            }
            return
        }
        
        self.queuedSamples.appendContentsOf(samples)

        var baseTimeStamp: Double = self.savedTimeStamp != nil ? self.savedTimeStamp : timeStamp
        
        while self.queuedSamples.count >= self.chunkSize {
            let subArray: [Float] = Array(self.queuedSamples[0..<self.chunkSize])
            self.analyzeAudioChunk(timeStamp: baseTimeStamp, samples: subArray)
            self.queuedSamplesPtr += self.hopSize
            self.queuedSamples.removeFirst(self.hopSize)
            baseTimeStamp += Double(self.hopSize)/Double(self.sampleRate)
        }
        
        self.savedTimeStamp = nil
    }
    
    func setupCommon() {
        self.lastMagnitudes = [Float](count: self.frequencyBands, repeatedValue: 0)
        self.peakHistory = [TempiPeakInterval]()
        
        self.peakDetector = TempiPeakDetector(peakDetectionCallback: { (timeStamp, magnitude) in
            self.handlePeak(timeStamp: timeStamp, magnitude: magnitude)
            }, sampleRate: self.sampleRate / Float(self.hopSize))
        
        self.peakDetector.coalesceInterval = 0.1
        self.lastPeakTimeStamp = nil
        self.lastMeasuredTempo = 0
        self.confidence = 0
        self.firstPass = true
    }

    private func setupInput() {
        self.queuedSamples = [Float]()
        self.queuedSamplesPtr = 0
    }
#endif
    
    func analyzeAudioChunk(timeStamp timeStamp: Double, samples: [Float]) {
        let (magnitude, success) = self.calculateMagnitude(timeStamp: timeStamp, samples: samples)
        if (!success) {
            return;
        }
        
        if self.savePlotData {
            fputs("\(timeStamp) \(magnitude)\n", self.plotFFTDataFile)
        }

        self.peakDetector.addMagnitude(timeStamp: timeStamp, magnitude: magnitude)
    }
    
    private func handlePeak(timeStamp timeStamp: Double, magnitude: Float) {
        if (self.lastPeakTimeStamp == nil) {
            self.lastPeakTimeStamp = timeStamp
            return
        }
        
        let interval: Double = timeStamp - self.lastPeakTimeStamp
        
        if self.savePlotData {
            fputs("\(timeStamp) 1\n", self.plotMarkersFile)
        }
        
        let mappedInterval = self.mapInterval(interval)
        let peakInterval = TempiPeakInterval(timeStamp: timeStamp, magnitude: magnitude, interval: Float(mappedInterval))
        self.peakHistory.append(peakInterval)
        
        if self.peakHistory.count >= 2 &&
            (self.peakHistory.last?.timeStamp)! - (self.peakHistory.first?.timeStamp)! >= self.peakHistoryLength {
            self.performBucketAnalysisAtTimeStamp(timeStamp)
        }
        
        self.lastPeakTimeStamp = timeStamp
    }
    
    private func calculateMagnitude(timeStamp timeStamp: Double, samples: [Float]) -> (magnitude: Float, success: Bool) {
        let fft: TempiFFT = TempiFFT(withSize: self.chunkSize, sampleRate: self.sampleRate)
        fft.windowType = TempiFFTWindowType.hanning
        fft.fftForward(samples)
        
        switch self.frequencyBands {
            case 6:     fft.calculateLogarithmicBands(minFrequency: 100, maxFrequency: 5512, bandsPerOctave: 1)
            case 12:    fft.calculateLogarithmicBands(minFrequency: 100, maxFrequency: 5512, bandsPerOctave: 2)
            case 30:    fft.calculateLogarithmicBands(minFrequency: 100, maxFrequency: 5512, bandsPerOctave: 5)
            default:    assert(false, "Unsupported number of bands.")
        }
        
        // Use the spectral flux+median max algorithm mentioned in https://bmcfee.github.io/papers/icassp2014_beats.pdf .
        // Basically, instead of summing magnitudes across frequency bands we take the log for each band,
        // subtract it from the same band on the last pass, and then find the median of those diffs across
        // frequency bands. This gives a smoother envelope than the summing algorithm.
        
        var diffs: Array = [Float]()
        for i in 0..<self.frequencyBands {
            var mag = fft.magnitudeAtBand(i)
            
            if mag > 0.0 {
                mag = log10f(mag)
            }
            
            // The 1000.0 here isn't important; just makes the data easier to see in plots, etc.
            let diff: Float = 1000.0 * max(0.0, mag - self.lastMagnitudes[i])
            
            self.lastMagnitudes[i] = mag
            diffs.append(diff)
        }
        
        if self.firstPass {
            // Don't act on the very first pass since there are no diffs to compare.
            self.firstPass = false
            return (0.0, false)
        }

        return (tempi_median(diffs), true)
    }
    
    private func performBucketAnalysisAtTimeStamp(timeStamp: Double) {
        var buckets = [[Float]].init(count: self.bucketCnt, repeatedValue: [Float]())
        
        let minInterval: Float = 60.0/self.maxTempo
        let maxInterval: Float = 60.0/self.minTempo
        let range = maxInterval - minInterval
        var originalBPM: Float = 0.0
        var adjusted = false
        
        for i in 0..<self.peakHistory.count {
            let nextInterval = self.peakHistory[i]
            var bucketIdx: Int = Int(roundf((nextInterval.interval - minInterval)/range * Float(self.bucketCnt)))
            bucketIdx = min(bucketIdx, self.bucketCnt - 1)
            buckets[bucketIdx].append(nextInterval.interval)
        }
        
        // Eliminate stale intervals.
        self.peakHistory = self.peakHistory.filter({
            return timeStamp - $0.timeStamp <= self.peakHistoryLength
        })
        
        // Sort to find which bucket has the most intervals.
        buckets = buckets.sort({ $0.count < $1.count })
        
        // The predominant bucket is the last.
        let predominantIntervals = buckets.last
        
        // Use the median interval for prediction.
        let medianPredominantInterval = tempi_median(predominantIntervals!)
        
        // Divide into 60 to get the bpm.
        var bpm = 60.0 / medianPredominantInterval
        
        var multiple: Float = 0.0
        
        if self.lastMeasuredTempo == 0 || self.tempo(bpm, isNearTempo: self.lastMeasuredTempo, epsilon: 2.0) {
            // The tempo remained constant. Bump our confidence up a notch.
            self.confidence = min(10, self.confidence + 1)
        } else if self.tempo(bpm, isMultipleOf: self.lastMeasuredTempo, multiple: &multiple) {
            // The tempo changed but it's still a multiple of the last. Adapt it by that multiple but don't change confidence.
            originalBPM = bpm
            bpm = bpm / multiple
            adjusted = true
        } else {
            // Drop our confidence down a notch
            self.confidence = max(0, self.confidence - 1)
            if self.confidence > 7 {
                // The tempo changed but our confidence level in the old tempo was high.
                // Don't report this result.
                print(String(format: "%0.2f: IGNORING bpm = %0.2f", timeStamp, bpm));
                self.lastMeasuredTempo = bpm
                return
            }
        }
        
        if self.beatDetectionHandler != nil {
            self.beatDetectionHandler(timeStamp: timeStamp, bpm: bpm)
        }
        
        if adjusted {
            print(String(format:"%0.2f: bpm = %0.2f (adj from %0.2f)", timeStamp, bpm, originalBPM));
        } else {
            print(String(format:"%0.2f: bpm = %0.2f", timeStamp, bpm));
        }
        
        self.testTotal += 1
        if self.tempo(bpm, isNearTempo: self.testActualTempo, epsilon: self.allowedTempoVariance) {
            self.testCorrect += 1
        } else {
            if self.tempo(bpm, isNearTempo: 2.0 * self.testActualTempo, epsilon: self.allowedTempoVariance) ||
                self.tempo(bpm, isNearTempo: 0.5 * self.testActualTempo, epsilon: self.allowedTempoVariance) {
                self.testCorrect += 1
            }
        }
        
        self.lastMeasuredTempo = bpm
    }
    
    private func mapInterval(interval: Double) -> Double {
        var mappedInterval = interval
        let minInterval: Double = 60.0 / Double(self.maxTempo)
        let maxInterval: Double = 60.0 / Double(self.minTempo)
        
        while mappedInterval < minInterval {
            mappedInterval *= 2.0
        }
        while mappedInterval > maxInterval {
            mappedInterval /= 2.0
        }
        return mappedInterval
    }
    
    private func tempo(tempo1: Float, isMultipleOf tempo2: Float, inout multiple: Float) -> Bool
    {
        let multiples: [Float] = [0.5, 1.5, 1.33333, 2.0]
        for m in multiples {
            if self.tempo(m * tempo2, isNearTempo: tempo1, epsilon: m * 3.0) {
                multiple = m
                return true
            }
        }
        
        return false
    }

    private func tempo(tempo1: Float, isNearTempo tempo2: Float, epsilon: Float) -> Bool {
        return tempo2 - epsilon < tempo1 && tempo2 + epsilon > tempo1;
    }
    
}