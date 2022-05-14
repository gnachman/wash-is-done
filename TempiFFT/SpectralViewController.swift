//
//  SpectralViewController.swift
//  TempiHarness
//
//  Created by John Scalo on 1/7/16.
//  Copyright © 2016 John Scalo. All rights reserved.
//

import UIKit
import AVFoundation

class Bucket {
    private let size: Int
    private var samples: [Float] = []
    private let queue: DispatchQueue

    init(_ size: Int,
         queue: DispatchQueue) {
        self.size = size
        self.queue = queue
    }

    func add(_ newSamples: [Float],
             handler: @escaping ([Float]) -> ()) {
        samples.append(contentsOf: newSamples)
        while samples.count > size {
            let chunk = Array(samples[0..<size])
            samples = Array(samples[size..<samples.count])
            queue.async {
                handler(chunk)
            }
        }
    }
}


extension TempiFFT {
    var dominantBand: Int {
        var max = 0.0
        var maxIndex = -1
        for i in 0..<numberOfBands {
            let m = Double(magnitudeAtBand(i))
            if m > max {
                max = m
                maxIndex = i
            }
        }
        return maxIndex
    }
}

class Recorder {
    private let capacity: Int
    private var buffer: [Int] = []
    init(_ capacity: Int) {
        self.capacity = capacity
    }
    func append(_ value: Int) {
        buffer.append(value)
        if buffer.count > capacity {
            buffer.remove(at: 0)
        }
    }

    public let acceptableScore = 80

    public func matches(_ other: [Int]) -> (Bool, Int) {
        let score = levenshtein(other)
        var save = true
        if let current = UserDefaults.standard.object(forKey: "best") as? NSNumber {
            save = score < current.intValue
        }
        if save {
            print("save it")
            UserDefaults.standard.set(score, forKey: "best")
            UserDefaults.standard.set(buffer, forKey: "buffer")
        }
        return (score < acceptableScore, score)
    }

    public func difference(_ other: [Int]) -> Int {
        if other.count != buffer.count {
            return Int.max
        }
        var sum = 0
        for (x, y) in zip(buffer, other) {
            sum += abs(x-y)
        }
        print(sum)
        return sum
    }

    // Threshold is 80
    public func levenshtein(_ other: [Int]) -> Int {
        let sCount = buffer.count
        let oCount = other.count

        guard sCount != 0 else {
            return oCount
        }

        guard oCount != 0 else {
            return sCount
        }

        let line : [Int]  = Array(repeating: 0, count: oCount + 1)
        var mat : [[Int]] = Array(repeating: line, count: sCount + 1)

        for i in 0...sCount {
            mat[i][0] = i
        }

        for j in 0...oCount {
            mat[0][j] = j
        }

        for j in 1...oCount {
            for i in 1...sCount {
                if buffer[i - 1] == other[j - 1] {
                    mat[i][j] = mat[i - 1][j - 1]       // no operation
                } else {
                    let del = mat[i - 1][j] + 1         // deletion
                    let ins = mat[i][j - 1] + 1         // insertion
                    let sub = mat[i - 1][j - 1] + 1     // substitution
                    mat[i][j] = min(min(del, ins), sub)
                }
            }
        }

        return mat[sCount][oCount]
    }
}

class SpectralViewController: UIViewController {
    let bucket = Bucket(2048, queue: DispatchQueue.main)
    private let sampleRate: Float = 44100.0
    private let recorder = Recorder(SpectralViewController.pattern.count)
    @IBOutlet weak var spectralView: SpectralView!
    var player: AVAudioPlayer?
    let imageView = UIImageView(image: UIImage(named: "happy.jpg"))
    let label = UILabel(frame: CGRect.zero)
    var unpluggedCount = 0

    var audioInput: TempiAudioInput!

    // Recorded in real live, 10/2/19 — new washer
    static let pattern = [12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 17, 17, 17, 17, 16, 2,
                          0, 16, 16, 33, 33, 33, 13, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12,
                          9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 10, 11, 10, 10, 11, 10, 12, 12, 12,
                          12, 14, 33, 33, 7, 7, 7, 7, 7, 9, 9, 9, 9, 11, 10, 10, 10, 9, 10, 9, 9, 9,
                          9, 9, 9, 9, 9, 9, 9, 9, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12,
                          12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 17, 17, 17, 17,
                          17, 16, 16, 16, 16, 14, 14, 14, 14, 12, 12, 12, 12, 12, 12, 12, 12, 12,
                          12, 12, 12, 12, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17,
                          17, 17, 17, 17, 19, 19, 19, 17, 17, 17, 17, 17, 16, 16, 16, 16, 2, 1, 2,
                          1, 2, 16, 16, 16, 16, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17,
                          17, 17, 17, 17, 17]
    // Recorded in real life, 9/17/19 — old washer
//    static let pattern = [12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 17, 17, 17, 17, 17,
//                          16, 16, 16, 16, 33, 33, 33, 33, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12,
//                          12, 12, 12, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 11, 11, 11, 11, 11, 11,
//                          12, 12, 12, 33, 33, 33, 33, 7, 7, 7, 7, 7, 9, 9, 9, 9, 11, 11, 11, 11, 11,
//                          9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12,
//                          12, 12, 12, 12, 12, 12, 12, 12, 12, 3, 12, 12, 12, 12, 12, 12, 17, 17, 17,
//                          2, 6, 16, 16, 16, 16, 33, 33, 33, 33, 12, 12, 12, 12, 12, 12, 12, 12, 12,
//                          12, 12, 12, 12, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17,
//                          17, 17, 17, 17, 19, 19, 19, 19, 17, 17, 17, 17, 16, 16, 16, 16, 16, 33,
//                          33, 33, 33, 16, 16, 16, 16, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17,
//                          17, 17, 17, 17, 17, 17]

    // Captured from https://www.youtube.com/watch?v=clHpyRzb1PI
    /*
        [12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 17, 17, 17, 17, 16, 16, 16,
                          16, 14, 14, 14, 14, 14, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12,  9,  9,
                          9,  9,  9,  9,  9,  9,  9,  9,  9,  9,  9,  9, 11, 11, 11, 11, 11, 11, 12, 12,
                          14, 14, 14, 14, 14,  7,  7,  7,  7,  9,  9,  9,  9, 10, 11, 11, 11, 11,  9,  9,
                          9,  9,  9,  9,  9,  9,  9,  9,  9,  9,  9, 12, 12, 12, 12, 12, 12, 12, 12, 12,
                          12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 17, 17, 17,
                          17, 16, 16, 16, 36, 14, 14, 14, 14, 14, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12,
                          12, 12, 12, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17,
                          31, 19, 19, 19, 17, 17, 17, 17, 17, 16, 16, 16, 14, 14, 14, 14, 14, 14, 16, 16,
                          14, 16, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17]
     */

    private func patternFound() {
        playForever("washdone")
    }

    private func playForever(_ name: String) {
        if player == nil {
            let path = Bundle.main.path(forResource: name, ofType: "m4a")
            let url = NSURL.fileURL(withPath: path!)
            player = try! AVAudioPlayer(contentsOf: url)
            player!.numberOfLoops = -1
            player!.play()
            imageView.isHidden = false
        }
    }

    private func lowBattery(_ shouldPlay: Bool) {
        if shouldPlay {
            playForever("lowbattery")
        } else {

        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        self.tap(nil)
    }

    let c0 = Float(16.3125)
    let lowestOctave = 6
    let highestOctave = 10

    private func performAnalysis(_ samples: [Float]) {
        let fft = TempiFFT(withSize: samples.count, sampleRate: sampleRate)
        fft.windowType = TempiFFTWindowType.hanning
        fft.fftForward(samples)

        fft.calculateLogarithmicBands(minFrequency: c0 * Float(pow(2.0, Float(lowestOctave))),
                                      maxFrequency: c0 * Float(pow(2.0, Float(highestOctave))),
                                      bandsPerOctave: 12)
        recorder.append(fft.dominantBand)
        if let max = samples.max(), max < 0.001 {
            spectralView.note = ""
        } else {
            spectralView.note = name(fft.dominantBand + 12*4 + 9)
        }
        let (found, score) = recorder.matches(SpectralViewController.pattern)
        spectralView.addScore(score)
        spectralView.acceptableScore = recorder.acceptableScore
        if found {
            patternFound()
        }
    }

    func name(_ band: Int) -> String {
        let notes = ["c", "c", "d", "d", "e", "f", "f", "g", "g", "a", "a", "b"]
        let sharps = ["", "#", "", "#", "", "", "#", "", "#", "", "#", ""]
        let i = band % notes.count
        let note = notes[i]
        let sharp = sharps[i]
        let octave = band / 12
        return "\(note)\(octave)\(sharp)"
    }

    private func handleChunk(_ samples: [Float]) {
        let fft = TempiFFT(withSize: samples.count, sampleRate: sampleRate)
        fft.windowType = TempiFFTWindowType.hanning
        fft.fftForward(samples)

        // Interpoloate the FFT data so there's one band per pixel.
        let screenWidth = UIScreen.main.bounds.size.width * UIScreen.main.scale

        // NB: The UI in this demo app is geared towards a linear calculation. If you instead use calculateLogarithmicBands, the labels will not be placed correctly.
        fft.calculateLinearBands(minFrequency: 0, maxFrequency: fft.nyquistFrequency, numberOfBands: Int(screenWidth))

        performAnalysis(samples)

        self.spectralView.fft = fft
        self.spectralView.numberOfBands = 480
        self.spectralView.setNeedsDisplay()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        if let best = UserDefaults.standard.value(forKey: "best") as? NSNumber,
            let bestBuffer = UserDefaults.standard.value(forKey: "buffer") as? [NSNumber] {
            print("Best=\(best), buffer=\(bestBuffer)")
        }

        let audioInputCallback: TempiAudioInputCallback = { (timeStamp, numberOfFrames, samples) -> Void in
            self.gotSomeAudio(timeStamp: Double(timeStamp), numberOfFrames: Int(numberOfFrames), samples: samples)
        }
        
        audioInput = TempiAudioInput(audioInputCallback: audioInputCallback, sampleRate: 44100, numberOfChannels: 1)
        audioInput.startRecording()

        view.addSubview(imageView)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.isHidden = true
        view.addConstraint(NSLayoutConstraint(item: imageView,
                                                   attribute: .top,
                                                   relatedBy: .equal,
                                                   toItem: view,
                                                   attribute: .top,
                                                   multiplier: 1,
                                                   constant: 0))
        view.addConstraint(NSLayoutConstraint(item: imageView,
                                                   attribute: .bottom,
                                                   relatedBy: .equal,
                                                   toItem: view,
                                                   attribute: .bottom,
                                                   multiplier: 1,
                                                   constant: 0))
        view.addConstraint(NSLayoutConstraint(item: imageView,
                                                   attribute: .leading,
                                                   relatedBy: .equal,
                                                   toItem: view,
                                                   attribute: .leading,
                                                   multiplier: 1,
                                                   constant: 0))
        view.addConstraint(NSLayoutConstraint(item: imageView,
                                                   attribute: .trailing,
                                                   relatedBy: .equal,
                                                   toItem: view,
                                                   attribute: .trailing,
                                                   multiplier: 1,
                                                   constant: 0))
        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tap(_:))))

        view.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = UIColor.white
        view.addConstraint(NSLayoutConstraint(item: label,
                                              attribute: .top,
                                              relatedBy: .equal,
                                              toItem: view,
                                              attribute: .top,
                                              multiplier: 1,
                                              constant: 12))
        view.addConstraint(NSLayoutConstraint(item: label,
                                              attribute: .leading,
                                              relatedBy: .equal,
                                              toItem: view,
                                              attribute: .leading,
                                              multiplier: 1,
                                              constant: 12))

        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { (_) in
            switch UIDevice.current.batteryState {
            case .unplugged:
                self.unpluggedCount += 1
                print("unplugged count incremented to \(self.unpluggedCount)")
                if self.unpluggedCount > 5 {
                    self.lowBattery(true)
                }
            case .charging, .full, .unknown:
                self.unpluggedCount = 0
                print("plugged in or unknown battery state")
                self.lowBattery(false)
            @unknown default:
                preconditionFailure()
            }
        }
    }

    @objc(tap:)
    func tap(_ sender: Any?) {
        player?.stop()
        player = nil
        imageView.isHidden = true
    }

    func gotSomeAudio(timeStamp: Double, numberOfFrames: Int, samples: [Float]) {
        precondition(numberOfFrames == samples.count)
        bucket.add(samples, handler: { self.handleChunk($0) })
    }
    
    override func didReceiveMemoryWarning() {
        NSLog("*** Memory!")
        super.didReceiveMemoryWarning()
    }
}

