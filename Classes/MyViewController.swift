//
//  MyViewController.swift
//  iPhoneACFileConvertTest
//
//  Translated by OOPer in cooperation with shlab.jp, on 2016/1/10.
//
//
/*
        File: MyViewController.h
        File: MyViewController.m
    Abstract: The main view controller of this app.
     Version: 1.0.2

    Disclaimer: IMPORTANT:  This Apple software is supplied to you by Apple
    Inc. ("Apple") in consideration of your agreement to the following
    terms, and your use, installation, modification or redistribution of
    this Apple software constitutes acceptance of these terms.  If you do
    not agree with these terms, please do not use, install, modify or
    redistribute this Apple software.

    In consideration of your agreement to abide by the following terms, and
    subject to these terms, Apple grants you a personal, non-exclusive
    license, under Apple's copyrights in this original Apple software (the
    "Apple Software"), to use, reproduce, modify and redistribute the Apple
    Software, with or without modifications, in source and/or binary forms;
    provided that if you redistribute the Apple Software in its entirety and
    without modifications, you must retain this notice and the following
    text and disclaimers in all such redistributions of the Apple Software.
    Neither the name, trademarks, service marks or logos of Apple Inc. may
    be used to endorse or promote products derived from the Apple Software
    without specific prior written permission from Apple.  Except as
    expressly stated in this notice, no other rights or licenses, express or
    implied, are granted by Apple herein, including but not limited to any
    patent rights that may be infringed by your derivative works or by other
    works in which the Apple Software may be incorporated.

    The Apple Software is provided by Apple on an "AS IS" basis.  APPLE
    MAKES NO WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
    THE IMPLIED WARRANTIES OF NON-INFRINGEMENT, MERCHANTABILITY AND FITNESS
    FOR A PARTICULAR PURPOSE, REGARDING THE APPLE SOFTWARE OR ITS USE AND
    OPERATION ALONE OR IN COMBINATION WITH YOUR PRODUCTS.

    IN NO EVENT SHALL APPLE BE LIABLE FOR ANY SPECIAL, INDIRECT, INCIDENTAL
    OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
    SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
    INTERRUPTION) ARISING IN ANY WAY OUT OF THE USE, REPRODUCTION,
    MODIFICATION AND/OR DISTRIBUTION OF THE APPLE SOFTWARE, HOWEVER CAUSED
    AND WHETHER UNDER THEORY OF CONTRACT, TORT (INCLUDING NEGLIGENCE),
    STRICT LIABILITY OR OTHERWISE, EVEN IF APPLE HAS BEEN ADVISED OF THE
    POSSIBILITY OF SUCH DAMAGE.

    Copyright (C) 2014 Apple Inc. All Rights Reserved.

*/

// includes
import UIKit
import AVFoundation
import AudioToolbox

@objc(MyViewController)
class MyViewController: UIViewController, AVAudioPlayerDelegate {
    
    @IBOutlet private var fileInfo: UILabel!
    
    private var destinationFilePath: String!
    private var sourceURL: NSURL!
    private var destinationURL: NSURL!
    private var outputFormat: OSType = 0
    private var sampleRate: Float64 = 0.0
    
    @IBOutlet private(set) var instructionsView: UIView!
    @IBOutlet private(set) var webView: UIWebView!
    @IBOutlet private(set) var contentView: UIView!
    @IBOutlet private(set) var outputFormatSelector: UISegmentedControl!
    @IBOutlet private(set) var outputSampleRateSelector: UISegmentedControl!
    @IBOutlet private(set) var startButton: UIButton!
    @IBOutlet private(set) var activityIndicator: UIActivityIndicatorView!
    
    var flipButton: UIBarButtonItem!
    var doneButton: UIBarButtonItem!
    
    private let kTransitionDuration = 0.75
    
    //MARK:-
    
    private var isAACEncoderAvailable: Bool {
        var isAvailable = false
        
        // get an array of AudioClassDescriptions for all installed encoders for the given format
        // the specifier is the format that we are interested in - this is 'aac ' in our case
        var encoderSpecifier: UInt32 = kAudioFormatMPEG4AAC
        var size: UInt32 = 0
        
        var result = AudioFormatGetPropertyInfo(kAudioFormatProperty_Encoders, UInt32(sizeofValue(encoderSpecifier)), &encoderSpecifier, &size)
        guard result == 0 else {
            print("AudioFormatGetPropertyInfo kAudioFormatProperty_Encoders result \(result) \(FourCharCode(result).possibleFourCharString)")
            return false
        }
        
        let numEncoders = Int(size) / sizeof(AudioClassDescription)
        var encoderDescriptions: [AudioClassDescription] = Array(count: numEncoders, repeatedValue: AudioClassDescription())
        
        result = AudioFormatGetProperty(kAudioFormatProperty_Encoders, UInt32(sizeofValue(encoderSpecifier)), &encoderSpecifier, &size, &encoderDescriptions)
        guard result == 0 else {
            print("AudioFormatGetProperty kAudioFormatProperty_Encoders result \(result) \(FourCharCode(result).possibleFourCharString)")
            return false
        }
        
        print("Number of AAC encoders available: \(numEncoders)")
        
        // with iOS 7.0 AAC software encode is always available
        // older devices like the iPhone 4s also have a slower/less flexible hardware encoded for supporting AAC encode on older systems
        // newer devices may not have a hardware AAC encoder at all but a faster more flexible software AAC encoder
        // as long as one of these encoders is present we can convert to AAC
        // if both are available you may choose to which one to prefer via the AudioConverterNewSpecific() API
        for i in 0..<numEncoders {
            if encoderDescriptions[i].mSubType == kAudioFormatMPEG4AAC && encoderDescriptions[i].mManufacturer == kAppleHardwareAudioCodecManufacturer {
                print("Hardware encoder available")
                isAvailable = true
            }
            if encoderDescriptions[i].mSubType == kAudioFormatMPEG4AAC && encoderDescriptions[i].mManufacturer == kAppleSoftwareAudioCodecManufacturer {
                print("Software encoder available")
                isAvailable = true
            }
        }
        
        return isAvailable
    }
    
    private func updateFormatInfo(inLabel: UILabel, _ inFileURL: NSURL) {
        var fileID: AudioFileID = nil
        
        var result = AudioFileOpenURL(inFileURL, .ReadPermission, 0, &fileID)
        guard result == noErr else {
            print("AudioFileOpenURL failed! result \(result) \(FourCharCode(result).possibleFourCharString)")
            return
        }
        var asbd: CAStreamBasicDescription = CAStreamBasicDescription()
        var size = UInt32(strideofValue(asbd))
        result = AudioFileGetProperty(fileID, kAudioFilePropertyDataFormat, &size, &asbd)
        guard result == noErr else {
            print("AudioFileGetProperty kAudioFilePropertyDataFormat result \(result) \(FourCharCode(result).possibleFourCharString)")
            return
        }
        let lastPathComponent = inFileURL.lastPathComponent ?? ""
        let formatID = asbd.mFormatID.fourCharString
        
        inLabel.text = String(format: "\(lastPathComponent) \(formatID) %6.0f Hz (\(asbd.numberChannels) ch.)", asbd.mSampleRate)
        
        AudioFileClose(fileID)
    }
    
    //MARK:-
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // create the URLs we'll use for source and destination
        sourceURL = NSBundle.mainBundle().URLForResource("sourcePCM", withExtension: "aif")!
        
        let URLs = NSFileManager.defaultManager().URLsForDirectory(.DocumentDirectory, inDomains: .UserDomainMask)
        let documentsDirectoryURL = URLs[0]
        destinationURL = documentsDirectoryURL.URLByAppendingPathComponent("output.caf")
        print(destinationURL)
        destinationFilePath = destinationURL.path
        
        // load up the info text
        let infoSourceURL = NSBundle.mainBundle().URLForResource("info", withExtension: "html")!
        let infoText = try! String(contentsOfURL: infoSourceURL, encoding: NSUTF8StringEncoding)
        self.webView.loadHTMLString(infoText, baseURL: nil)
        self.webView.backgroundColor = UIColor.whiteColor()
        
        // set up start button
        let greenImage = UIImage(named: "green_button.png")!.resizableImageWithCapInsets(UIEdgeInsets(top: 12.0, left: 12.0, bottom: 12.0, right: 12.0))
        let redImage = UIImage(named: "red_button.png")!.resizableImageWithCapInsets(UIEdgeInsets(top: 12.0, left: 12.0, bottom: 12.0, right: 12.0))
        
        startButton.setBackgroundImage(greenImage, forState: .Normal)
        startButton.setBackgroundImage(redImage, forState: .Disabled)
        
        // add the subview
        self.view.addSubview(contentView)
        
        // add our custom flip buttons as the nav bars custom right view
        let infoButton = UIButton(type: .InfoLight)
        infoButton.addTarget(self, action: "flipAction:", forControlEvents: .TouchUpInside)
        
        flipButton = UIBarButtonItem(customView: infoButton)
        self.navigationItem.rightBarButtonItem = flipButton
        
        // create our done button as the nav bar's custom right view for the flipped view (used later)
        doneButton = UIBarButtonItem(barButtonSystemItem: .Done, target: self, action: "flipAction:")
        
        // default output format
        // sample rate of 0 indicates source file sample rate
        outputFormat = kAudioFormatAppleLossless
        sampleRate = 0
        
        // can we encode to AAC?
        if isAACEncoderAvailable {
            self.outputFormatSelector.setEnabled(true, forSegmentAtIndex: 0)
        } else {
            // even though not enabled in IB, this segment will still be enabled
            // if not specifically turned off here which we'll assume is a bug
            self.outputFormatSelector.setEnabled(false, forSegmentAtIndex: 0)
        }
        
        updateFormatInfo(fileInfo, sourceURL)
        
    }
    
    override func didReceiveMemoryWarning() {
        // Invoke super's implementation to do the Right Thing, but also release the input controller since we can do that
        // In practice this is unlikely to be used in this application, and it would be of little benefit,
        // but the principle is the important thing.
        
        super.didReceiveMemoryWarning()
    }
    
    //MARK:- Actions
    
    @objc func flipAction(_: AnyObject) {
        UIView.setAnimationDelegate(self)
        UIView.setAnimationDidStopSelector(nil)
        UIView.beginAnimations(nil, context: nil)
        UIView.setAnimationDuration(kTransitionDuration)
        
        UIView.setAnimationTransition(self.contentView.superview != nil ? .FlipFromLeft : .FlipFromRight,
            forView: self.view,
            cache: true)
        
        if self.instructionsView.superview != nil {
            self.instructionsView.removeFromSuperview()
            self.view.addSubview(contentView)
        } else {
            self.contentView.removeFromSuperview()
            self.view.addSubview(instructionsView)
        }
        
        UIView.commitAnimations()
        
        // adjust our done/info buttons accordingly
        if instructionsView.superview != nil {
            self.navigationItem.rightBarButtonItem = doneButton
        } else {
            self.navigationItem.rightBarButtonItem = flipButton
        }
    }
    
    @IBAction func convertButtonPressed(_: AnyObject) {
        do {
            try AVAudioSession.sharedInstance().setCategory(AVAudioSessionCategoryAudioProcessing)
        } catch let error as NSError {
            print("Setting the AVAudioSessionCategoryAudioProcessing Category failed! \(error.code)")
            
            return
        }
        
        self.startButton.setTitle("Converting...", forState: .Disabled)
        startButton.enabled = false
        
        self.activityIndicator.startAnimating()
        
        // run audio file code in a background thread
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
            self.convertAudio()
        }
    }
    
    @IBAction func segmentedControllerValueChanged(sender: UISegmentedControl) {
        switch sender.tag {
        case 0:
            switch sender.selectedSegmentIndex {
            case 0:
                outputFormat = kAudioFormatMPEG4AAC
                self.outputSampleRateSelector.setEnabled(true, forSegmentAtIndex: 0)
                self.outputSampleRateSelector.setEnabled(true, forSegmentAtIndex: 1)
                self.outputSampleRateSelector.setEnabled(true, forSegmentAtIndex: 2)
                self.outputSampleRateSelector.setEnabled(true, forSegmentAtIndex: 3)
            case 1:
                outputFormat = kAudioFormatAppleIMA4
                self.outputSampleRateSelector.setEnabled(true, forSegmentAtIndex: 0)
                self.outputSampleRateSelector.setEnabled(true, forSegmentAtIndex: 1)
                self.outputSampleRateSelector.setEnabled(true, forSegmentAtIndex: 2)
                self.outputSampleRateSelector.setEnabled(true, forSegmentAtIndex: 3)
            case 2:
                // iLBC sample rate is 8K
                outputFormat = kAudioFormatiLBC
                sampleRate = 8000.0
                self.outputSampleRateSelector.selectedSegmentIndex = 2
                self.outputSampleRateSelector.setEnabled(false, forSegmentAtIndex: 0)
                self.outputSampleRateSelector.setEnabled(false, forSegmentAtIndex: 1)
                self.outputSampleRateSelector.setEnabled(false, forSegmentAtIndex: 3)
            case 3:
                outputFormat = kAudioFormatAppleLossless
                self.outputSampleRateSelector.setEnabled(true, forSegmentAtIndex: 0)
                self.outputSampleRateSelector.setEnabled(true, forSegmentAtIndex: 1)
                self.outputSampleRateSelector.setEnabled(true, forSegmentAtIndex: 2)
                self.outputSampleRateSelector.setEnabled(true, forSegmentAtIndex: 3)
            default:
                break
            }
        case 1:
            switch sender.selectedSegmentIndex {
            case 0:
                sampleRate = 44100.0
            case 1:
                sampleRate = 22050.0
            case 2:
                sampleRate = 8000.0
            case 3:
                sampleRate = 0
            default:
                break
            }
        default:
            break
        }
    }
    
    //MARK:- AVAudioPlayer
    
    private func updateUI() {
        startButton.enabled = true
        updateFormatInfo(fileInfo, sourceURL)
    }
    
    func audioPlayerDecodeErrorDidOccur(player: AVAudioPlayer, error: NSError?) {
        NSLog("audioPlayerDecodeErrorDidOccur %@", error!.localizedDescription ?? "")
        self.audioPlayerDidFinishPlaying(player, successfully: false)
    }
    
    func audioPlayerBeginInterruption(player: AVAudioPlayer) {
        print("Session interrupted! --- audioPlayerBeginInterruption ---")
        
        // if the player was interrupted during playback we don't continue
        self.audioPlayerDidFinishPlaying(player, successfully: true)
    }
    
    func audioPlayerDidFinishPlaying(player: AVAudioPlayer, successfully flag: Bool) {
        if !flag {NSLog("Playback finished unsuccessfully!")}
        
        print("audioPlayerDidFinishPlaying")
        
        player.delegate = nil
        self.player = nil
        
        self.updateUI()
    }
    
    private var player: AVAudioPlayer? = nil
    private func playAudio() {
        print("playAudio")
        
        updateFormatInfo(fileInfo, destinationURL)
        self.startButton.setTitle("Playing Output File...", forState: .Disabled)
        
        // set category back to something that will allow us to play audio since AVAudioSessionCategoryAudioProcessing will not
        do {
            try AVAudioSession.sharedInstance().setCategory(AVAudioSessionCategoryPlayback)
        } catch let error as NSError {
            print("Setting the AVAudioSessionCategoryPlayback Category failed! \(error.code)")
            
            self.updateUI()
            
            return
        }
        
        // play the result
        do {
            player = try AVAudioPlayer(contentsOfURL: destinationURL)
            player?.delegate = self
            player?.play()
        } catch let error as NSError {
            print("AVAudioPlayer alloc failed! \(error.code)")
            
            self.updateUI()
            
            return
        }
        
    }
    
    //MARK:- ExtAudioFile
    
    func convertAudio() {
        autoreleasepool {
            
            let error = DoConvertFile(sourceURL, destinationURL, outputFormat, sampleRate)
            
            //self.activityIndicator.stopAnimating() //###
            
            if error != 0 {
                // delete output file if it exists since an error was returned during the conversion process
                if NSFileManager.defaultManager().fileExistsAtPath(destinationFilePath) {
                    do {
                        try NSFileManager.defaultManager().removeItemAtPath(destinationFilePath)
                    } catch {}
                }
                
                print("DoConvertFile failed! \(error)")
                dispatch_async(dispatch_get_main_queue()) {
                    self.activityIndicator.stopAnimating() //###
                    self.updateUI()
                }
            } else {
                dispatch_async(dispatch_get_main_queue()) {
                    self.activityIndicator.stopAnimating() //###
                    self.playAudio()
                }
            }
            
        }
    }
    
}