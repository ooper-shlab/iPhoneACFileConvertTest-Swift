//
//  CAStreamBasicDescription.swift
//  iPhoneACFileConvertTest
//
//  Translated by OOPer in cooperation with shlab.jp, on 2015/1/31.
//
//
/*
File: CAStreamBasicDescription.h
File: CAStreamBasicDescription.cpp
Abstract:  CAStreamBasicDescription.h
Version: 1.0.3

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

import Foundation
import CoreAudio


//=============================================================================
//	CAStreamBasicDescription
//
//	This is a wrapper class for the AudioStreamBasicDescription struct.
//	It adds a number of convenience routines, but otherwise adds nothing
//	to the footprint of the original struct.
//=============================================================================
typealias CAStreamBasicDescription = AudioStreamBasicDescription
extension AudioStreamBasicDescription {
    
    enum CommonPCMFormat: Int {
        case other = 0
        case float32 = 1
        case int16 = 2
        case fixed824 = 3
    }
    
    //	Construction/Destruction
    
    init(desc: AudioStreamBasicDescription) {
        self = desc
    }
    
    init?(sampleRate inSampleRate: Double, numChannels inNumChannels: UInt32, pcmf: CommonPCMFormat, isInterleaved inIsInterleaved: Bool) {
        self.init()
        var wordsize: UInt32
        
        mSampleRate = inSampleRate
        mFormatID = AudioFormatID(kAudioFormatLinearPCM)
        mFormatFlags = AudioFormatFlags(kAudioFormatFlagsNativeEndian | kAudioFormatFlagIsPacked)
        mFramesPerPacket = 1
        mChannelsPerFrame = inNumChannels
        mBytesPerFrame = 0
        mBytesPerPacket = 0
        mReserved = 0
        
        switch pcmf {
        case .float32:
            wordsize = 4
            mFormatFlags |= AudioFormatFlags(kAudioFormatFlagIsFloat)
        case .int16:
            wordsize = 2
            mFormatFlags |= AudioFormatFlags(kAudioFormatFlagIsSignedInteger)
        case .fixed824:
            wordsize = 4
            mFormatFlags |= AudioFormatFlags(kAudioFormatFlagIsSignedInteger | (24 << kLinearPCMFormatFlagsSampleFractionShift))
        default:
            return nil
        }
        mBitsPerChannel = wordsize * 8
        if inIsInterleaved {
            mBytesPerFrame = wordsize * inNumChannels
            mBytesPerPacket = mBytesPerFrame
        } else {
            mFormatFlags |= AudioFormatFlags(kAudioFormatFlagIsNonInterleaved)
            mBytesPerFrame = wordsize
            mBytesPerPacket = mBytesPerFrame
        }
    }
    
    // _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
    //
    // interrogation
    
    var isPCM: Bool {
        return mFormatID == kAudioFormatLinearPCM
    }
    
    var packednessIsSignificant: Bool {
        assert(isPCM, "PackednessIsSignificant only applies for PCM");
        return (sampleWordSize << 3) != mBitsPerChannel;
    }
    
    var alignmentIsSignificant: Bool {
        return packednessIsSignificant || (mBitsPerChannel & 7) != 0;
    }
    
    var isInterleaved: Bool {
        return !isPCM || (mFormatFlags & kAudioFormatFlagIsNonInterleaved) == 0
    }
    
    var numberInterleavedChannels: UInt32 {
        return isInterleaved ? mChannelsPerFrame : 1
    }
    
    var numberChannels: UInt32 {
        return mChannelsPerFrame
    }
    
    var sampleWordSize: UInt32 {
        return (mBytesPerFrame > 0 && numberInterleavedChannels != 0) ? mBytesPerFrame / numberInterleavedChannels :  0;
    }
    
    // _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
    //
    //	other
    
    func print() {
        self.print(&stdout)
    }
    
    func print<T: TextOutputStream>(_ output: inout T) {
        self.printFormat(&output, "", "AudioStreamBasicDescription:")
    }
    
    func printFormat<T: TextOutputStream>(_ output: inout T, _ indent: String, _ name: String) {
        Swift.print("\(indent)\(name) \(description)", to: &output)
    }

    func printFormat2<T: TextOutputStream>(_ output: inout T, _ indent: String, _ name: String) { // no trailing newline
        Swift.print("\(indent)\(name) \(description)", terminator: "", to: &output)
    }
    
    static func print(_ inDesc: AudioStreamBasicDescription) {
        let desc = CAStreamBasicDescription(desc: inDesc)
        desc.print()
    }
    
    public var description: String {
        return asString
    }
    
    var asString: String {
        var buf: String = ""
        let formatID = mFormatID.fourCharString
        buf += String(format: "%2d ch, %6.0f Hz, '%@' (0x%08X) ", Int32(numberChannels), mSampleRate, formatID, Int32(mFormatFlags))
        if mFormatID == kAudioFormatLinearPCM {
            let isInt = (mFormatFlags & kLinearPCMFormatFlagIsFloat) == 0
            let wordSize = sampleWordSize
            var endian = ""
            if wordSize > 1 {
                endian = (mFormatFlags & kLinearPCMFormatFlagIsBigEndian) != 0 ? " big-endian" : " little-endian"
            }
            var sign = ""
            if isInt {
                sign = (mFormatFlags & kLinearPCMFormatFlagIsSignedInteger) != 0 ? " signed" : " unsigned"
            }
            let floatInt = isInt ? "integer" : "float"
            var packed = ""
            if wordSize > 0 && packednessIsSignificant {
                if mFormatFlags & kLinearPCMFormatFlagIsPacked != 0 {
                    packed = "packed in \(wordSize) bytes"
                } else {
                    packed = "unpacked in \(wordSize) bytes"
                }
            }
            var align = ""
            if wordSize > 0 && alignmentIsSignificant {
                align = (mFormatFlags & kLinearPCMFormatFlagIsAlignedHigh) != 0 ? " high-aligned" : " low-aligned"
            }
            let deinter = (mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0 ? ", deinterleaved" : ""
            let commaSpace = !packed.isEmpty || !align.isEmpty ? ", " : ""
            let bitdepth: String
            
//            if CA_PREFER_FIXED_POINT != 0 {
                let fracbits = (mFormatFlags & kLinearPCMFormatFlagsSampleFractionMask) >> kLinearPCMFormatFlagsSampleFractionShift
                if fracbits > 0 {
                    bitdepth = "\(mBitsPerChannel - fracbits).\(fracbits)"
                } else {
                    bitdepth = String(mBitsPerChannel)
                }
//            } else {
//                bitdepth = String(mBitsPerChannel)
//            }
            
            buf += "\(bitdepth)-bit\(endian)\(sign) \(floatInt)\(commaSpace)\(packed)\(align)\(deinter)"
        } else if mFormatID == kAudioFormatAppleLossless {
            var sourceBits = 0
            switch mFormatFlags {
            case kAppleLosslessFormatFlag_16BitSourceData:
                sourceBits = 16
            case kAppleLosslessFormatFlag_20BitSourceData:
                sourceBits = 20
            case kAppleLosslessFormatFlag_24BitSourceData:
                sourceBits = 24
            case kAppleLosslessFormatFlag_32BitSourceData:
                sourceBits = 32
            default:
                break
            }
            if sourceBits != 0 {
                buf +=  "from \(sourceBits)-bit source, "
            } else {
                buf += "from UNKNOWN source bit depth, "
            }
            buf += "\(mFramesPerPacket) frames/packet"
        } else {
            buf += "\(mBitsPerChannel) bits/channel, \(mBytesPerPacket) bytes/packet, \(mFramesPerPacket) frames/packet, \(mBytesPerFrame) bytes/frame"
        }
        return buf
    }
}
