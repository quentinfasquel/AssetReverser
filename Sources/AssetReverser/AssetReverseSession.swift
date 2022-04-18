//
//  AssetReverseSession.swift
//  AssetReverser
//
//  Created by Quentin Fasquel on 02/09/2016.
//  Copyright © 2016 Quentin Fasquel. All rights reserved.
//

import AVFoundation
import CoreMedia
import Dispatch

fileprivate let AVAssetTracksKey = "tracks"

public enum AssetReverseSessionStatus: Int {
    case unknown
    case executing
    case cancelling
    case cancelled
    case completed
    case failed
}

@available(iOS 10.0, *)
public class AssetReverseSession {

    // MARK: - Properties

    private let asset: AVAsset
    private let outputFileURL: URL
    private let readStepDuration: CMTime
    private let readWriteQueue: DispatchQueue

    private var assetReader: AVAssetReader!
    private var assetReaderOutput: AVAssetReaderOutput!
    private var assetWriter: AVAssetWriter!
    private var assetWriterInput: AVAssetWriterInput!
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor!
    private var completionHandler: ((AVURLAsset?, Error?) -> (Void))!

    private(set) var error: Error?
    private(set) var status: AssetReverseSessionStatus = .unknown

    // MARK: - Initializers
    
    public required init(asset: AVAsset, outputFileURL: URL) {
        self.asset = asset
        self.outputFileURL = outputFileURL
        self.readWriteQueue = DispatchQueue(label: "AssetReverser.readWrite", qos: .utility)
        self.readStepDuration = CMTime(seconds: 1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
    }

    deinit {
        cancelReverse()
    }
    
    // MARK: - Control Flow

    @available(*, renamed: "reverse()")
    public func reverseAsynchronously(completionHandler: @escaping ((AVURLAsset?, Error?) -> Void)) {
        self.completionHandler = completionHandler
        // Status unknown means `idle`
        guard status == .unknown else {
            fatalError()
        }

        // Start executing
        status = .executing

        // Load asset properties in the background, to avoid blocking the caller with synchronous I/O.
        asset.loadValuesAsynchronously(forKeys: [AVAssetTracksKey]) {
            // If session got cancelled, just return `finish` has already been called
            guard self.status == .executing else {
                return
            }

            self.readWriteQueue.async {
                do {
                    try self.prepareReaderAndWriter()
                    try self.startReading()
                } catch {
                    return self.finish(.failed, error: error)
                }

                // startWriting will then keep on calling `continueReading` until
                // reading is completed.
                self.startWriting()
            }
        }
    }

    @available(iOS 13, *)
    public func reverse() async throws -> AVURLAsset {
        return try await withCheckedThrowingContinuation { continuation in
            reverseAsynchronously { result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let result = result else {
                    fatalError("Expected non-nil result 'result' for nil error")
                }
                continuation.resume(returning: result)
            }
        }
    }
    
    public func cancelReverse() {
        guard status != .cancelled, status != .cancelling, status != .completed else {
            return
        }

        status = .cancelling
        asset.cancelLoading()
        readWriteQueue.async {
            self.assetReader?.cancelReading()
            self.assetWriter?.cancelWriting()
            self.finish(.cancelled)
        }
    }

    private func finish(_ finalStatus: AssetReverseSessionStatus, error: Error? = nil) {
        status = finalStatus

        switch (status) {
        case .completed:
            let reversedAsset = AVURLAsset(url: outputFileURL)
            completionHandler?(reversedAsset, nil)
        case .failed:
            completionHandler?(nil, error)
        case .cancelled:
            // TODO: Remove file?
            break
        default:
            break
        }
    }

    // MARK: -
    
    private func prepareReaderAndWriter() throws {
        // Make sure that the asset tracks loaded successfully.
        var trackLoadingError: NSError?
        guard asset.statusOfValue(forKey: AVAssetTracksKey, error: &trackLoadingError) == .loaded else {
            throw trackLoadingError!
        }

        // Get video track
        guard let videoTrack: AVAssetTrack = asset.tracks(withMediaType: .video).first else {
            // TODO: throw error no video track
            throw NSError()
        }

        assetReader = try AVAssetReader(asset: asset)
        assetReaderOutput = makeReaderOutput(for: videoTrack)
        if assetReader.canAdd(assetReaderOutput) {
            assetReader.add(assetReaderOutput)
        } else {
            throw NSError()
        }

        assetWriter = try AVAssetWriter(outputURL: outputFileURL, fileType: .mp4)
        assetWriterInput = makeWriterInput(for: videoTrack)
        pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: assetWriterInput, sourcePixelBufferAttributes: nil)

        if assetWriter.canAdd(assetWriterInput) {
            assetWriter.add(assetWriterInput)
        } else {
            throw NSError()
        }

        // Remove file if necessary, AVAssetWriter will not overwrite an existing file.
        if (try? outputFileURL.checkResourceIsReachable()) ?? false {
            try FileManager.default.removeItem(at: outputFileURL)
        }

        // Start reading will be performed after a first call to advanceReadingTimeRange()
        // Start writing is executed now to ensure outputFileURL can be written
        guard assetWriter.startWriting() else {
            // `error` is non-nil when startWriting returns false.
            throw assetWriter.error!
        }
    }

    private func makeReaderOutput(for videoTrack: AVAssetTrack) -> AVAssetReaderTrackOutput {
        // Decompress source video to 32ARGB
        let readerSettings: [String: Any] = [
            String(kCVPixelBufferPixelFormatTypeKey): Int(kCVPixelFormatType_32ARGB)]
        let readerOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: readerSettings)
        readerOutput.supportsRandomAccess = true
//        readerOutput.alwaysCopiesSampleData = false
        return readerOutput
    }

    private func makeWriterInput(for videoTrack: AVAssetTrack) -> AVAssetWriterInput {
        let formatHint = videoTrack.formatDescriptions.last as! CMFormatDescription
        let writerSettings: [String: Any] = [
            AVVideoWidthKey: videoTrack.naturalSize.width,
            AVVideoHeightKey: videoTrack.naturalSize.height,
            // Compress modified source frames to H.264.
            AVVideoCodecKey: AVVideoCodecH264,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: videoTrack.estimatedDataRate,
            ],
        ]

        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: writerSettings, sourceFormatHint: formatHint)
        writerInput.expectsMediaDataInRealTime = false
        return writerInput
    }

    // MARK: - Reading & Writing

    private typealias SampleBuffer = (pixelBuffer: CVPixelBuffer, presentationTime: CMTime)
    
    private var readSampleBuffers: [CMSampleBuffer] = []
    private var readingTimeRange: CMTimeRange? = nil
    private var readingIndex: Int = 0
    private var startTime: CMTime? = nil
    private var countFrames: Int64 = 0

    private func advanceReadingTimeRange() -> CMTimeRange? {
        let endTime = readingTimeRange?.start ?? asset.duration
        let readDuration = CMTimeMinimum(readStepDuration, endTime)
        let startTime = CMTimeSubtract(endTime, readDuration)
        let timeRange = CMTimeRange(start: startTime, duration: readDuration)

        readSampleBuffers = []
        readingIndex = 0
        readingTimeRange = timeRange

        guard CMTIMERANGE_IS_EMPTY(timeRange) == false else {
            return nil
        }

        // "assetReader will start reading from \(timeRange.start.seconds) to \(timeRange.end.seconds)"
        return timeRange
    }

    private func copySampleBuffers() {
        // Asynchronously start collecting buffers for current time range
        readWriteQueue.async {
            while let sample = self.assetReaderOutput.copyNextSampleBuffer() {
                self.readSampleBuffers.append(sample)
            }

            // Then start or continue asynchronous writing
            switch self.assetReader.status {
            case .reading, .completed:
                if self.startTime == nil {
                    self.startTime = .zero
                    self.assetWriter.startSession(atSourceTime: self.startTime!)
                    // "assetWriter start session at time \(self.startTime!.seconds)"
                } // else "assetWriter continue writing"
            case .cancelled:
                return
            case .failed:
                return self.finish(.failed, error: self.assetReader.error)
            default:
                fatalError("Unexpected terminal asset reader status: \(self.assetReader.status).")
            }
        }
    }

    private func startReading() throws {
        guard readingTimeRange == nil, let startReadingTimeRange = advanceReadingTimeRange() else {
            // TODO: throw error nothing to read
            return
        }

        // Start reading from a specific time range
        assetReader.timeRange = startReadingTimeRange
        guard assetReader.startReading() else {
            throw assetReader.error!
        }

        copySampleBuffers()
    }
    
    private func continueReading() {
        guard let nextReadingTimeRange = advanceReadingTimeRange() else {
            // If there isn't anything to read, marking assetReaderOutput as final
            // will set assetReader.status to .completed
            assetReaderOutput.markConfigurationAsFinal()
            return
        }

        // Continue reading with a new time range
        let timeRangeValue = NSValue(timeRange: nextReadingTimeRange)
        assetReaderOutput.reset(forReadingTimeRanges: [timeRangeValue])

        copySampleBuffers()
    }

    private func fetchNextSampleBuffer() -> SampleBuffer? {
        guard status != .cancelled else {
            return nil
        }
        guard readingIndex < readSampleBuffers.count else {
            return nil
        }
        let reverseSample = readSampleBuffers[readSampleBuffers.count - readingIndex - 1]
        let pixelBuffer = CMSampleBufferGetImageBuffer(reverseSample)!
        let timeScale = CMTimeScale(30) //assetWriterInput.mediaTimeScale
        let presentationTime = CMTime(value: countFrames, timescale: timeScale)
        // Increment reading index
        readingIndex = readingIndex + 1
        countFrames = countFrames + 1
        return (pixelBuffer, presentationTime)
    }

    private func startWriting() {
        assetWriterInput.requestMediaDataWhenReady(on: readWriteQueue) {
            // Start writing (called only after first async block is finished)
            while self.assetWriterInput.isReadyForMoreMediaData && self.assetWriter.status == .writing {
                guard let (pixelBuffer, sampleTime) = self.fetchNextSampleBuffer() else {
                    switch self.assetReader.status {
                    case .reading:
                        self.continueReading()
                    case .completed:
                        self.finishWriting()
                    default:
                        fatalError("Unexpected asset reader status: \(self.assetReader.status)")
                    }
                    break
                }
                //
                self.pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: sampleTime)
            }
        }
    }

    private func finishWriting() {
        assetWriterInput.markAsFinished()
        assetWriter.finishWriting {
            switch self.assetWriter.status {
            case .completed:
                self.finish(.completed)
            case .failed:
                self.finish(.failed, error: self.assetWriter.error)
            case .cancelled:
                break // cancel() has been called
            default:
                fatalError("Unexpected terminal asset writer status: \(self.assetWriter.status).")
            }
        }
    }
}
