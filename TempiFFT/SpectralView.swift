//
//  SpectralView.swift
//  TempiHarness
//
//  Created by John Scalo on 1/20/16.
//  Copyright © 2016 John Scalo. All rights reserved.
//

import UIKit

class SpectralView: UIView {

    var fft: TempiFFT!
    var numberOfBands: Int? = nil
    var scores: [Int] = []
    var acceptableScore = 80
    let maxScores = 100
    var note: String = ""

    func addScore(_ score: Int) {
        scores.append(score)
        if scores.count > maxScores {
            scores.removeFirst()
        }
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        
        if fft == nil {
            return
        }
        
        let context = UIGraphicsGetCurrentContext()

        drawScores(context: context!)
        self.drawSpectrum(context: context!)
        drawNote(context: context!)

        // We're drawing static labels every time through our drawRect() which is a waste.
        // If this were more than a demo we'd take care to only draw them once.
        self.drawLabels(context: context!)
    }

    private func drawNote(context: CGContext) {
        let rect = CGRect(x: 0, y: 0, width: 32, height: 32)
        context.setFillColor(UIColor.black.cgColor)
        context.fill(rect)

        context.setStrokeColor(UIColor.white.cgColor)
        let attributedString = NSAttributedString(string: note, attributes: [.foregroundColor: UIColor.white, .font: UIFont.systemFont(ofSize: 32)])
        attributedString.draw(at: rect.origin)
    }

    private func drawScores(context: CGContext) {
        context.setFillColor(UIColor.black.cgColor)
        let height = bounds.height / 3.0
        let yOrigin = 0.0
        let maxScore = 160.0

        // Background
        context.fill(CGRect(x: 0,
                            y: yOrigin,
                            width: bounds.width,
                            height: height))

        // Threshold line
        let y = CGFloat(acceptableScore) * height / maxScore
        context.setFillColor(UIColor.blue.cgColor)
        context.fill(CGRect(x: 0,
                            y: y + yOrigin,
                            width: bounds.width,
                            height: 1))

        // Box for each score
        let stride = round(bounds.width / CGFloat(maxScores))
        var x = 0.0
        for score in scores {
            let y = CGFloat(score) * height / maxScore
            context.setFillColor(UIColor.white.cgColor)
            context.fill(CGRect(x: x,
                                y: y + yOrigin,
                                width: stride,
                                height: 5))
            x += stride
        }
    }

    private func drawSpectrum(context: CGContext) {
        let viewWidth = self.bounds.size.width
        let viewHeight = self.bounds.size.height
        let plotYStart: CGFloat = 48.0
        
        context.saveGState()
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: 0, y: -viewHeight)
        
        let colors = [UIColor.green.cgColor, UIColor.yellow.cgColor, UIColor.red.cgColor]
        let gradient = CGGradient(
            colorsSpace: nil, // generic color space
            colors: colors as CFArray,
            locations: [0.0, 0.3, 0.6])
        
        var x: CGFloat = 0.0
        
        let count = numberOfBands ?? fft.numberOfBands
        
        // Draw the spectrum.
        let maxDB: Float = 64.0
        let minDB: Float = -32.0
        let headroom = maxDB - minDB
        let colWidth = tempi_round_device_scale(d: viewWidth / CGFloat(count))
        
        for i in 0..<count {
            let magnitude = fft.magnitudeAtBand(i)
            
            // Incoming magnitudes are linear, making it impossible to see very low or very high values. Decibels to the rescue!
            var magnitudeDB = TempiFFT.toDB(magnitude)
            
            // Normalize the incoming magnitude so that -Inf = 0
            magnitudeDB = max(0, magnitudeDB + abs(minDB))
            
            let dbRatio = min(1.0, magnitudeDB / headroom)
            let magnitudeNorm = CGFloat(dbRatio) * viewHeight
            
            let colRect: CGRect = CGRect(x: x, y: plotYStart, width: colWidth, height: magnitudeNorm)
            
            let startPoint = CGPoint(x: viewWidth / 2, y: 0)
            let endPoint = CGPoint(x: viewWidth / 2, y: viewHeight)
            
            context.saveGState()
            context.clip(to: colRect)
            context.drawLinearGradient(gradient!, start: startPoint, end: endPoint, options: CGGradientDrawingOptions(rawValue: 0))
            context.restoreGState()
            
            x += colWidth
        }
        
        context.restoreGState()
    }
    
    private func drawLabels(context: CGContext) {
        let viewWidth = self.bounds.size.width
        let viewHeight = self.bounds.size.height
        
        context.saveGState()
        context.translateBy(x: 0, y: viewHeight);
        
        let pointSize: CGFloat = 15.0
        let font = UIFont.systemFont(ofSize: pointSize, weight: .regular)
        
        let freqLabelStr = "Frequency (kHz)"
        var attrStr = NSMutableAttributedString(string: freqLabelStr)
        attrStr.addAttribute(.font, value: font, range: NSMakeRange(0, freqLabelStr.count))
        attrStr.addAttribute(.foregroundColor, value: UIColor.yellow, range: NSMakeRange(0, freqLabelStr.count))
        
        var x: CGFloat = viewWidth / 2.0 - attrStr.size().width / 2.0
        attrStr.draw(at: CGPoint(x: x, y: -22))

        let range = 1...10
        let labelStrings: [String] = range.map { String($0) }
        let labelValues: [CGFloat] = range.map { CGFloat($0 * 1000) }
        let highestDisplayedFrequency: CGFloat
        if let numberOfBands = numberOfBands {
            highestDisplayedFrequency = CGFloat(fft.frequencyAtBand(numberOfBands))
        } else {
            highestDisplayedFrequency = CGFloat(fft.sampleRate) / 2.0
        }
        let samplesPerPixel: CGFloat = highestDisplayedFrequency / viewWidth
        for i in 0..<labelStrings.count {
            let str = labelStrings[i]
            let freq = labelValues[i]
            
            attrStr = NSMutableAttributedString(string: str)
            attrStr.addAttribute(.font, value: font, range: NSMakeRange(0, str.count))
            attrStr.addAttribute(.foregroundColor, value: UIColor.yellow, range: NSMakeRange(0, str.count))
            
            x = freq / samplesPerPixel - pointSize / 2.0
            attrStr.draw(at: CGPoint(x: x, y: -40))
        }
        
        context.restoreGState()
    }
}
