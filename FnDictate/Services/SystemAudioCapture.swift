import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

/// Captures system audio via ScreenCaptureKit when Screen Recording is granted.
final class SystemAudioCapture: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private var stream: SCStream?
    var onBuffer: ((AVAudioPCMBuffer) -> Void)?
    /// Normalized 0...1 peak level for remote (Others) UI waveform.
    var onLevel: ((Float) -> Void)?

    func start() async throws {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw SystemAudioError.permissionDenied
        }
        guard let display = content.displays.first else {
            throw SystemAudioError.noDisplay
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48_000
        config.channelCount = 1
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        config.showsCursor = false

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: DispatchQueue(label: "fn.dictate.system-audio"))
        try await stream.startCapture()
        self.stream = stream
    }

    func stop() async {
        guard let stream else { return }
        try? await stream.stopCapture()
        self.stream = nil
        onLevel?(0)
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        guard let buffer = Self.makePCMBuffer(from: sampleBuffer) else { return }
        onBuffer?(buffer)
        if let level = AudioLevel.normalized(from: buffer) {
            onLevel?(level)
        }
    }

    private static func makePCMBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else { return nil }
        guard var asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)?.pointee else {
            return nil
        }
        guard let format = AVAudioFormat(streamDescription: &asbd) else { return nil }

        let numSamples = CMSampleBufferGetNumSamples(sampleBuffer)
        guard numSamples > 0 else { return nil }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(numSamples)) else {
            return nil
        }
        buffer.frameLength = AVAudioFrameCount(numSamples)

        var blockBuffer: CMBlockBuffer?
        var audioBufferList = AudioBufferList()
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: &audioBufferList,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else { return nil }

        let ablPointer = UnsafeMutableAudioBufferListPointer(&audioBufferList)
        guard let source = ablPointer.first?.mData else { return nil }
        let byteCount = Int(ablPointer.first?.mDataByteSize ?? 0)

        if format.isInterleaved {
            if let dest = buffer.floatChannelData?[0] {
                memcpy(
                    dest,
                    source,
                    min(byteCount, Int(buffer.frameCapacity) * Int(format.streamDescription.pointee.mBytesPerFrame))
                )
            } else if let dest = buffer.int16ChannelData?[0] {
                memcpy(
                    dest,
                    source,
                    min(byteCount, Int(buffer.frameCapacity) * Int(format.streamDescription.pointee.mBytesPerFrame))
                )
            }
        } else if let channelData = buffer.floatChannelData {
            let channels = Int(format.channelCount)
            for channel in 0..<min(channels, ablPointer.count) {
                guard let src = ablPointer[channel].mData else { continue }
                memcpy(channelData[channel], src, Int(ablPointer[channel].mDataByteSize))
            }
        }

        return buffer
    }

    enum SystemAudioError: LocalizedError {
        case noDisplay
        case permissionDenied

        var errorDescription: String? {
            switch self {
            case .noDisplay:
                return "No display available for system audio capture."
            case .permissionDenied:
                return "Screen Recording permission denied. Enable Fn Dictate in System Settings, then quit and relaunch."
            }
        }
    }
}
