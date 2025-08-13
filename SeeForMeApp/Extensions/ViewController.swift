//
//  FrameHandler.swift
//  SeeForMe
//
//  Created by Ronan M on 7/18/25.
//

import UIKit
import SwiftUI
import AVFoundation
import Vision
import CoreHaptics
import ARKit
import SwiftUI


class ViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate, AVSpeechSynthesizerDelegate, ARSessionDelegate {
    private var permissionGranted = false // Flag for permission
    private let captureSession = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "sessionQueue")
    private var previewLayer = AVCaptureVideoPreviewLayer()
    private var settingsHostingController: UIHostingController<SettingsView>?
    var screenRect: CGRect! = nil // For view dimensions
    var hapticEngine: CHHapticEngine?
    let speechSynthesizer = AVSpeechSynthesizer()
    var isSpeaking = false // For controlling VoiceOver
    let arSession = ARSession()
    var arDepthAvailable: Bool = false
    var latestBufferSize: CGSize = .zero
    var latestARFrame: ARFrame?
    
    
    
    var trackedObjects: [String: TrackedObject] = [:]
    
    // Detector
    private var videoOutput = AVCaptureVideoDataOutput()
    var requests = [VNRequest]()
    var detectionLayer: CALayer! = nil
    
      
    override func viewDidLoad() {
        checkPermission()
        super.viewDidLoad()
        speechSynthesizer.delegate = self
        
        let config = ARWorldTrackingConfiguration()
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics = .sceneDepth
            arDepthAvailable = true
            arSession.run(config)
            arSession.delegate = self
        } else {
            arDepthAvailable = false
        }
        
        sessionQueue.async { [unowned self] in
            guard permissionGranted else { return }
            self.setupCaptureSession()
            
            self.setupLayers()
            self.setupDetector()
            
            self.setupHapticEngine()
            
            self.captureSession.startRunning()
        }
    }
    
    @objc func openSettings() {
        let settingsVC = UIHostingController(rootView: SettingsView())
        settingsVC.modalPresentationStyle = .formSheet
        present(settingsVC, animated: true)
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        let orientation = UIDevice.current.orientation
        switch orientation {
        // Home button on top
        case UIDeviceOrientation.portraitUpsideDown:
            self.previewLayer.connection?.videoRotationAngle = 270
        // Home button on right
        case UIDeviceOrientation.landscapeLeft:
            self.previewLayer.connection?.videoRotationAngle = 0
        // Home button on left
        case UIDeviceOrientation.landscapeRight:
            self.previewLayer.connection?.videoRotationAngle = 180
        // Home button at bottom
        case UIDeviceOrientation.portrait:
            self.previewLayer.connection?.videoRotationAngle = 90
        default:
            self.previewLayer.connection?.videoRotationAngle = 90
        }
        self.previewLayer.frame = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        
        // Detector
        updateLayers()
    }
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        latestARFrame = frame
    }
    
    func speechSynthesizer(_ syntheszer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        isSpeaking = false
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        isSpeaking = false
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        isSpeaking = true
    }
    
    func setupHapticEngine() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            print("This device does not support haptics.")
            return
        }
        
        do {
            hapticEngine = try CHHapticEngine()
            try hapticEngine?.start()
            print("Haptic engine started.")
        } catch {
            print("Error starting haptic engine: \(error.localizedDescription)")
        }
    }
    
    func checkPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
            // Permission has been granted before
            case .authorized:
                permissionGranted = true
                
            // Permission has not been requested yet
            case .notDetermined:
                requestPermission()
                    
            default:
                permissionGranted = false
            }
    }
    
    func requestPermission() {
        sessionQueue.suspend()
        AVCaptureDevice.requestAccess(for: .video) { [unowned self] granted in
            self.permissionGranted = granted
            self.sessionQueue.resume()
        }
    }
    
    func setupCaptureSession() {
        // Camera input
        guard let videoDevice = AVCaptureDevice.default(.builtInDualWideCamera,for: .video, position: .back) else { return }
        guard let videoDeviceInput = try? AVCaptureDeviceInput(device: videoDevice) else { return }
        guard captureSession.canAddInput(videoDeviceInput) else { return }
        captureSession.addInput(videoDeviceInput)
        
        // Performance Optimizations
        do {
            try videoDevice.lockForConfiguration()
            
            // Limit FPS to 15 for less CPU/GPU usage
            videoDevice.activeVideoMinFrameDuration = CMTimeMake(value: 1, timescale: 15)
            
            // Reduce resolution to 720p
            if captureSession.canSetSessionPreset(.hd1280x720) {
                captureSession.sessionPreset = .hd1280x720
            }
            
            videoDevice.unlockForConfiguration()
        } catch {
            print("Failed to configure device: \(error)")
        }
                         
        // Preview layer
        screenRect = UIScreen.main.bounds
        
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.frame = CGRect(x: 0, y: 0, width: screenRect.size.width, height: screenRect.size.height)
        previewLayer.videoGravity = AVLayerVideoGravity.resizeAspectFill // Fill screen
        previewLayer.connection?.videoRotationAngle = 90
        
        // Detector
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "sampleBufferQueue"))
        captureSession.addOutput(videoOutput)
        
        videoOutput.connection(with: .video)?.videoRotationAngle = 90
        
        // Updates to UI must be on main queue
        DispatchQueue.main.async { [weak self] in
            self!.view.layer.addSublayer(self!.previewLayer)
        }
    }
    
    func createOverlay(for label: String, confidence: Float, distance: String, frame: CGRect) -> UIView {
        let overlay = UIView(frame: frame)
        overlay.isUserInteractionEnabled = true
        overlay.accessibilityViewIsModal = false
        overlay.shouldGroupAccessibilityChildren = false
        
        overlay.layer.borderColor = UIColor.black.cgColor
        overlay.layer.borderWidth = 3
        overlay.layer.cornerRadius = 4
        overlay.backgroundColor = .clear

        // Accessibility
        overlay.isAccessibilityElement = true
        overlay.accessibilityLabel = "\(label), \(Int(confidence * 100))% confidence, \(distance)"
        overlay.accessibilityTraits = .staticText

        // Text label (visual)
        let minLabelWidth: CGFloat = 80
        let labelWidth = max(frame.width, minLabelWidth)

        let textLabel = UILabel(frame: CGRect(x: (frame.width - labelWidth) / 2,
                                              y: -36,
                                              width: labelWidth,
                                              height: 36))
        textLabel.numberOfLines = 2
        textLabel.font = .systemFont(ofSize: 12)
        textLabel.textAlignment = .center
        textLabel.textColor = .white
        textLabel.backgroundColor = (distance.contains("1") || distance.contains("2"))
            ? UIColor.red.withAlphaComponent(0.6)
            : UIColor.black.withAlphaComponent(0.6)
        textLabel.layer.cornerRadius = 4
        textLabel.layer.masksToBounds = true
        textLabel.text = "\(label) (\(Int(confidence * 100))%)\n\(distance)"

        overlay.addSubview(textLabel)
        return overlay
    }
    
    func estimateDistance(from boundingBox: CGRect) -> String {
        // Try LiDAR depth first
        if arDepthAvailable, let frame = latestARFrame, let depthMap = frame.sceneDepth?.depthMap {
            
            let previewLayer = self.previewLayer

            // Convert bounding box center from screen to camera space
            let screenCenter = CGPoint(x: boundingBox.midX, y: boundingBox.midY)
            let normalizedPoint = previewLayer.captureDevicePointConverted(fromLayerPoint: screenCenter)

            let depthWidth = CVPixelBufferGetWidth(depthMap)
            let depthHeight = CVPixelBufferGetHeight(depthMap)

            let pixelX = min(max(Int(normalizedPoint.x * CGFloat(depthWidth)), 0), depthWidth - 1)
            let pixelY = min(max(Int(normalizedPoint.y * CGFloat(depthHeight)), 0), depthHeight - 1)

            CVPixelBufferLockBaseAddress(depthMap, .readOnly)
            let floatBuffer = unsafeBitCast(CVPixelBufferGetBaseAddress(depthMap), to: UnsafeMutablePointer<Float32>.self)

            var depthSum: Float = 0
            var validCount = 0

            for dy in -1...1 {
                for dx in -1...1 {
                    let x = min(max(pixelX + dx, 0), depthWidth - 1)
                    let y = min(max(pixelY + dy, 0), depthHeight - 1)
                    let index = y * depthWidth + x
                    let depth = floatBuffer[index]
                    if depth.isFinite && depth > 0 {
                        depthSum += depth
                        validCount += 1
                    }
                }
            }

            CVPixelBufferUnlockBaseAddress(depthMap, .readOnly)

            if validCount > 0 {
                let averageDepth = depthSum / Float(validCount)
                let feet = averageDepth * 3.28084
                return "\(Int(feet.rounded())) feet away"
            }
        }
        
        // Fallback distance measure if no LiDAR (Assume that a full-screen object [100% area] = 0.5 feet away)
        let screenArea = screenRect.width * screenRect.height
        let boxArea = boundingBox.width * boundingBox.height
        let areaRatio = boxArea / screenArea
        
        let estimatedFeet = min(max(0.5 / areaRatio, 1.0), 10.0) // Clamp from 1 to 10 feet
        let roundedFeet = Int(estimatedFeet.rounded())
        
        return "\(roundedFeet) feet away"
    }
}

struct HostedViewController: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        return ViewController()
        }

        func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        }
}

struct DetectionViewControllerWrapper: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> ViewController {
        return ViewController() // Your main camera/ML view
    }

    func updateUIViewController(_ uiViewController: ViewController, context: Context) {}
}
