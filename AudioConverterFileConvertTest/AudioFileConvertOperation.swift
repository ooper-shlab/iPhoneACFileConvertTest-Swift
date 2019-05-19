//
//  AudioFileConvertOperation.swift
//  AudioConverterFileConvertTest
//
//  Translated by OOPer in cooperation with shlab.jp, on 2017/1/3.
//
//
/*
    Copyright (C) 2016 Apple Inc. All Rights Reserved.
    See LICENSE.txt for this sample’s licensing information

    Abstract:
    Demonstrates converting audio using AudioConverterFillComplexBuffer.
 */

import Foundation
import AudioToolbox
import AVFoundation

@objc(AudioFileConvertOperationDelegate)
protocol  AudioFileConvertOperationDelegate {
    
    @objc(audioFileConvertOperation:didEncounterError:)
    func audioFileConvertOperation(_ audioFileConvertOperation: AudioFileConvertOperation, didEncounterError error: Error)
    
    @objc(audioFileConvertOperation:didCompleteWithURL:)
    func audioFileConvertOperation(_ audioFileConvertOperation: AudioFileConvertOperation, didCompleteWith destinationURL: URL)
    
}

// ***********************
//MARK:- Converter
/* The main Audio Conversion function using AudioConverter */

extension OSStatus {
    static let kMyAudioConverterErr_CannotResumeFromInterruptionError = OSStatus("CANT" as FourCharCode)
    static let eofErr: OSStatus = -39 // End of file
}

private struct AudioFileIO {
    var srcFileID: AudioFileID?
    var srcFilePos: Int64 = 0
    var srcBuffer: UnsafeMutablePointer<CChar>?
    var srcBufferSize: UInt32 = 0
    var srcFormat: AudioStreamBasicDescription = AudioStreamBasicDescription()
    var srcSizePerPacket: UInt32 = 0
    var numPacketsPerRead: UInt32 = 0
    var packetDescriptions: UnsafeMutablePointer<AudioStreamPacketDescription>?
}

//MARK:-

// Input data proc callback
private let EncoderDataProc: AudioConverterComplexInputDataProc = {inAudioConverter, ioNumberDataPackets, ioData, outDataPacketDescription, inUserData
    in
    let afio = inUserData!.assumingMemoryBound(to: AudioFileIO.self)
    var error: OSStatus = noErr
    
    // figure out how much to read
    let maxPackets = afio.pointee.srcBufferSize / afio.pointee.srcSizePerPacket
    if ioNumberDataPackets.pointee > maxPackets {ioNumberDataPackets.pointee = maxPackets}
    
    // read from the file
    var outNumBytes = maxPackets * afio.pointee.srcSizePerPacket
    
    error = AudioFileReadPacketData(afio.pointee.srcFileID!, false, &outNumBytes, afio.pointee.packetDescriptions, afio.pointee.srcFilePos, ioNumberDataPackets, afio.pointee.srcBuffer)
    if error == .eofErr {error = noErr}
    guard error == noErr else {
        print("Input Proc Read error: \(error) (\((UInt32(bitPattern: error).fourCharString))")
        return error
    }
    
    //print("Input Proc: Read \(ioNumberDataPackets.pointee) packets, at position \(afio.pointee.srcFilePos) size \(outNumBytes)")
    
    // advance input file packet position
    afio.pointee.srcFilePos += Int64(ioNumberDataPackets.pointee)
    
    // put the data pointer into the buffer list
    let ioDataPtr = UnsafeMutableAudioBufferListPointer(ioData)
    ioDataPtr[0].mData = UnsafeMutableRawPointer(afio.pointee.srcBuffer)
    ioDataPtr[0].mDataByteSize = outNumBytes
    ioDataPtr[0].mNumberChannels = afio.pointee.srcFormat.mChannelsPerFrame
    
    // don't forget the packet descriptions if required
    if let outDataPacketDescription = outDataPacketDescription {
        if afio.pointee.packetDescriptions != nil {
            outDataPacketDescription.pointee = afio.pointee.packetDescriptions
        } else {
            outDataPacketDescription.pointee = nil
        }
    }
    
    return error
}

private enum AudioConverterState: Int {
    case initial
    case running
    case paused
    case done
}

@objc(AudioFileConvertOperation)
class AudioFileConvertOperation: Operation {
    
    let sourceURL: URL
    
    let destinationURL: URL
    
    let sampleRate: Float64
    
    let outputFormat: AudioFormatID
    
    weak var delegate: AudioFileConvertOperationDelegate?
    
    // MARK: Properties
    
    private var queue: DispatchQueue = DispatchQueue(label: "com.example.apple-samplecode.AudioConverterFileConvertTest.AudioFileConverOperation.queue", attributes: .concurrent)
    
    private var semaphore: DispatchSemaphore = DispatchSemaphore(value: 0)
    
    private var state: AudioConverterState = .initial
    
    // MARK: Initialization
    
    init(sourceURL: URL, destinationURL: URL, sampleRate: Float64, outputFormat: AudioFormatID) {
        
        self.sourceURL = sourceURL
        self.destinationURL = destinationURL
        self.sampleRate = sampleRate
        self.outputFormat = outputFormat
        
        super.init()
        
        NotificationCenter.default.addObserver(self, selector: #selector(handleAudioSessionInterruptionNotification), name: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance())
        
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self, name: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance())
    }
    
    override func main() {
        super.main()
        
        // This should never run on the main thread.
        assert(!Thread.isMainThread)
        
        var outputPacketDescriptions: UnsafeMutablePointer<AudioStreamPacketDescription>? = nil
        
        // Set the state to running.
        
        self.queue.sync {[weak self] in
            self?.state = .running
        }
        
        var error: OSStatus = noErr
        do {//### for cleanup defers
            // Get the source file.
            var _sourceFileID: AudioFileID? = nil
            
            guard checkError(AudioFileOpenURL(self.sourceURL as CFURL, .readPermission, 0, &_sourceFileID), withError: "AudioFileOpenURL failed for sourceFile with URL: \(self.sourceURL)"),
                let sourceFileID = _sourceFileID else {
                    return
            }
            defer {AudioFileClose(sourceFileID)}
            
            // Get the source data format.
            var sourceFormat = AudioStreamBasicDescription()
            var size = UInt32(MemoryLayout.stride(ofValue: sourceFormat))
            guard checkError(AudioFileGetProperty(sourceFileID, kAudioFilePropertyDataFormat, &size, &sourceFormat), withError: "AudioFileGetProperty couldn't get the source data format") else {
                return
            }
            
            // Setup the output file format.
            var destinationFormat = AudioStreamBasicDescription()
            destinationFormat.mSampleRate = (self.sampleRate == 0 ? sourceFormat.mSampleRate : self.sampleRate);
            
            if self.outputFormat == kAudioFormatLinearPCM {
                // If the output format is PCM, create a 16-bit file format description.
                destinationFormat.mFormatID = self.outputFormat
                destinationFormat.mChannelsPerFrame = sourceFormat.mChannelsPerFrame
                destinationFormat.mBitsPerChannel = 16
                destinationFormat.mBytesPerPacket = 2 * destinationFormat.mChannelsPerFrame
                destinationFormat.mBytesPerFrame = destinationFormat.mBytesPerPacket
                destinationFormat.mFramesPerPacket = 1
                destinationFormat.mFormatFlags = kLinearPCMFormatFlagIsPacked | kLinearPCMFormatFlagIsSignedInteger // little-endian
            } else {
                // This is a compressed format, need to set at least format, sample rate and channel fields for kAudioFormatProperty_FormatInfo.
                destinationFormat.mFormatID = self.outputFormat
                
                // For iLBC, the number of channels must be 1.
                destinationFormat.mChannelsPerFrame = (self.outputFormat == kAudioFormatiLBC ? 1 : sourceFormat.mChannelsPerFrame)
                
                // Use AudioFormat API to fill out the rest of the description.
                size = UInt32(MemoryLayout.stride(ofValue: destinationFormat))
                guard checkError(AudioFormatGetProperty(kAudioFormatProperty_FormatInfo, 0, nil, &size, &destinationFormat), withError: "AudioFormatGetProperty couldn't fill out the destination data format") else {
                    return
                }
            }
            
            print("Source File format:")
            AudioFileConvertOperation.printAudioStreamBasicDescription(sourceFormat)
            print("Destination File format:")
            AudioFileConvertOperation.printAudioStreamBasicDescription(destinationFormat)
            
            // Create the AudioConverterRef.
            var _converter: AudioConverterRef? = nil
            guard checkError(AudioConverterNew(&sourceFormat, &destinationFormat, &_converter), withError: "AudioConverterNew failed"),
                let converter = _converter else {
                    return
            }
            defer {AudioConverterDispose(converter)}
            
            // If the source file has a cookie, get ir and set it on the AudioConverterRef.
            self.readCookie(from: sourceFileID, converter: converter)
            
            // Get the actuall formats (source and destination) from the AudioConverterRef.
            size = UInt32(MemoryLayout.stride(ofValue: sourceFormat))
            guard checkError(AudioConverterGetProperty(converter, kAudioConverterCurrentInputStreamDescription, &size, &sourceFormat), withError: "AudioConverterGetProperty kAudioConverterCurrentInputStreamDescription failed!") else {
                return
            }
            
            size = UInt32(MemoryLayout.stride(ofValue: destinationFormat))
            guard checkError(AudioConverterGetProperty(converter, kAudioConverterCurrentOutputStreamDescription, &size, &destinationFormat), withError: "AudioConverterGetProperty kAudioConverterCurrentOutputStreamDescription failed!") else {
                return
            }
            
            print("Formats returned from AudioConverter:")
            print("Source File format:")
            AudioFileConvertOperation.printAudioStreamBasicDescription(sourceFormat)
            print("Destination File format:")
            AudioFileConvertOperation.printAudioStreamBasicDescription(destinationFormat)
            
            /*
             If encoding to AAC set the bitrate kAudioConverterEncodeBitRate is a UInt32 value containing
             the number of bits per second to aim for when encoding data when you explicitly set the bit rate
             and the sample rate, this tells the encoder to stick with both bit rate and sample rate
             but there are combinations (also depending on the number of channels) which will not be allowed
             if you do not explicitly set a bit rate the encoder will pick the correct value for you depending
             on samplerate and number of channels bit rate also scales with the number of channels,
             therefore one bit rate per sample rate can be used for mono cases and if you have stereo or more,
             you can multiply that number by the number of channels.
             */
            
            if destinationFormat.mFormatID == kAudioFormatMPEG4AAC {
                var outputBitRate: UInt32 = 64000
                
                var propSize = UInt32(MemoryLayout.size(ofValue: outputBitRate))
                
                if destinationFormat.mSampleRate >= 44100 {
                    outputBitRate = 192000
                } else if destinationFormat.mSampleRate < 22000 {
                    outputBitRate = 32000
                }
                
                // Set the bit rate depending on the sample rate chosen.
                guard checkError(AudioConverterSetProperty(converter, kAudioConverterEncodeBitRate, propSize, &outputBitRate), withError: "AudioConverterSetProperty kAudioConverterEncodeBitRate failed!") else {
                    return
                }
                
                // Get it back and print it out.
                AudioConverterGetProperty(converter, kAudioConverterEncodeBitRate, &propSize, &outputBitRate)
                print("AAC Encode Bitrate: \(outputBitRate)")
            }
            
            /*
             Can the Audio Converter resume after an interruption?
             this property may be queried at any time after construction of the Audio Converter after setting its output format
             there's no clear reason to prefer construction time, interruption time, or potential resumption time but we prefer
             construction time since it means less code to execute during or after interruption time.
             */
            var canResumeFromInterruption = true
            var canResume: UInt32 = 0
            size = UInt32(MemoryLayout.size(ofValue: canResume))
            error = AudioConverterGetProperty(converter, kAudioConverterPropertyCanResumeFromInterruption, &size, &canResume)
            
            if error == noErr {
                /*
                 we recieved a valid return value from the GetProperty call
                 if the property's value is 1, then the codec CAN resume work following an interruption
                 if the property's value is 0, then interruptions destroy the codec's state and we're done
                 */
                
                if canResume == 0 {
                    canResumeFromInterruption = false
                }
                
                print("Audio Converter \(canResumeFromInterruption ? "CAN" : "CANNOT") continue after interruption!")
                
            } else {
                /*
                 if the property is unimplemented (kAudioConverterErr_PropertyNotSupported, or paramErr returned in the case of PCM),
                 then the codec being used is not a hardware codec so we're not concerned about codec state
                 we are always going to be able to resume conversion after an interruption
                 */
                
                if error == kAudioConverterErr_PropertyNotSupported {
                    print("kAudioConverterPropertyCanResumeFromInterruption property not supported - see comments in source for more info.")
                } else {
                    print("AudioConverterGetProperty kAudioConverterPropertyCanResumeFromInterruption result \(error), paramErr is OK if PCM")
                }
                
                error = noErr
            }
            
            // Create the destination audio file.
            var _destinationFileID: AudioFileID? = nil
            guard checkError(AudioFileCreateWithURL(self.destinationURL as CFURL, kAudioFileCAFType, &destinationFormat, .eraseFile, &_destinationFileID), withError: "AudioFileCreateWithURL failed!"),
                let destinationFileID = _destinationFileID else {
                    return
            }
            defer {AudioFileClose(destinationFileID)}
            
            // Setup source buffers and data proc info struct.
            var afio = AudioFileIO()
            afio.srcFileID = sourceFileID
            afio.srcBufferSize = 32768
            afio.srcBuffer = .allocate(capacity: Int(afio.srcBufferSize))
            afio.srcFilePos = 0
            afio.srcFormat = sourceFormat
            defer {afio.srcBuffer?.deallocate()}
            
            if sourceFormat.mBytesPerPacket == 0 {
                /*
                 if the source format is VBR, we need to get the maximum packet size
                 use kAudioFilePropertyPacketSizeUpperBound which returns the theoretical maximum packet size
                 in the file (without actually scanning the whole file to find the largest packet,
                 as may happen with kAudioFilePropertyMaximumPacketSize)
                 */
                size = UInt32(MemoryLayout.size(ofValue: afio.srcSizePerPacket))
                guard checkError(AudioFileGetProperty(sourceFileID, kAudioFilePropertyPacketSizeUpperBound, &size, &afio.srcSizePerPacket), withError: "AudioFileGetProperty kAudioFilePropertyPacketSizeUpperBound failed!") else {
                    return
                }
                
                // How many packets can we read for our buffer size?
                afio.numPacketsPerRead = afio.srcBufferSize / afio.srcSizePerPacket
                
                // Allocate memory for the PacketDescription structs describing the layout of each packet.
                afio.packetDescriptions = .allocate(capacity: Int(afio.numPacketsPerRead))
            } else {
                // CBR source format
                afio.srcSizePerPacket = sourceFormat.mBytesPerPacket
                afio.numPacketsPerRead = afio.srcBufferSize / afio.srcSizePerPacket
                afio.packetDescriptions = nil
            }
            defer {afio.packetDescriptions?.deallocate()}
            
            // Set up output buffers
            var outputSizePerPacket = destinationFormat.mBytesPerPacket
            var theOutputBufferSize: UInt32 = 32768
            let outputBuffer = UnsafeMutablePointer<CChar>.allocate(capacity: Int(theOutputBufferSize))
            defer {outputBuffer.deallocate()}
            
            if outputSizePerPacket == 0 {
                // if the destination format is VBR, we need to get max size per packet from the converter
                size = UInt32(MemoryLayout.size(ofValue: outputSizePerPacket))
                
                guard checkError(AudioConverterGetProperty(converter, kAudioConverterPropertyMaximumOutputPacketSize, &size, &outputSizePerPacket), withError: "AudioConverterGetProperty kAudioConverterPropertyMaximumOutputPacketSize failed!") else {
                    
                    return
                }
                
                // allocate memory for the PacketDescription structures describing the layout of each packet
                outputPacketDescriptions = .allocate(capacity: Int(theOutputBufferSize / outputSizePerPacket))
            }
            defer {outputPacketDescriptions?.deallocate()}
            
            let numberOutputPackets = theOutputBufferSize / outputSizePerPacket
            
            // If the destination format has a cookie, get it and set it on the output file.
            self.writeCookie(for: destinationFileID, converter: converter)
            
            // Write destination channel layout.
            if sourceFormat.mChannelsPerFrame > 2 {
                self.writeChannelLayout(converter: converter, source: sourceFileID, destination: destinationFileID)
            }
            
            // Used for debugging printf
            var totalOutputFrames: UInt64 = 0
            var outputFilePosition: Int64 = 0
            
            // Loop to convert data.
            print("Converting...")
            while true {
                
                // Set up output buffer list.
                var fillBufferList = AudioBufferList()
                fillBufferList.mNumberBuffers = 1
                fillBufferList.mBuffers.mNumberChannels = destinationFormat.mChannelsPerFrame
                fillBufferList.mBuffers.mDataByteSize = theOutputBufferSize
                fillBufferList.mBuffers.mData = UnsafeMutableRawPointer(outputBuffer)
                
                
                let wasInterrupted = self.checkIfPausedDueToInterruption()
                
                if (error != noErr || wasInterrupted) && !canResumeFromInterruption {
                    // this is our interruption termination condition
                    // an interruption has occured but the Audio Converter cannot continue
                    error = .kMyAudioConverterErr_CannotResumeFromInterruptionError
                    break
                }
                
                // Convert data
                var ioOutputDataPackets = numberOutputPackets
                print("AudioConverterFillComplexBuffer...")
                error = AudioConverterFillComplexBuffer(converter, EncoderDataProc, &afio, &ioOutputDataPackets, &fillBufferList, outputPacketDescriptions)
                
                // if interrupted in the process of the conversion call, we must handle the error appropriately
                if error != noErr {
                    if error == kAudioConverterErr_HardwareInUse {
                        print("Audio Converter returned kAudioConverterErr_HardwareInUse!")
                    } else {
                        guard checkError(error, withError: "AudioConverterFillComplexBuffer error!") else {
                            return
                        }
                    }
                } else {
                    if ioOutputDataPackets == 0 {
                        // This is the EOF condition.
                        error = noErr
                        break
                    }
                }
                
                if error == noErr {
                    // Write to output file.
                    let inNumBytes = fillBufferList.mBuffers.mDataByteSize
                    guard checkError(AudioFileWritePackets(destinationFileID, false, inNumBytes, outputPacketDescriptions, outputFilePosition, &ioOutputDataPackets, outputBuffer), withError: "AudioFileWritePackets failed!") else {
                        return
                    }
                    
                    print("Convert Output: Write \(ioOutputDataPackets) packets at position \(outputFilePosition), size: \(inNumBytes)")
                    
                    // Advance output file packet position.
                    outputFilePosition += Int64(ioOutputDataPackets)
                    
                    if destinationFormat.mFramesPerPacket != 0 {
                        // The format has constant frames per packet.
                        totalOutputFrames += UInt64(ioOutputDataPackets * destinationFormat.mFramesPerPacket)
                    } else if let outputPacketDescriptions = outputPacketDescriptions {
                        // variable frames per packet require doing this for each packet (adding up the number of sample frames of data in each packet)
                        for i in 0..<Int(ioOutputDataPackets) {
                            totalOutputFrames += UInt64(outputPacketDescriptions[i].mVariableFramesInPacket)
                        }
                    }
                }
            }
            
            
            guard checkError(error, withError: "An Error Occured during the conversion!") else {
                return
            }
            
            // write out any of the leading and trailing frames for compressed formats only
            if destinationFormat.mBitsPerChannel == 0 {
                // our output frame count should jive with
                print("Total number of output frames counted: \(totalOutputFrames)")
                self.writePacketTableInfo(converter: converter, toDestination: destinationFileID)
            }
            
            self.writeCookie(for: destinationFileID, converter: converter)
            
            // Cleanup
            //### See `defer`s in this do-block.
        }
        
        // Set the state to done.
        self.queue.sync {[weak self] in
            self?.state = .done
        }
        
        if error == noErr {
            self.delegate?.audioFileConvertOperation(self, didCompleteWith: self.destinationURL)
        }
        
    }
    
    /*
     Some audio formats have a magic cookie associated with them which is required to decompress audio data
     When converting audio data you must check to see if the format of the data has a magic cookie
     If the audio data format has a magic cookie associated with it, you must add this information to anAudio Converter
     using AudioConverterSetProperty and kAudioConverterDecompressionMagicCookie to appropriately decompress the data
     http://developer.apple.com/mac/library/qa/qa2001/qa1318.html
     */
    private func readCookie(from sourceFileID: AudioFileID, converter: AudioConverterRef) {
        // Grab the cookie from the source file and set it on the converter.
        var cookieSize: UInt32 = 0
        var error = AudioFileGetPropertyInfo(sourceFileID, kAudioFilePropertyMagicCookieData, &cookieSize, nil)
        
        // If there is an error here, then the format doesn't have a cookie - this is perfectly fine as some formats do not.
        guard error == noErr && cookieSize != 0 else {
            return
        }
        var cookie: [CChar] = Array(repeating: 0, count: Int(cookieSize))
        
        error = AudioFileGetProperty(sourceFileID, kAudioFilePropertyMagicCookieData, &cookieSize, &cookie)
        guard error == noErr else {
            print("Could not Get kAudioFilePropertyMagicCookieData from source file!")
            return
        }
        error = AudioConverterSetProperty(converter, kAudioConverterDecompressionMagicCookie, cookieSize, cookie)
        
        if error != noErr {
            print("Could not Set kAudioConverterDecompressionMagicCookie on the Audio Converter!")
        }
        
    }
    
    /*
     Some audio formats have a magic cookie associated with them which is required to decompress audio data
     When converting audio, a magic cookie may be returned by the Audio Converter so that it may be stored along with
     the output data -- This is done so that it may then be passed back to the Audio Converter at a later time as required
     */
    private func writeCookie(for destinationFileID: AudioFileID, converter: AudioConverterRef) {
        // Grab the cookie from the converter and write it to the destination file.
        var cookieSize: UInt32 = 0
        var error = AudioConverterGetPropertyInfo(converter, kAudioConverterCompressionMagicCookie, &cookieSize, nil)
        
        // If there is an error here, then the format doesn't have a cookie - this is perfectly fine as som formats do not.
        guard error == noErr && cookieSize != 0 else {
            return
        }
        var cookie: [CChar] = Array(repeating: 0, count: Int(cookieSize))
        
        error = AudioConverterGetProperty(converter, kAudioConverterCompressionMagicCookie, &cookieSize, &cookie)
        guard error == noErr else {
            print("Could not Get kAudioConverterCompressionMagicCookie from Audio Converter!")
            return
        }
        error = AudioFileSetProperty(destinationFileID, kAudioFilePropertyMagicCookieData, cookieSize, cookie)
        
        if error == noErr {
            print("Writing magic cookie to destination file: \(cookieSize)")
        } else {
            print("Even though some formats have cookies, some files don't take them and that's OK")
        }
        
    }
    
    /*
     Sets the packet table containing information about the number of valid frames in a file and where they begin and end
     for the file types that support this information.
     Calling this function makes sure we write out the priming and remainder details to the destination file
     */
    private func writePacketTableInfo(converter: AudioConverterRef, toDestination destinationFileID: AudioFileID) {
        var isWritable: UInt32 = 0
        var dataSize: UInt32 = 0
        var error = AudioFileGetPropertyInfo(destinationFileID, kAudioFilePropertyPacketTableInfo, &dataSize, &isWritable)
        
        guard error == noErr && isWritable != 0 else {
            print("GetPropertyInfo for kAudioFilePropertyPacketTableInfo error: \(error), isWritable: \(isWritable)")
            return
        }
        var primeInfo = AudioConverterPrimeInfo()
        dataSize = UInt32(MemoryLayout.stride(ofValue: primeInfo))
        
        // retrieve the leadingFrames and trailingFrames information from the converter,
        error = AudioConverterGetProperty(converter, kAudioConverterPrimeInfo, &dataSize, &primeInfo)
        guard error == noErr else {
            print("No kAudioConverterPrimeInfo available and that's OK")
            return
        }
        /* we have some priming information to write out to the destination file
         The total number of packets in the file times the frames per packet (or counting each packet's
         frames individually for a variable frames per packet format) minus mPrimingFrames, minus
         mRemainderFrames, should equal mNumberValidFrames.
         */
        
        var pti = AudioFilePacketTableInfo()
        dataSize = UInt32(MemoryLayout.stride(ofValue: pti))
        error = AudioFileGetProperty(destinationFileID, kAudioFilePropertyPacketTableInfo, &dataSize, &pti)
        guard error == noErr else {
            print("Getting kAudioFilePropertyPacketTableInfo error: \(error)")
            return
        }
        // there's priming to write out to the file
        let totalFrames: Int64 = pti.mNumberValidFrames + Int64(pti.mPrimingFrames + pti.mRemainderFrames) // get the total number of frames from the output file
        print("Total number of frames from output file: \(totalFrames)")
        
        pti.mPrimingFrames = Int32(primeInfo.leadingFrames)
        pti.mRemainderFrames = Int32(primeInfo.trailingFrames)
        pti.mNumberValidFrames = totalFrames - Int64(pti.mPrimingFrames) - Int64(pti.mRemainderFrames)
        
        error = AudioFileSetProperty(destinationFileID, kAudioFilePropertyPacketTableInfo, UInt32(MemoryLayout.stride(ofValue: pti)), &pti)
        guard error == noErr else {
            print("Some audio files can't contain packet table information and that's OK")
            return
        }
        print("Writing packet table information to destination file: \(MemoryLayout.stride(ofValue: pti))")
        print("     Total valid frames: \(pti.mNumberValidFrames)")
        print("         Priming frames: \(pti.mPrimingFrames)")
        print("       Remainder frames: \(pti.mRemainderFrames)\n")
    }
    
    private func writeChannelLayout(converter: AudioConverterRef, source sourceFileID: AudioFileID, destination destinationFileID: AudioFileID) {
        var layoutSize: UInt32 = 0
        var layoutFromConverter = true
        
        var error = AudioConverterGetPropertyInfo(converter, kAudioConverterOutputChannelLayout, &layoutSize, nil)
        
        // if the Audio Converter doesn't have a layout see if the input file does
        if error != noErr || layoutSize == 0 {
            error = AudioFileGetPropertyInfo(sourceFileID, kAudioFilePropertyChannelLayout, &layoutSize,  nil)
            layoutFromConverter = false
        }
        
        guard error == noErr && layoutSize != 0  else {
            return
        }
        var layout: [CChar] = Array(repeating: 0, count: Int(layoutSize))
        
        if layoutFromConverter {
            error = AudioConverterGetProperty(converter, kAudioConverterOutputChannelLayout, &layoutSize, &layout)
            if error != noErr {print("Could not Get kAudioConverterOutputChannelLayout from Audio Converter!")}
        } else {
            error = AudioFileGetProperty(sourceFileID, kAudioFilePropertyChannelLayout, &layoutSize, &layout)
            if error != noErr {print("Could not Get kAudioFilePropertyChannelLayout from source file!")}
        }
        
        guard error == noErr else {
            return
        }
        error = AudioFileSetProperty(destinationFileID, kAudioFilePropertyChannelLayout, layoutSize, layout)
        if error == noErr {
            print("Writing channel layout to destination file: \(layoutSize)")
        } else {
            print("Even though some formats have layouts, some files don't take them and that's OK")
        }
        
    }
    
    private func checkError(_ error: OSStatus, withError string: @autoclosure ()->String) -> Bool{
        if error == noErr {
            return true
        }
        
        let err = NSError(domain: "AudioFileConvertOperationErrorDomain", code: Int(error), userInfo: [NSLocalizedDescriptionKey: string()])
        self.delegate?.audioFileConvertOperation(self, didEncounterError: err)
        
        return false
    }
    
    private func checkIfPausedDueToInterruption() -> Bool {
        var wasInterrupted = false
        
        self.queue.sync {[weak self] in
            assert(self?.state != .done)
            
            while self?.state == .paused {
                self?.semaphore.wait()
                
                wasInterrupted = true
            }
        }
        
        // We must be running or something bad has happened.
        assert(self.state == .running)
        
        return wasInterrupted
    }
    
    // MARK: Notification Handlers.
    
    @objc func handleAudioSessionInterruptionNotification(_ notification: NSNotification) {
        let interruptionType = AVAudioSession.InterruptionType(rawValue: notification.userInfo![AVAudioSessionInterruptionTypeKey] as! UInt)!
        
        print("Session interrupted > --- \(interruptionType == .began ? "Begin Interruption" : "End Interruption") ---")
        
        if interruptionType == .began {
            self.queue.sync {[weak self] in
                if self?.state == .running {
                    self?.state = .paused
                }
            }
        } else {
            
            do {
                
                try AVAudioSession.sharedInstance().setActive(true)
                
            } catch let error {
                NSLog("AVAudioSession setActive failed with error: \(error.localizedDescription)")
            }
            
            
            if self.state == .paused {
                self.semaphore.signal()
            }
            
            self.queue.sync {[weak self] in
                self?.state = .running
            }
        }
    }
    
    static func printAudioStreamBasicDescription(_ asbd: AudioStreamBasicDescription) {
        print(String(format: "Sample Rate:         %10.0f",  asbd.mSampleRate))
        print(String(format: "Format ID:                 \(asbd.mFormatID.fourCharString)"))
        print(String(format: "Format Flags:        %10X",    asbd.mFormatFlags))
        print(String(format: "Bytes per Packet:    %10d",    asbd.mBytesPerPacket))
        print(String(format: "Frames per Packet:   %10d",    asbd.mFramesPerPacket))
        print(String(format: "Bytes per Frame:     %10d",    asbd.mBytesPerFrame))
        print(String(format: "Channels per Frame:  %10d",    asbd.mChannelsPerFrame))
        print(String(format: "Bits per Channel:    %10d",    asbd.mBitsPerChannel))
        print()
    }
    
}
