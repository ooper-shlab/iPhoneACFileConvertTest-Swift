//
//  iPhoneACFileConvertTest.swift
//  iPhoneACFileConvertTest
//
//  Translated by OOPer in cooperation with shlab.jp, on 2016/1/11.
//
//
/*
        File: iPhoneACFileConvertTest.h
        File: iPhoneACFileConvertTest.mm
    Abstract: The application delegate.
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

import UIKit

import AVFoundation

@UIApplicationMain
@objc(ACFileConvertAppDelegate)
class ACFileConvertAppDelegate: NSObject, UIApplicationDelegate {
    
    @IBOutlet var window: UIWindow?
    @IBOutlet var navigationController: UINavigationController!
    @IBOutlet var myViewController: MyViewController!
    
    @objc func handleInterruption(notification: NSNotification) {
        let theInterruptionType = notification.userInfo![AVAudioSessionInterruptionTypeKey] as! UInt
        
        NSLog("Session interrupted > --- %@ ---\n", theInterruptionType == AVAudioSessionInterruptionType.Began.rawValue ? "Begin Interruption" : "End Interruption")
        
        if theInterruptionType == AVAudioSessionInterruptionType.Began.rawValue {
            ThreadStateBeginInterruption()
        }
        
        if theInterruptionType == AVAudioSessionInterruptionType.Ended.rawValue {
            // make sure we are again the active session
            do {
                try AVAudioSession.sharedInstance().setActive(true)
                
            } catch let error as NSError {
                NSLog("AVAudioSession set active failed with error: %@", error)
            }
            
            ThreadStateEndInterruption()
        }
    }
    
    //MARK: -Audio Session Route Change Notification
    
    @objc func handleRouteChange(notification: NSNotification) {
        let reasonValue = notification.userInfo![AVAudioSessionRouteChangeReasonKey] as! UInt
        let routeDescription = notification.userInfo![AVAudioSessionRouteChangePreviousRouteKey] as! AVAudioSessionRouteDescription
        
        NSLog("Route change:")
        switch reasonValue {
        case AVAudioSessionRouteChangeReason.NewDeviceAvailable.rawValue:
            NSLog("     NewDeviceAvailable")
        case AVAudioSessionRouteChangeReason.OldDeviceUnavailable.rawValue:
            NSLog("     OldDeviceUnavailable")
        case AVAudioSessionRouteChangeReason.CategoryChange.rawValue:
            NSLog("     CategoryChange")
            NSLog(" New Category: %@", AVAudioSession.sharedInstance().category)
        case AVAudioSessionRouteChangeReason.Override.rawValue:
            NSLog("     Override")
        case AVAudioSessionRouteChangeReason.WakeFromSleep.rawValue:
            NSLog("     WakeFromSleep")
        case AVAudioSessionRouteChangeReason.NoSuitableRouteForCategory.rawValue:
            NSLog("     NoSuitableRouteForCategory")
        default:
            NSLog("     ReasonUnknown")
        }
        
        NSLog("Previous route:\n")
        NSLog("%@", routeDescription)
    }
    
    //MARK: -
    //MARK: Application lifecycle
    
    func applicationDidFinishLaunching(application: UIApplication) {
        
        // Override point for customization after application launch
        self.window?.rootViewController = navigationController
        window?.makeKeyAndVisible()
        
        ThreadStateInitalize()
        
        do {
            
            // Configure the audio session
            let sessionInstance = AVAudioSession.sharedInstance()
            
            // our default category -- we change this for conversion and playback appropriately
            do {
                try sessionInstance.setCategory(AVAudioSessionCategoryAudioProcessing)
            } catch let error as NSError {
                throw CAXException(operation: "couldn't set audio category", err: OSStatus(error.code))
            }
            
            // add interruption handler
            NSNotificationCenter.defaultCenter().addObserver(self,
                selector: #selector(ACFileConvertAppDelegate.handleInterruption(_:)),
                name: AVAudioSessionInterruptionNotification,
                object: sessionInstance)
            
            // we don't do anything special in the route change notification
            NSNotificationCenter.defaultCenter().addObserver(self,
                selector: #selector(ACFileConvertAppDelegate.handleRouteChange(_:)),
                name: AVAudioSessionRouteChangeNotification,
                object: sessionInstance)
            
            // the session must be active for offline conversion
            do {
                try sessionInstance.setActive(true)
            } catch let error as NSError {
                throw CAXException(operation: "couldn't set audio session active\n", err: OSStatus(error.code))
            }
            
        } catch let e as CAXException {
            print("Error: \(e.mOperation) (\(e.formatError()))\n", toStream: &stderr)
            print("You probably want to fix this before continuing!")
        } catch _ {}
        
    }
    
    deinit {
        
        NSNotificationCenter.defaultCenter().removeObserver(self,
            name: AVAudioSessionInterruptionNotification,
            object: AVAudioSession.sharedInstance())
        
        NSNotificationCenter.defaultCenter().removeObserver(self,
            name: AVAudioSessionRouteChangeNotification,
            object: AVAudioSession.sharedInstance())
        
    }
    
    func applicationDidEnterBackground(application: UIApplication) {
        /*
        Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        If your application supports background execution, called instead of applicationWillTerminate: when the user quits.
        */
        
        print("applicationDidEnterBackground")
    }
    
    
    func applicationWillEnterForeground(application: UIApplication) {
        /*
        Called as part of  transition from the background to the inactive state: here you can undo many of the changes made on entering the background.
        */
        
        print("applicationWillEnterForeground")
    }
    
    func applicationWillResignActive(application: UIApplication) {
        /*
        Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
        */
        
        print("applicationWillResignActive")
    }
    
    func applicationDidBecomeActive(application: UIApplication) {
        /*
        Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
        */
        
        print("applicationDidBecomeActive")
    }
    
}