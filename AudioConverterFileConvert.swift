//
//  AudioConverterFileConvert.swift
//  iPhoneACFileConvertTest
//
//  Translated by OOPer in cooperation with shlab.jp, on 2015/7/30.
//
//
/*
        File: AudioConverterFileConvert.cpp
    Abstract: Demonstrates converting audio using AudioConverterFillComplexBuffer.
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

// standard includes
import AudioToolbox

/*

For more information on the importance of interruption handling and Audio Session setup when performing offline
encoding please see the Audio Session Programming Guide.

Offline format conversion requires interruption handling. Specifically, you must handle interruptions at the audio data buffer level.

By way of background, you can use a hardware assisted-codec—on certain devices—to encode linear PCM audio to AAC format.
The codec is available on the iPhone 3GS and on the iPod touch (2nd generation), but not on older models. You use the codec as part
of an Audio Converter object (of type AudioConverterRef).
For information on these opaque types, refer to Audio Converter Services Reference and Extended Audio File Services Reference.

To handle an interruption during hardware-assisted encoding, take two things into account:

1. The codec may or may not be able to resume encoding after the interruption ends.
2. The codec may be unavailable, probably due to an interruption.

Note: iOS 7 provides for software AAC encode, devices with hardware encoder will show as having two encoders, devices such as the iPhone 5s only has
a software encoder that is much faster and more flexible than the older hardware encoders.

Encoding takes place as you repeatedly call the AudioConverterFillComplexBuffer function supplying new buffers of input audio data via the input data procedure
producing buffers of audio encoded in the output format.
To handle an interruption, you respond to the function’s result code, as described here:

• kAudioConverterErr_HardwareInUse — This result code indicates that the underlying hardware codec has become unavailable, probably due to an interruption.
In this case, your application must stop calling AudioConverterFillComplexBuffer.  If you can resume conversion, wait for an interruption-ended call from
the audio session. In your interruption-end handler, reactivate the session and then resume converting the audio data.

To check if the AAC codec can resume, obtain the value of the associated converter’s kAudioConverterPropertyCanResumeFromInterruption property.
The value is 1 (can resume) or 0 (cannot resume) or the property itself may not be supported (implies software codec use where we can resume).
You can obtain this value any time after instantiating the converter—immediately after instantiation, upon interruption, or after interruption ends.

If the converter cannot resume, then on interruption you must abandon the conversion. After the interruption ends, or after the user relaunches your application
and indicates they want to resume conversion, re-instantiate the extended audio file object and perform the conversion again.

*/

//MARK:- Thread State
/* Since we perform conversion in a background thread, we must ensure that we handle interruptions appropriately.
In this sample we're using a mutex protected variable tracking thread states. The background conversion threads state transistions from Done to Running
to Done unless we've been interrupted in which case we are Paused blocking the conversion thread and preventing further calls
to AudioConverterFillComplexBuffer (since it would fail if we were using the hardware codec).
Once the interruption has ended, we unblock the background thread as the state transitions to Running once again.
Any errors returned from AudioConverterFillComplexBuffer must be handled appropriately. Additionally, if the Audio Converter cannot
resume conversion after an interruption, you should not call AudioConverterFillComplexBuffer again.
*/

private var sStateLock: pthread_mutex_t = pthread_mutex_t()
private var sStateChanged: pthread_cond_t = pthread_cond_t()      // signals when interruption thread unblocks conversion thread
enum ThreadStates {
    case Running
    case Paused
    case Done
}
var sState: ThreadStates = .Running

// initialize the thread state
func ThreadStateInitalize() {
    
    assert(NSThread.isMainThread())
    
    var rc = pthread_mutex_init(&sStateLock, nil)
    assert(rc == 0)
    
    rc = pthread_cond_init(&sStateChanged, nil)
    assert(rc == 0)
    
    sState = .Done
}

// handle begin interruption - transition to kStatePaused
func ThreadStateBeginInterruption() {
    
    assert(NSThread.isMainThread())
    
    var rc = pthread_mutex_lock(&sStateLock)
    assert(rc == 0)
    
    if sState == .Running {
        sState = .Paused
    }
    
    rc = pthread_mutex_unlock(&sStateLock)
    assert(rc == 0)
}

// handle end interruption - transition to kStateRunning
func ThreadStateEndInterruption() {
    
    assert(NSThread.isMainThread())
    
    var rc = pthread_mutex_lock(&sStateLock)
    assert(rc == 0)
    
    if sState == .Paused {
        sState = .Running
        
        rc = pthread_cond_signal(&sStateChanged)
        assert(rc == 0)
    }
    
    rc = pthread_mutex_unlock(&sStateLock)
    assert(rc == 0)
}

// set state to kStateRunning
func ThreadStateSetRunning() {
    var rc = pthread_mutex_lock(&sStateLock)
    assert(rc == 0)
    
    assert(sState == .Done)
    sState = .Running
    
    rc = pthread_mutex_unlock(&sStateLock)
    assert(rc == 0)
}

// block for state change to kStateRunning
func ThreadStatePausedCheck() -> Bool {
    var wasInterrupted = false
    
    var rc = pthread_mutex_lock(&sStateLock)
    assert(rc == 0)
    
    assert(sState != .Done)
    
    while sState == .Paused {
        rc = pthread_cond_wait(&sStateChanged, &sStateLock)
        assert(rc == 0)
        wasInterrupted = true
    }
    
    // we must be running or something bad has happened
    assert(sState == .Running)
    
    rc = pthread_mutex_unlock(&sStateLock)
    assert(rc == 0)
    
    return wasInterrupted
}

func ThreadStateSetDone() {
    var rc = pthread_mutex_lock(&sStateLock)
    assert(rc == 0)
    
    assert(sState != .Done)
    sState = .Done
    
    rc = pthread_mutex_unlock(&sStateLock)
    assert(rc == 0)
}

// ***********************
//MARK:- Converter
/* The main Audio Conversion function using AudioConverter */

let kMyAudioConverterErr_CannotResumeFromInterruptionError = OSStatus("CANT" as FourCharCode)
let eofErr: OSStatus = -39 // End of file

struct AudioFileIO {
    var srcFileID: AudioFileID = nil
    var srcFilePos: Int64 = 0
    var srcBuffer: UnsafeMutablePointer<CChar> = nil
    var srcBufferSize: UInt32 = 0
    var srcFormat: CAStreamBasicDescription = CAStreamBasicDescription()
    var srcSizePerPacket: UInt32 = 0
    var numPacketsPerRead: UInt32 = 0
    var packetDescriptions: UnsafeMutablePointer<AudioStreamPacketDescription> = nil
}
typealias AudioFileIOPtr = UnsafeMutablePointer<AudioFileIO>

//MARK:-

// Input data proc callback
private func EncoderDataProc(inAudioConverter: AudioConverterRef, _ ioNumberDataPackets: UnsafeMutablePointer<UInt32>, _ ioData: UnsafeMutablePointer<AudioBufferList>, _ outDataPacketDescription: UnsafeMutablePointer<UnsafeMutablePointer<AudioStreamPacketDescription>>, _ inUserData: UnsafeMutablePointer<Void>) -> OSStatus
{
    let afio: AudioFileIOPtr = UnsafeMutablePointer(inUserData)
    var error: OSStatus = noErr
    
    // figure out how much to read
    let maxPackets = afio.memory.srcBufferSize / afio.memory.srcSizePerPacket
    if ioNumberDataPackets.memory > maxPackets {ioNumberDataPackets.memory = maxPackets}
    
    // read from the file
    var ioNumBytes: UInt32 = afio.memory.srcBufferSize
    //### Deprecated in iOS 8.0
    //    error = AudioFileReadPackets(afio.memory.srcFileID, false, &outNumBytes, afio.memory.packetDescriptions, afio.memory.srcFilePos, ioNumberDataPackets, afio.memory.srcBuffer)
    error = AudioFileReadPacketData(afio.memory.srcFileID, false, &ioNumBytes, afio.memory.packetDescriptions, afio.memory.srcFilePos, ioNumberDataPackets, afio.memory.srcBuffer)
    if error == eofErr {error = noErr}
    if error != 0 { print("Input Proc Read error: \(error) (\(FourCharCode(error).possibleFourCharString))"); return error }
    
    //print("Input Proc: Read \(ioNumberDataPackets.memory) packets, at position \(afio.memory.srcFilePos) size \(ioNumBytes)")
    
    // advance input file packet position
    afio.memory.srcFilePos += Int64(ioNumberDataPackets.memory)
    
    // put the data pointer into the buffer list
    let ioDataPtr = UnsafeMutableAudioBufferListPointer(ioData)
    ioDataPtr[0].mData = UnsafeMutablePointer(afio.memory.srcBuffer)
    ioDataPtr[0].mDataByteSize = ioNumBytes
    ioDataPtr[0].mNumberChannels = afio.memory.srcFormat.mChannelsPerFrame
    
    // don't forget the packet descriptions if required
    if outDataPacketDescription != nil {
        if afio.memory.packetDescriptions != nil {
            outDataPacketDescription.memory = afio.memory.packetDescriptions
        } else {
            outDataPacketDescription.memory = nil
        }
    }
    
    return error
}

//MARK:-

// Some audio formats have a magic cookie associated with them which is required to decompress audio data
// When converting audio data you must check to see if the format of the data has a magic cookie
// If the audio data format has a magic cookie associated with it, you must add this information to anAudio Converter
// using AudioConverterSetProperty and kAudioConverterDecompressionMagicCookie to appropriately decompress the data
// http://developer.apple.com/mac/library/qa/qa2001/qa1318.html
private func ReadCookie(sourceFileID: AudioFileID, _ converter: AudioConverterRef) {
    // grab the cookie from the source file and set it on the converter
    var cookieSize: UInt32 = 0
    var error = AudioFileGetPropertyInfo(sourceFileID, kAudioFilePropertyMagicCookieData, &cookieSize, nil)
    
    // if there is an error here, then the format doesn't have a cookie - this is perfectly fine as some formats do not
    if error == noErr && cookieSize != 0 {
        let cookie = UnsafeMutablePointer<CChar>.alloc(Int(cookieSize))
        
        error = AudioFileGetProperty(sourceFileID, kAudioFilePropertyMagicCookieData, &cookieSize, cookie)
        if error == noErr {
            error = AudioConverterSetProperty(converter, kAudioConverterDecompressionMagicCookie, cookieSize, cookie)
            if error != 0 {print("Could not Set kAudioConverterDecompressionMagicCookie on the Audio Converter!")}
        } else {
            print("Could not Get kAudioFilePropertyMagicCookieData from source file!")
        }
        
        cookie.dealloc(Int(cookieSize))
    }
}

// Some audio formats have a magic cookie associated with them which is required to decompress audio data
// When converting audio, a magic cookie may be returned by the Audio Converter so that it may be stored along with
// the output data -- This is done so that it may then be passed back to the Audio Converter at a later time as required
private func WriteCookie(converter: AudioConverterRef, _ destinationFileID: AudioFileID) {
    // grab the cookie from the converter and write it to the destinateion file
    var cookieSize: UInt32 = 0
    var error = AudioConverterGetPropertyInfo(converter, kAudioConverterCompressionMagicCookie, &cookieSize, nil)
    
    // if there is an error here, then the format doesn't have a cookie - this is perfectly fine as some formats do not
    guard error == noErr && cookieSize != 0 else {return}
    var cookie: [CChar] = Array(count: Int(cookieSize), repeatedValue: 0)
    
    error = AudioConverterGetProperty(converter, kAudioConverterCompressionMagicCookie, &cookieSize, &cookie)
    guard error == noErr else {
        print("Could not Get kAudioConverterCompressionMagicCookie from Audio Converter!")
        return
    }
    error = AudioFileSetProperty(destinationFileID, kAudioFilePropertyMagicCookieData, cookieSize, cookie)
    guard error == noErr else {
        print("Even though some formats have cookies, some files don't take them and that's OK")
        return
    }
    print("Writing magic cookie to destination file: \(cookieSize)")
}

// Write output channel layout to destination file
private func WriteDestinationChannelLayout(converter: AudioConverterRef, _ sourceFileID: AudioFileID, _ destinationFileID: AudioFileID) {
    var layoutSize: UInt32 = 0
    var layoutFromConverter = true
    
    var error = AudioConverterGetPropertyInfo(converter, kAudioConverterOutputChannelLayout, &layoutSize, nil)
    
    // if the Audio Converter doesn't have a layout see if the input file does
    if error != 0 || layoutSize == 0 {
        error = AudioFileGetPropertyInfo(sourceFileID, kAudioFilePropertyChannelLayout, &layoutSize, nil)
        layoutFromConverter = false
    }
    
    guard error == noErr && layoutSize != 0 else {return}
    var layout: [CChar] = Array(count: Int(layoutSize), repeatedValue: 0)
    
    if layoutFromConverter {
        error = AudioConverterGetProperty(converter, kAudioConverterOutputChannelLayout, &layoutSize, &layout)
        if error != 0 {print("Could not Get kAudioConverterOutputChannelLayout from Audio Converter!")}
    } else {
        error = AudioFileGetProperty(sourceFileID, kAudioFilePropertyChannelLayout, &layoutSize, &layout)
        if error != 0 {print("Could not Get kAudioFilePropertyChannelLayout from source file!")}
    }
    
    guard error == noErr else {return}
    error = AudioFileSetProperty(destinationFileID, kAudioFilePropertyChannelLayout, layoutSize, layout)
    guard error == noErr else {
        print("Even though some formats have layouts, some files don't take them and that's OK")
        return
    }
    print("Writing channel layout to destination file: \(layoutSize)")
    
}

// Sets the packet table containing information about the number of valid frames in a file and where they begin and end
// for the file types that support this information.
// Calling this function makes sure we write out the priming and remainder details to the destination file
private func WritePacketTableInfo(converter: AudioConverterRef, _ destinationFileID: AudioFileID) {
    var isWritable: UInt32 = 0
    var dataSize: UInt32 = 0
    var error = AudioFileGetPropertyInfo(destinationFileID, kAudioFilePropertyPacketTableInfo, &dataSize, &isWritable)
    guard error == noErr && isWritable != 0 else {
        print("GetPropertyInfo for kAudioFilePropertyPacketTableInfo error: \(error), isWritable: \(isWritable)")
        return
    }
    
    var primeInfo: AudioConverterPrimeInfo = AudioConverterPrimeInfo()
    dataSize = UInt32(sizeofValue(primeInfo))
    
    // retrieve the leadingFrames and trailingFrames information from the converter,
    error = AudioConverterGetProperty(converter, kAudioConverterPrimeInfo, &dataSize, &primeInfo)
    guard error == noErr else {
        print("No kAudioConverterPrimeInfo available and that's OK")
        return
    }
    // we have some priming information to write out to the destination file
    /* The total number of packets in the file times the frames per packet (or counting each packet's
    frames individually for a variable frames per packet format) minus mPrimingFrames, minus
    mRemainderFrames, should equal mNumberValidFrames.
    */
    var pti: AudioFilePacketTableInfo = AudioFilePacketTableInfo()
    dataSize = UInt32(sizeofValue(pti))
    error = AudioFileGetProperty(destinationFileID, kAudioFilePropertyPacketTableInfo, &dataSize, &pti)
    guard error == noErr else {
        print("Getting kAudioFilePropertyPacketTableInfo error: \(error)")
        return
    }
    // there's priming to write out to the file
    let totalFrames = UInt64(pti.mNumberValidFrames) + UInt64(pti.mPrimingFrames) + UInt64(pti.mRemainderFrames) // get the total number of frames from the output file
    print("Total number of frames from output file: \(totalFrames)")
    
    pti.mPrimingFrames = Int32(primeInfo.leadingFrames)
    pti.mRemainderFrames = Int32(primeInfo.trailingFrames)
    pti.mNumberValidFrames = Int64(totalFrames) - Int64(pti.mPrimingFrames) - Int64(pti.mRemainderFrames)
    
    error = AudioFileSetProperty(destinationFileID, kAudioFilePropertyPacketTableInfo, UInt32(sizeofValue(pti)), &pti)
    guard error == noErr else {
        print("Some audio files can't contain packet table information and that's OK");
        return
    }
    print("Writing packet table information to destination file: \(sizeofValue(pti))")
    print("     Total valid frames: \(pti.mNumberValidFrames)")
    print("         Priming frames: \(pti.mPrimingFrames)")
    print("       Remainder frames: \(pti.mRemainderFrames)")
}

//MARK:-

func DoConvertFile(sourceURL: NSURL, _ destinationURL: NSURL, _ outputFormat: OSType, _ outputSampleRate: Float64) -> OSStatus {
    var sourceFileID: AudioFileID = nil
    var destinationFileID: AudioFileID = nil
    var converter: AudioConverterRef = nil
    var canResumeFromInterruption = true // we can continue unless told otherwise
    
    var srcFormat: CAStreamBasicDescription = CAStreamBasicDescription()
    var dstFormat: CAStreamBasicDescription = CAStreamBasicDescription()
    var afio = AudioFileIO()
    
    var outputBuffer: UnsafeMutablePointer<CChar> = nil
    var outputPacketDescriptions: UnsafeMutablePointer<AudioStreamPacketDescription> = nil
    
    var error = noErr
    
    // in this sample we should never be on the main thread here
    assert(!NSThread.isMainThread())
    
    // transition thread state to kStateRunning before continuing
    ThreadStateSetRunning()
    
    print("\nDoConvertFile")
    
    var outputSizePerPacket: UInt32 = 0
    let theOutputBufSize: UInt32 = 32768
    do {
        // get the source file
        try XThrowIfError(AudioFileOpenURL(sourceURL, .ReadPermission, 0, &sourceFileID), "AudioFileOpenURL failed")
        
        // get the source data format
        var size = UInt32(sizeofValue(srcFormat))
        try XThrowIfError(AudioFileGetProperty(sourceFileID, kAudioFilePropertyDataFormat, &size, &srcFormat), "couldn't get source data format")
        
        // setup the output file format
        dstFormat.mSampleRate = (outputSampleRate == 0 ? srcFormat.mSampleRate : outputSampleRate) // set sample rate
        if outputFormat == kAudioFormatLinearPCM {
            // if the output format is PC create a 16-bit int PCM file format description as an example
            dstFormat.mFormatID = outputFormat
            dstFormat.mChannelsPerFrame = srcFormat.numberChannels
            dstFormat.mBitsPerChannel = 16
            dstFormat.mBytesPerPacket = 2 * dstFormat.mChannelsPerFrame
            dstFormat.mBytesPerFrame = dstFormat.mBytesPerPacket
            dstFormat.mFramesPerPacket = 1
            dstFormat.mFormatFlags = kLinearPCMFormatFlagIsPacked | kLinearPCMFormatFlagIsSignedInteger // little-endian
        } else {
            // compressed format - need to set at least format, sample rate and channel fields for kAudioFormatProperty_FormatInfo
            dstFormat.mFormatID = outputFormat
            dstFormat.mChannelsPerFrame =  (outputFormat == kAudioFormatiLBC ? 1 : srcFormat.numberChannels) // for iLBC num channels must be 1
            
            // use AudioFormat API to fill out the rest of the description
            size = UInt32(sizeofValue(dstFormat))
            try XThrowIfError(AudioFormatGetProperty(kAudioFormatProperty_FormatInfo, 0, nil, &size, &dstFormat), "couldn't create destination data format")
        }
        
        print("Source File format: ", terminator: ""); srcFormat.print()
        print("Destination format: ", terminator: ""); dstFormat.print()
        
        // create the AudioConverter
        
        try XThrowIfError(AudioConverterNew(&srcFormat, &dstFormat, &converter), "AudioConverterNew failed!")
        
        // if the source has a cookie, get it and set it on the Audio Converter
        ReadCookie(sourceFileID, converter)
        
        // get the actual formats back from the Audio Converter
        size = UInt32(sizeofValue(srcFormat))
        try XThrowIfError(AudioConverterGetProperty(converter, kAudioConverterCurrentInputStreamDescription, &size, &srcFormat), "AudioConverterGetProperty kAudioConverterCurrentInputStreamDescription failed!")
        
        size = UInt32(sizeofValue(dstFormat))
        try XThrowIfError(AudioConverterGetProperty(converter, kAudioConverterCurrentOutputStreamDescription, &size, &dstFormat), "AudioConverterGetProperty kAudioConverterCurrentOutputStreamDescription failed!")
        
        print("Formats returned from AudioConverter:")
        print("              Source format: ", terminator: ""); srcFormat.print()
        print("    Destination File format: ", terminator: ""); dstFormat.print()
        
        // if encoding to AAC set the bitrate
        // kAudioConverterEncodeBitRate is a UInt32 value containing the number of bits per second to aim for when encoding data
        // when you explicitly set the bit rate and the sample rate, this tells the encoder to stick with both bit rate and sample rate
        //     but there are combinations (also depending on the number of channels) which will not be allowed
        // if you do not explicitly set a bit rate the encoder will pick the correct value for you depending on samplerate and number of channels
        // bit rate also scales with the number of channels, therefore one bit rate per sample rate can be used for mono cases
        //    and if you have stereo or more, you can multiply that number by the number of channels.
        if dstFormat.mFormatID == kAudioFormatMPEG4AAC {
            var outputBitRate: UInt32 = 64000; // 64kbs
            var propSize = UInt32(sizeofValue(outputBitRate))
            
            if dstFormat.mSampleRate >= 44100 {
                outputBitRate = 192000 // 192kbs
            } else if dstFormat.mSampleRate < 22000 {
                outputBitRate = 32000 // 32kbs
            }
            
            // set the bit rate depending on the samplerate chosen
            try XThrowIfError(AudioConverterSetProperty(converter, kAudioConverterEncodeBitRate, propSize, &outputBitRate),
                "AudioConverterSetProperty kAudioConverterEncodeBitRate failed!")
            
            // get it back and print it out
            AudioConverterGetProperty(converter, kAudioConverterEncodeBitRate, &propSize, &outputBitRate)
            print("AAC Encode Bitrate: \(outputBitRate)")
        }
        
        // can the Audio Converter resume conversion after an interruption?
        // this property may be queried at any time after construction of the Audio Converter after setting its output format
        // there's no clear reason to prefer construction time, interruption time, or potential resumption time but we prefer
        // construction time since it means less code to execute during or after interruption time
        var canResume: UInt32 = 0
        size = UInt32(sizeofValue(canResume))
        error = AudioConverterGetProperty(converter, kAudioConverterPropertyCanResumeFromInterruption, &size, &canResume)
        if error == noErr {
            // we recieved a valid return value from the GetProperty call
            // if the property's value is 1, then the codec CAN resume work following an interruption
            // if the property's value is 0, then interruptions destroy the codec's state and we're done
            
            if canResume == 0 {canResumeFromInterruption = false}
            
            print("Audio Converter %@ continue after interruption!", (canResumeFromInterruption ? "CAN" : "CANNOT"))
        } else {
            // if the property is unimplemented (kAudioConverterErr_PropertyNotSupported, or paramErr returned in the case of PCM),
            // then the codec being used is not a hardware codec so we're not concerned about codec state
            // we are always going to be able to resume conversion after an interruption
            
            if error == kAudioConverterErr_PropertyNotSupported {
                print("kAudioConverterPropertyCanResumeFromInterruption property not supported - see comments in source for more info.")
            } else {
                print("AudioConverterGetProperty kAudioConverterPropertyCanResumeFromInterruption result \(error), paramErr is OK if PCM")
            }
            
            error = noErr
        }
        
        // create the destination file
        try XThrowIfError(AudioFileCreateWithURL(destinationURL, kAudioFileCAFType, &dstFormat, .EraseFile, &destinationFileID), "AudioFileCreateWithURL failed!")
        
        // set up source buffers and data proc info struct
        afio.srcFileID = sourceFileID
        afio.srcBufferSize = 32768
        afio.srcBuffer = UnsafeMutablePointer<CChar>.alloc(Int(afio.srcBufferSize))
        afio.srcFilePos = 0
        afio.srcFormat = srcFormat
        
        if srcFormat.mBytesPerPacket == 0 {
            // if the source format is VBR, we need to get the maximum packet size
            // use kAudioFilePropertyPacketSizeUpperBound which returns the theoretical maximum packet size
            // in the file (without actually scanning the whole file to find the largest packet,
            // as may happen with kAudioFilePropertyMaximumPacketSize)
            size = UInt32(sizeofValue(afio.srcSizePerPacket))
            try XThrowIfError(AudioFileGetProperty(sourceFileID, kAudioFilePropertyPacketSizeUpperBound, &size, &afio.srcSizePerPacket), "AudioFileGetProperty kAudioFilePropertyPacketSizeUpperBound failed!")
            
            // how many packets can we read for our buffer size?
            afio.numPacketsPerRead = afio.srcBufferSize / afio.srcSizePerPacket
            
            // allocate memory for the PacketDescription structures describing the layout of each packet
            afio.packetDescriptions = UnsafeMutablePointer<AudioStreamPacketDescription>.alloc(Int(afio.numPacketsPerRead))
        } else {
            // CBR source format
            afio.srcSizePerPacket = srcFormat.mBytesPerPacket
            afio.numPacketsPerRead = afio.srcBufferSize / afio.srcSizePerPacket
            afio.packetDescriptions = nil
        }
        
        // set up output buffers
        outputSizePerPacket = dstFormat.mBytesPerPacket // this will be non-zero if the format is CBR
        outputBuffer = UnsafeMutablePointer<CChar>.alloc(Int(theOutputBufSize))
        
        if outputSizePerPacket == 0 {
            // if the destination format is VBR, we need to get max size per packet from the converter
            size = UInt32(sizeofValue(outputSizePerPacket))
            try XThrowIfError(AudioConverterGetProperty(converter, kAudioConverterPropertyMaximumOutputPacketSize, &size, &outputSizePerPacket), "AudioConverterGetProperty kAudioConverterPropertyMaximumOutputPacketSize failed!")
            
            // allocate memory for the PacketDescription structures describing the layout of each packet
            outputPacketDescriptions = UnsafeMutablePointer<AudioStreamPacketDescription>.alloc(Int(theOutputBufSize / outputSizePerPacket))
        }
        let numOutputPackets = theOutputBufSize / outputSizePerPacket
        
        // if the destination format has a cookie, get it and set it on the output file
        WriteCookie(converter, destinationFileID)
        
        // write destination channel layout
        if srcFormat.mChannelsPerFrame > 2 {
            WriteDestinationChannelLayout(converter, sourceFileID, destinationFileID)
        }
        
        var totalOutputFrames = 0 // used for debgging printf
        var outputFilePos: Int64 = 0
        
        // loop to convert data
        print("Converting...")
        while true {
            
            // set up output buffer list
            var fillBufList = AudioBufferList(
                mNumberBuffers: 1,
                mBuffers: AudioBuffer(
                    mNumberChannels: dstFormat.mChannelsPerFrame,
                    mDataByteSize: UInt32(theOutputBufSize),
                    mData: outputBuffer)
            )
            
            // this will block if we're interrupted
            let wasInterrupted = ThreadStatePausedCheck()
            
            if (error != 0 || wasInterrupted) && !canResumeFromInterruption {
                // this is our interruption termination condition
                // an interruption has occured but the Audio Converter cannot continue
                error = kMyAudioConverterErr_CannotResumeFromInterruptionError
                break
            }
            
            // convert data
            var ioOutputDataPackets = numOutputPackets
            print("AudioConverterFillComplexBuffer...")
            error = AudioConverterFillComplexBuffer(converter, EncoderDataProc, &afio, &ioOutputDataPackets, &fillBufList, outputPacketDescriptions)
            // if interrupted in the process of the conversion call, we must handle the error appropriately
            if error != 0 {
                if error == kAudioConverterErr_HardwareInUse {
                    print("Audio Converter returned kAudioConverterErr_HardwareInUse!")
                } else {
                    try XThrowIfError(error, "AudioConverterFillComplexBuffer error!")
                }
            } else {
                if ioOutputDataPackets == 0 {
                    // this is the EOF conditon
                    error = noErr
                    break
                }
            }
            
            if error == noErr {
                // write to output file
                let inNumBytes = fillBufList.mBuffers.mDataByteSize
                try XThrowIfError(AudioFileWritePackets(destinationFileID, false, inNumBytes, outputPacketDescriptions, outputFilePos, &ioOutputDataPackets, outputBuffer), "AudioFileWritePackets failed!")
                
                print("Convert Output: Write \(ioOutputDataPackets) packets at position \(outputFilePos), size: \(inNumBytes)")
                
                // advance output file packet position
                outputFilePos += Int64(ioOutputDataPackets)
                
                if dstFormat.mFramesPerPacket != 0 {
                    // the format has constant frames per packet
                    totalOutputFrames += Int(ioOutputDataPackets * dstFormat.mFramesPerPacket)
                } else if outputPacketDescriptions != nil {
                    // variable frames per packet require doing this for each packet (adding up the number of sample frames of data in each packet)
                    for i in 0..<Int(ioOutputDataPackets) {
                        totalOutputFrames += Int(outputPacketDescriptions[i].mVariableFramesInPacket)
                    }
                }
            }
        }
        
        if error == noErr {
            // write out any of the leading and trailing frames for compressed formats only
            if dstFormat.mBitsPerChannel == 0 {
                // our output frame count should jive with
                print("Total number of output frames counted: \(totalOutputFrames)")
                WritePacketTableInfo(converter, destinationFileID)
            }
            
            // write the cookie again - sometimes codecs will update cookies at the end of a conversion
            WriteCookie(converter, destinationFileID)
        }
    } catch let e as CAXException {
        print("Error: \(e.mOperation) (\(e.formatError()))\n", toStream: &stderr)
        error = e.mError
    } catch _ {
        fatalError()
    }
    
    // cleanup
    if converter != nil {AudioConverterDispose(converter)}
    if destinationFileID != nil {AudioFileClose(destinationFileID)}
    if sourceFileID != nil {AudioFileClose(sourceFileID)}
    
    if afio.srcBuffer != nil {afio.srcBuffer.dealloc(Int(afio.srcBufferSize))}
    if afio.packetDescriptions != nil {afio.packetDescriptions.dealloc(Int(afio.numPacketsPerRead))}
    if outputBuffer != nil {outputBuffer.dealloc(Int(theOutputBufSize))}
    if outputPacketDescriptions != nil {outputPacketDescriptions.dealloc(Int(theOutputBufSize / outputSizePerPacket))}
    
    // transition thread state to kStateDone before continuing
    ThreadStateSetDone()
    
    return error
}