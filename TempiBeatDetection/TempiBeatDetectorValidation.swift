//
//  TempiBeatDetectorValidation.swift
//  TempiBeatDetection
//
//  Created by John Scalo on 5/1/16.
//  Copyright © 2016 John Scalo. See accompanying License.txt for terms.

import Foundation
import AVFoundation

extension TempiBeatDetector {
    
    func validate() {
//        self.validateStudioSet1()
        self.validateHomeSet1()
//        self.validateThreesSet1()
//        self.validateUtilitySet1()

    }
    
    private func projectURL() -> NSURL {
        let projectPath = "/Users/jscalo/Developer/Tempi/com.github/TempiBeatDetection"
        return NSURL.fileURLWithPath(projectPath)
    }

    private func validationSetup() {
        if self.savePlotData {
            let projectURL: NSURL = self.projectURL()
            
            var plotDataURL = projectURL.URLByAppendingPathComponent("Peak detection plots")
            plotDataURL = plotDataURL.URLByAppendingPathComponent("\(self.currentTestName)-plotData.txt")
            
            var plotMarkersURL = projectURL.URLByAppendingPathComponent("Peak detection plots")
            plotMarkersURL = plotMarkersURL.URLByAppendingPathComponent("\(self.currentTestName)-plotMarkers.txt")
            
            do {
                try NSFileManager.defaultManager().removeItemAtURL(plotDataURL)
                try NSFileManager.defaultManager().removeItemAtURL(plotMarkersURL)
            } catch _ { /* normal if file not yet created */ }
            
            self.plotFFTDataFile = fopen(plotDataURL.fileSystemRepresentation, "w")
            self.plotMarkersFile = fopen(plotMarkersURL.fileSystemRepresentation, "w")
        }
        
        self.testTotal = 0
        self.testCorrect = 0
    }
    
    private func validationFinish() {
        let result = 100.0 * Float(self.testCorrect) / Float(self.testTotal)
        print(String(format:"[%@] accuracy: %.01f%%\n", self.currentTestName, result));
        self.testSetResults.append(result)
    }
    
    private func testAudio(path: String,
                           label: String,
                           actualTempo: Float,
                           startTime: Double = 0.0, endTime: Double = 0.0,
                           minTempo: Float = 40.0, maxTempo: Float = 240.0,
                           variance: Float = 2.0) {
        
        let projectURL: NSURL = self.projectURL()
        let songURL = projectURL.URLByAppendingPathComponent("Test Media/\(path)")
        
        let avAsset: AVURLAsset = AVURLAsset(URL: songURL)
        
        print("Start testing: \(path)")
        
        self.currentTestName = label;
        
        self.startTime = startTime
        self.endTime = endTime
        
        self.minTempo = minTempo
        self.maxTempo = maxTempo
        
        self.setupCommon()
        self.validationSetup()
        
        self.allowedTempoVariance = variance
        
        let assetReader: AVAssetReader
        do {
            assetReader = try AVAssetReader(asset: avAsset)
        } catch let e as NSError {
            print("*** AVAssetReader failed with \(e)")
            return
        }
        
        let settings: [String : AnyObject] = [ AVFormatIDKey : Int(kAudioFormatLinearPCM),
                         AVSampleRateKey : self.sampleRate,
                         AVLinearPCMBitDepthKey : 32,
                         AVLinearPCMIsFloatKey : true,
                         AVNumberOfChannelsKey : 1 ]
        
        let output: AVAssetReaderAudioMixOutput = AVAssetReaderAudioMixOutput.init(audioTracks: avAsset.tracks, audioSettings: settings)
        
        assetReader.addOutput(output)
        
        if !assetReader.startReading() {
            print("assetReader.startReading() failed")
            return
        }
        
        var samplePtr: Int = 0
        
        self.testActualTempo = actualTempo
        
        var queuedSamples: [Float] = [Float]()
        
        repeat {
            var status: OSStatus = 0
            guard let nextBuffer = output.copyNextSampleBuffer() else {
                break
            }
            
            let bufferSampleCnt = CMSampleBufferGetNumSamples(nextBuffer)
            
            var bufferList = AudioBufferList(
                mNumberBuffers: 1,
                mBuffers: AudioBuffer(
                    mNumberChannels: 1,
                    mDataByteSize: 4,
                    mData: nil))
            
            var blockBuffer: CMBlockBuffer?
            
            status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(nextBuffer,
                                                                             nil,
                                                                             &bufferList,
                                                                             sizeof(AudioBufferList),
                                                                             nil,
                                                                             nil,
                                                                             kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
                                                                             &blockBuffer)
            
            if status != 0 {
                print("*** CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer failed with error \(status)")
                break
            }
            
            // Move samples from mData into our native [Float] format.
            // (There's probably an better way to do this using UnsafeBufferPointer but I couldn't make it work.)
            for i in 0..<bufferSampleCnt {
                let ptr = UnsafePointer<Float>(bufferList.mBuffers.mData)
                let newPtr = ptr + i
                let sample = unsafeBitCast(newPtr.memory, Float.self)
                queuedSamples.append(sample)
            }

            // We have a big buffer of audio (whatever CoreAudio decided to give us).
            // Now iterate over the buffer, sending a chunkSize's (e.g. 4096 samples) worth of data to the analyzer and then
            // shifting by hopSize (e.g. 132 samples) after each iteration. If there's not enough data in the buffer (bufferSampleCnt < chunkSize),
            // then add the data to the queue and get the next buffer.

            while queuedSamples.count >= self.chunkSize {
                let timeStamp: Double = Double(samplePtr) / Double(self.sampleRate)
                
                if self.endTime > 0.01 {
                    if timeStamp < self.startTime || timeStamp > self.endTime {
                        queuedSamples.removeFirst(self.hopSize)
                        samplePtr += self.hopSize
                        continue
                    }
                }
                
                let subArray: [Float] = Array(queuedSamples[0..<self.chunkSize])
                
                self.analyzeAudioChunk(timeStamp: timeStamp, samples: subArray)
                
                samplePtr += self.hopSize
                queuedSamples.removeFirst(self.hopSize)
            }
            
        } while true
        
        print("Finished testing: \(path)")
        
        if self.savePlotData {
            fclose(self.plotFFTDataFile)
            fclose(self.plotMarkersFile)
        }
        
        self.validationFinish()
    }
    
    private func testSetSetupForSetName(setName: String) {
        print("Starting validation set \(setName)");
        self.currentTestSetName = setName
        self.testSetResults = [Float]()
    }
    
    private func testSetFinish() {
        let mean: Float = tempi_mean(self.testSetResults)
        print(String(format:"Validation set [%@] accuracy: %.01f%%\n", self.currentTestSetName, mean));
    }
    
    private func oneOffTest() {
        self.testSetSetupForSetName("oneOff")

        self.testAudio("Studio/Learn To Fly.mp3",
                       label: "learn-to-fly",
                       actualTempo: 136,
                       startTime: 0, endTime: 15,
                       minTempo: 80, maxTempo: 160,
                       variance: 2)
        
        self.testSetFinish()
    }
    
    private func validateStudioSet1 () {
        self.testSetSetupForSetName("studioSet1")
        
        self.testAudio("Studio/Skinny Sweaty Man.mp3",
                       label: "skinny-sweaty-man",
                       actualTempo: 141,
                       startTime: 0, endTime: 15,
                       minTempo: 80, maxTempo: 160,
                       variance: 3)
        
        self.testAudio("Studio/Satisfaction.mp3",
                       label: "satisfaction",
                       actualTempo: 137,
                       startTime: 0, endTime: 20,
                       minTempo: 80, maxTempo: 160,
                       variance: 2.5)

        self.testAudio("Studio/Louie, Louie.mp3",
                       label: "louie-louie",
                       actualTempo: 120,
                       startTime: 0, endTime: 15,
                       minTempo: 60, maxTempo: 120,
                       variance: 3)

        self.testAudio("Studio/Learn To Fly.mp3",
                       label: "learn-to-fly",
                       actualTempo: 136,
                       startTime: 0, endTime: 15,
                       minTempo: 80, maxTempo: 160,
                       variance: 2)

        self.testAudio("Studio/HBFS.mp3",
                       label: "harder-better-faster-stronger",
                       actualTempo: 123,
                       startTime: 0, endTime: 15,
                       minTempo: 80, maxTempo: 160,
                       variance: 2)

        self.testAudio("Studio/Waving Flag.mp3",
                       label: "waving-flag",
                       actualTempo: 76,
                       startTime: 0, endTime: 15,
                       minTempo: 60, maxTempo: 120,
                       variance: 2)

        self.testAudio("Studio/Back in Black.mp3",
                       label: "back-in-black",
                       actualTempo: 90,
                       startTime: 0, endTime: 15,
                       minTempo: 60, maxTempo: 120,
                       variance: 2)

        self.testSetFinish()
    }
    
    private func validateHomeSet1 () {
        self.testSetSetupForSetName("homeSet1")
        
        self.testAudio("Home/AG-Blackbird-1.mp3",
                       label: "ag-blackbird1",
                       actualTempo: 94,
                       minTempo: 60, maxTempo: 120,
                       variance: 3)

        self.testAudio("Home/AG-Blackbird-2.mp3",
                       label: "ag-blackbird2",
                       actualTempo: 95,
                       minTempo: 60, maxTempo: 120,
                       variance: 3)
        
        self.testAudio("Home/AG-Sunset Road-116-1.mp3",
                       label: "ag-sunsetroad1",
                       actualTempo: 116,
                       minTempo: 80, maxTempo: 160,
                       variance: 2)
        
        self.testAudio("Home/AG-Sunset Road-116-2.mp3",
                       label: "ag-sunsetroad2",
                       actualTempo: 116,
                       minTempo: 80, maxTempo: 160,
                       variance: 2)
        
        self.testAudio("Home/Possum-1.mp3",
                       label: "possum1",
                       actualTempo: 79,
                       minTempo: 60, maxTempo: 120,
                       variance: 2)
        
        self.testAudio("Home/Possum-2.mp3",
                       label: "possum2",
                       actualTempo: 81,
                       minTempo: 60, maxTempo: 120,
                       variance: 3)
        
        self.testAudio("Home/Hard Top-1.mp3",
                       label: "hard-top1",
                       actualTempo: 133,
                       minTempo: 80, maxTempo: 160,
                       variance: 2)
        
        self.testAudio("Home/Hard Top-2.mp3",
                       label: "hard-top2",
                       actualTempo: 146,
                       minTempo: 80, maxTempo: 160,
                       variance: 2)
        
        self.testAudio("Home/Definitely Delicate-1.mp3",
                       label: "delicate1",
                       actualTempo: 75,
                       minTempo: 60, maxTempo: 120,
                       variance: 3)
        
        self.testAudio("Home/Wildwood Flower-1.mp3",
                       label: "wildwood1",
                       actualTempo: 95,
                       minTempo: 80, maxTempo: 160,
                       variance: 3)
        
        self.testAudio("Home/Wildwood Flower-2.mp3",
                       label: "wildwood2",
                       actualTempo: 148,
                       minTempo: 80, maxTempo: 160,
                       variance: 3)
        
        self.testSetFinish()
    }
    
    private func validateThreesSet1 () {
        self.testSetSetupForSetName("threesSet1")

        self.testAudio("Threes/Norwegian Wood.mp3",
                       label: "norwegian-wood",
                       actualTempo: 180,
                       startTime: 0, endTime: 0,
                       minTempo: 100, maxTempo: 200,
                       variance: 3)

        self.testAudio("Threes/Drive In Drive Out.mp3",
                       label: "drive-in-drive-out",
                       actualTempo: 81,
                       startTime: 0, endTime: 0,
                       minTempo: 60, maxTempo: 120,
                       variance: 2)
        
        self.testAudio("Threes/Oh How We Danced.mp3",
                       label: "oh-how-we-danced",
                       actualTempo: 180,
                       startTime: 0, endTime: 20,
                       minTempo: 100, maxTempo: 200,
                       variance: 2)
        
        self.testAudio("Threes/Texas Flood.mp3",
                       label: "texas-flood",
                       actualTempo: 60,
                       startTime: 0, endTime: 20,
                       minTempo: 40, maxTempo: 120,
                       variance: 2)
        
        self.testAudio("Threes/Brahms Lullaby.mp3",
                       label: "brahms-lullaby",
                       actualTempo: 70,
                       startTime: 0, endTime: 15,
                       minTempo: 60, maxTempo: 120,
                       variance: 2)
        
        
        self.testSetFinish()
    }
    
    private func validateUtilitySet1 () {
        self.testSetSetupForSetName("utilitySet1")

        self.testAudio("Utility/metronome-88.mp3",
                       label: "metronome-88",
                       actualTempo: 88,
                       startTime: 0, endTime: 10,
                       minTempo: 40, maxTempo: 240,
                       variance: 1)

        self.testAudio("Utility/metronome-126.mp3",
                       label: "metronome-126",
                       actualTempo: 126,
                       startTime: 0, endTime: 15,
                       minTempo: 40, maxTempo: 240,
                       variance: 1)

        self.testAudio("Utility/1sTones.wav",
                       label: "1s-tones",
                       actualTempo: 60,
                       startTime: 0, endTime: 10,
                       minTempo: 40, maxTempo: 240,
                       variance: 1)

        self.testSetFinish()
    }
}