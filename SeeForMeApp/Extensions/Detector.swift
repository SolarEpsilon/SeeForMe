//
//  Detector.swift
//  SeeForMe
//
//  Created by Ronan M on 7/21/25.
//

import Vision
import AVFoundation
import UIKit
import CoreHaptics
import ARKit

extension CGRect {
    func distance(to other: CGRect) -> CGFloat {
        let dx = self.midX - other.midX
        let dy = self.midY - other.midY
        return sqrt(dx * dx + dy * dy)
    }
}

extension ViewController {
    
    struct TrackedObject {
        let identifier: String
        var boundingBox: CGRect
        var lastSeen: Date
        var lastAnnounced: Date
    }
    
    struct Candidate {
        let object: VNRecognizedObjectObservation
        let label: VNClassificationObservation
        let bounds: CGRect
        let area: CGFloat
    }
    
    func setupDetector() {
        let modelURL = Bundle.main.url(forResource: "YOLOv3TinyInt8LUT", withExtension: "mlmodelc")
    
        do {
            let visionModel = try VNCoreMLModel(for: MLModel(contentsOf: modelURL!))
            let recognitions = VNCoreMLRequest(model: visionModel, completionHandler: detectionDidComplete)
            self.requests = [recognitions]
        } catch let error {
            print(error)
        }
    }
    
    func detectionDidComplete(request: VNRequest, error: Error?) {
        DispatchQueue.main.async(execute: {
            if let results = request.results {
                self.extractDetections(results)
            }
        })
    }
    
    func playHapticFeedback(doubleBuzz: Bool = false) {
            guard let engine = hapticEngine else { return }

        var events: [CHHapticEvent] = []

            if doubleBuzz {
                // Two quick taps spaced 0.1 seconds apart
                let first = CHHapticEvent(eventType: .hapticTransient,
                                          parameters: [
                                            .init(parameterID: .hapticIntensity, value: 0.8),
                                            .init(parameterID: .hapticSharpness, value: 0.5)
                                          ],
                                          relativeTime: 0)
                let second = CHHapticEvent(eventType: .hapticTransient,
                                           parameters: [
                                            .init(parameterID: .hapticIntensity, value: 0.8),
                                            .init(parameterID: .hapticSharpness, value: 0.5)
                                           ],
                                           relativeTime: 0.1)
                events = [first, second]
            } else {
                // Single tap
                let event = CHHapticEvent(eventType: .hapticTransient,
                                          parameters: [
                                            .init(parameterID: .hapticIntensity, value: 0.8),
                                            .init(parameterID: .hapticSharpness, value: 0.5)
                                          ],
                                          relativeTime: 0)
                events = [event]
            }

            do {
                let pattern = try CHHapticPattern(events: events, parameters: []) // Create the pattern
                let player = try engine.makePlayer(with: pattern)
                try player.start(atTime: CHHapticTimeImmediate) // Play the pattern immediately
            } catch {
                print("Error playing haptic pattern: \(error.localizedDescription)")
            }
        }
    
    func extractDetections(_ results: [VNObservation]) {
        detectionLayer.sublayers = nil
        
        let movementThreshold: CGFloat = 0.05 // 5% of screen diagonal
        let announceCooldown: TimeInterval = 4.0 // seconds
        let now = Date()
        let screenDiagonal = sqrt(screenRect.width * screenRect.width + screenRect.height * screenRect.height)
        
        var candidates: [Candidate] = []
        
        DispatchQueue.main.async {
            self.view.subviews.forEach { subview in
                if subview.accessibilityTraits == .staticText {
                    subview.removeFromSuperview()
                }
            }
        }
        
        for observation in results where observation is VNRecognizedObjectObservation {
            guard let objectObservation = observation as? VNRecognizedObjectObservation else { continue }
            
            // Transformations
            let objectBounds = VNImageRectForNormalizedRect(objectObservation.boundingBox, Int(screenRect.size.width), Int(screenRect.size.height))
            let transformedBounds = CGRect(x: objectBounds.minX, y: screenRect.size.height - objectBounds.maxY, width: objectBounds.maxX - objectBounds.minX, height: objectBounds.maxY - objectBounds.minY)

            // Calculate distance
            let distanceText = estimateDistance(from: transformedBounds)
            
            // Extract label and confidence
            if let topLabelObservation = objectObservation.labels.first {
                let objectIdentifier = topLabelObservation.identifier
                let confidence = topLabelObservation.confidence
                let now = Date()
                
                let area = transformedBounds.width * transformedBounds.height
                
                // Draw bounding box
                let overlayView = createOverlay(for: objectIdentifier,
                                                 confidence: confidence,
                                                 distance: distanceText,
                                                 frame: transformedBounds)

                DispatchQueue.main.async {
                    self.view.addSubview(overlayView)
                }

                // Cooldown + movement logic
                let previous = trackedObjects[objectIdentifier]
                let moved = previous?.boundingBox.distance(to: transformedBounds) ?? .infinity > (screenDiagonal * movementThreshold)
                let timeSinceLastAnnounce = now.timeIntervalSince(previous?.lastAnnounced ?? .distantPast)
                let eligible = (moved || timeSinceLastAnnounce > announceCooldown)

                if eligible {
                    candidates.append(Candidate(object: objectObservation, label: topLabelObservation, bounds: transformedBounds, area: area))
                }

                // Update tracking info regardless
                trackedObjects[objectIdentifier] = TrackedObject(
                    identifier: objectIdentifier,
                    boundingBox: transformedBounds,
                    lastSeen: now,
                    lastAnnounced: previous?.lastAnnounced ?? .distantPast
                )
                
                // Create label layer
                let textLayer = CATextLayer()
                let minLabelWidth: CGFloat = 80
                let labelWidth = max(transformedBounds.width, minLabelWidth)
                textLayer.string = "\(objectIdentifier) (\(String(format: "%.0f", confidence * 100))%)\n\(distanceText)"
                textLayer.font = UIFont.systemFont(ofSize: 12)
                textLayer.fontSize = 12
                textLayer.alignmentMode = .center
                textLayer.foregroundColor = UIColor.white.cgColor
                textLayer.backgroundColor = UIColor.black.withAlphaComponent(0.6).cgColor
                textLayer.contentsScale = UIScreen.main.scale // Retina support
                textLayer.frame = CGRect(x: (transformedBounds.width - labelWidth) / 2,
                                         y: -36,
                                         width: labelWidth,
                                         height: 36)
                textLayer.cornerRadius = 4
                textLayer.masksToBounds = true
                
                if distanceText.contains("1") || distanceText.contains("2") {
                    textLayer.backgroundColor = UIColor.red.withAlphaComponent(0.6).cgColor
                }
            }
        }
        
        if let best = candidates.sorted(by: { $0.area > $1.area }).first {
            let id = best.label.identifier
            let distanceDescription = estimateDistance(from: best.bounds)
            
            let announcement = "Detected \(id) \(distanceDescription)."

            if !isSpeaking {
                let utterance = AVSpeechUtterance(string: announcement)
                utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
                utterance.rate = 0.5
                speechSynthesizer.speak(utterance)
                
                isSpeaking = true
                trackedObjects[id]?.lastAnnounced = now
                
                if id.lowercased().contains("person") || id.lowercased().contains("cat") {
                    playHapticFeedback(doubleBuzz: true)
                } else {
                    playHapticFeedback()
                }
            }
            
            trackedObjects[id]?.lastAnnounced = now
        }
    }
    
    func setupLayers() {
        detectionLayer = CALayer()
        detectionLayer.frame = CGRect(x: 0, y: 0, width: screenRect.size.width, height: screenRect.size.height)
        self.view.layer.addSublayer(detectionLayer)
    }
    
    func updateLayers() {
        detectionLayer?.frame = CGRect(x: 0, y: 0, width: screenRect.size.width, height: screenRect.size.height)
    }
    
    func drawBoundingBox(_ bounds: CGRect) -> CALayer {
        let boxLayer = CALayer()
        boxLayer.frame = bounds
        boxLayer.borderWidth = 3.0
        boxLayer.borderColor = CGColor.init(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
        boxLayer.cornerRadius = 4
        return boxLayer
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        latestBufferSize = CGSize(width: width, height: height)
        
        let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:]) // Create handler to perform request on the buffer

        do {
            try imageRequestHandler.perform(self.requests) // Schedules vision requests to be performed
        } catch {
            print(error)
        }
    }
}
