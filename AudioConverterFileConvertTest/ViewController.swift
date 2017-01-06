//
//  ViewController.swift
//  AudioConverterFileConvertTest
//
//  Translated by OOPer in cooperation with shlab.jp, on 2017/1/3.
//
//
/*
    Copyright (C) 2016 Apple Inc. All Rights Reserved.
    See LICENSE.txt for this sample’s licensing information

    Abstract:
    The main view controller of this app.
 */

import UIKit
import AVFoundation
import AudioToolbox

extension OSStatus {
    var fourCharString: String {
        return UInt32(bitPattern: self).fourCharString
    }
}

@objc(ViewController)
class ViewController: UIViewController, AudioFileConvertOperationDelegate, AVAudioPlayerDelegate {
    
    // MARK: Properties
    
    @IBOutlet private weak var sourceAudioFile: UILabel!
    
    @IBOutlet private weak var sourceFormatInfo: UILabel!
    
    @IBOutlet private weak var outputFormatSelector: UISegmentedControl!
    
    @IBOutlet private weak var outputSampleRateSelector: UISegmentedControl!
    
    @IBOutlet private weak var destinationAudioFile: UILabel!
    
    @IBOutlet private weak var destinationFormatInfo: UILabel!
    
    @IBOutlet private weak var convertAndPlayButton: UIButton!
    
    @IBOutlet private weak var stopAudioButton: UIButton!
    
    private let sourceURL: URL = Bundle.main.url(forResource: "sourcePCM", withExtension: "aif")!
    
    private var destinationURL: URL!
    
    private var outputFormat: AudioFormatID = kAudioFormatMPEG4AAC {
        didSet {
            didSetOutputFormat(oldValue)
        }
    }
    
    private var sampleRate: Float64 = 0.0
    
    private var operation: AudioFileConvertOperation?
    
    private var player: AVAudioPlayer?
    
    // MARK: View Life Cycle.
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Create the URLs to be used for the source.
        
        // Set the default values.
        self.outputFormat = kAudioFormatMPEG4AAC
        self.sampleRate = 0
        
        // Update fileInfo label.
        self.updateSourceFileInfo()
        
        // Cleanup any stray files from previous runs.
        self.removeDestinationFileIfNeeded()
        
        // Add Notification observer for audio interuptions while playing back audio.
        NotificationCenter.default.addObserver(self, selector: #selector(handleAudioSessionInterruptionNotification), name: .AVAudioSessionInterruption, object: AVAudioSession.sharedInstance())
        
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self, name: .AVAudioSessionInterruption, object: AVAudioSession.sharedInstance())
    }
    
    // MARK: Target-Action
    
    @IBAction func outputFormatSelectorValueChanged(_ sender: UISegmentedControl) {
        switch sender.selectedSegmentIndex {
        case 0:
            self.outputFormat = kAudioFormatMPEG4AAC
            self.outputSampleRateSelector.setEnabled(true, forSegmentAt: 0)
            self.outputSampleRateSelector.setEnabled(true, forSegmentAt: 1)
            self.outputSampleRateSelector.setEnabled(true, forSegmentAt: 2)
            self.outputSampleRateSelector.setEnabled(true, forSegmentAt: 3)
        case 1:
            self.outputFormat = kAudioFormatAppleIMA4
            self.outputSampleRateSelector.setEnabled(true, forSegmentAt: 0)
            self.outputSampleRateSelector.setEnabled(true, forSegmentAt: 1)
            self.outputSampleRateSelector.setEnabled(true, forSegmentAt: 2)
            self.outputSampleRateSelector.setEnabled(true, forSegmentAt: 3)
        case 2:
            self.outputFormat = kAudioFormatiLBC
            self.sampleRate = 8000.0
            self.outputSampleRateSelector.selectedSegmentIndex = 2
            self.outputSampleRateSelector.setEnabled(false, forSegmentAt: 0)
            self.outputSampleRateSelector.setEnabled(false, forSegmentAt: 1)
            self.outputSampleRateSelector.setEnabled(false, forSegmentAt: 3)
        case 3:
            self.outputFormat = kAudioFormatAppleLossless
            self.outputSampleRateSelector.setEnabled(true, forSegmentAt: 0)
            self.outputSampleRateSelector.setEnabled(true, forSegmentAt: 1)
            self.outputSampleRateSelector.setEnabled(true, forSegmentAt: 2)
            self.outputSampleRateSelector.setEnabled(true, forSegmentAt: 3)
        case 4:
            self.outputFormat = kAudioFormatLinearPCM
            self.sampleRate = 44100.0
            self.outputSampleRateSelector.selectedSegmentIndex = 0
            self.outputSampleRateSelector.setEnabled(true, forSegmentAt: 1)
            self.outputSampleRateSelector.setEnabled(true, forSegmentAt: 2)
            self.outputSampleRateSelector.setEnabled(false, forSegmentAt: 3)
        default:
            return
        }
        
        self.removeDestinationFileIfNeeded()
    }
    
    @IBAction func outputSampleRateSelectorValueChanged(_ sender: UISegmentedControl) {
        switch sender.selectedSegmentIndex {
        case 0:
            self.sampleRate = 44100.0
        case 1:
            self.sampleRate = 22050.0
        case 2:
            self.sampleRate = 8000.0
        case 3:
            self.sampleRate = 0
        default:
            return
        }
        
        self.removeDestinationFileIfNeeded()
    }
    
    @IBAction func userDidPressConvertAndPlayButton(_ sender: UIButton) {
        self.convertAndPlayButton.setTitle("Converting...", for: .disabled)
        sender.isEnabled = false
        
        self.operation = AudioFileConvertOperation(sourceURL: self.sourceURL, destinationURL: self.destinationURL, sampleRate: self.sampleRate, outputFormat: self.outputFormat)
        
        self.operation!.delegate = self
        
        DispatchQueue.global(qos: .userInteractive).async {//###`weakSelf` is not needed...
            self.operation?.start()
        }
    }
    
    @IBAction func userDidPressStopPlayingButton(_ sender: UIButton) {
        if let player = self.player {
            player.stop()
            self.audioPlayerDidFinishPlaying(player, successfully: true)
        }
    }
    
    private func didSetOutputFormat(_ oldOutputFormat: AudioFormatID) {
        
        // After we set the output format we updated the URL for the output file be save to on disk.
        let formatString = outputFormat.fourCharString.uppercased()
        
        let urls = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let documentsDirectoryURL = urls[0]
        let destinationFileURL = documentsDirectoryURL.appendingPathComponent("Output\(formatString).caf")
        
        self.destinationURL = destinationFileURL
        self.updateDestinationFileInfo()
    }
    
    // MARK: UI Update Method.
    
    private func updateSourceFileInfo() {
        self.sourceAudioFile.text = self.sourceURL.lastPathComponent
        
        self.sourceFormatInfo.text = self.fileInfo(for: self.sourceURL, withBitsPerChannel: true)
    }
    
    private func updateDestinationFileInfo() {
        self.destinationAudioFile.text = self.destinationURL.lastPathComponent
        
        self.destinationFormatInfo.text = self.fileInfo(for: self.destinationURL, withBitsPerChannel: (self.outputFormat == kAudioFormatLinearPCM))
    }
    
    private func fileInfo(for url: URL, withBitsPerChannel bitsPerChannel: Bool) -> String {
        var _fileID: AudioFileID?
        var fileInfo = " "
        
        guard FileManager.default.fileExists(atPath: url.path) else {
            return fileInfo
        }
        var error = AudioFileOpenURL(url as CFURL, .readPermission, 0, &_fileID)
        
        guard error == noErr, let fileID = _fileID else {
            print("AudioFileOpenURL failed! result \(error) \(error.fourCharString)")
            return fileInfo
        }
        defer {AudioFileClose(fileID)}
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout.stride(ofValue: asbd))
        
        error = AudioFileGetProperty(fileID, kAudioFilePropertyDataFormat, &size, &asbd)
        guard error == noErr  else {
            print("AudioFileGetProperty kAudioFilePropertyDataFormat result \(error) \(error.fourCharString)")
            return fileInfo
        }
        let formatID = asbd.mFormatID.fourCharString
        
        fileInfo = String(format: "%@ %6.0f Hz (\(asbd.mChannelsPerFrame) ch.)", formatID, asbd.mSampleRate)
        
        if bitsPerChannel {
            fileInfo += " \(asbd.mBitsPerChannel) bits/ch."
        }
        
        return fileInfo
    }
    
    private func removeDestinationFileIfNeeded() {
        let fileManager = FileManager.default
        
        if fileManager.fileExists(atPath: self.destinationURL.path) {
            _ = try? fileManager.removeItem(at: self.destinationURL)
            
            self.updateDestinationFileInfo()
        }
    }
    
    // MARK: AudioFileConvertOperationDelegate Protocol Methods.
    
    func audioFileConvertOperation(_ audioFileConvertOperation: AudioFileConvertOperation, didCompleteWith destinationURL: URL) {
        
        DispatchQueue.main.async {//###`weakSelf` is not needed...
            self.updateDestinationFileInfo()
            
            self.operation = nil
            self.convertAndPlayButton.setTitle("Playing Audio...", for: .disabled)
            self.stopAudioButton.isHidden = false
            
            do {
                self.player = try AVAudioPlayer(contentsOf: destinationURL)
                self.player!.delegate = self
                
                self.player!.play()
            } catch let error {
                let alertController = UIAlertController(title: "Error Occured", message: error.localizedDescription, preferredStyle: .alert)
                alertController.addAction(UIAlertAction(title: "Dismiss", style: .cancel, handler: nil))
                
                self.present(alertController, animated: true, completion: nil)
            }
        }
    }
    
    func audioFileConvertOperation(_ audioFileConvertOperation: AudioFileConvertOperation, didEncounterError error: Error) {
        
        DispatchQueue.main.async {//###`weakSelf` is not needed...
            self.operation = nil
            
            let alertController = UIAlertController(title: "Error Occured", message: error.localizedDescription, preferredStyle: .alert)
            alertController.addAction(UIAlertAction(title: "Dismiss", style: .cancel, handler: nil))
            
            self.present(alertController, animated: true, completion: nil)
            
            self.convertAndPlayButton.setTitle("Convert & Play File", for: .normal)
            self.convertAndPlayButton.isEnabled = true
        }
    }
    
    // MARK: AVAudioPlayerDelegate Protocol Methods.
    
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        let alertController = UIAlertController(title: "Playback Error", message: error?.localizedDescription ?? "", preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: "Dismiss", style: .cancel, handler: nil))
        
        self.present(alertController, animated: true, completion: nil)
        
        self.audioPlayerDidFinishPlaying(player, successfully: false)
    }
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        self.convertAndPlayButton.setTitle("Convert & Play File", for: .normal)
        self.convertAndPlayButton.isEnabled = true
        self.stopAudioButton.isHidden = true
        
        self.player = nil
        
        self.removeDestinationFileIfNeeded()
    }
    
    // MARK: Notification Handler Methods.
    
    @objc private func handleAudioSessionInterruptionNotification(_ notification: Notification) {
        
        // For the purposes of this sample we only stop playback if needed and reset the UI back to being ready to convert again.
        if let player = self.player {
            player.stop()
            self.audioPlayerDidFinishPlaying(player, successfully: true)
        }
        
    }
    
}
