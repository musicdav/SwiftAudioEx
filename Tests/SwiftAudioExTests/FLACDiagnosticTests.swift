import AVFoundation
import XCTest
@testable import SwiftAudioEx

/// Diagnostic test to observe AVPlayer behavior with the problematic FLAC file.
/// This test seeks near the end and logs all state transitions, durations, and
/// whether itemDidPlayToEndTime fires.
class FLACDiagnosticTests: XCTestCase {

    func testFLACPlaybackEndBehavior() {
        let path = Bundle.module.path(forResource: "Cornfield Chase", ofType: "flac")!
        let url = URL(fileURLWithPath: path)

        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)
        player.volume = 0.0

        // Track all events
        var events: [(String, Double, Double)] = [] // (event, currentTime, duration)
        let endTimeExpectation = XCTestExpectation(description: "itemDidPlayToEndTime should fire")
        let pauseExpectation = XCTestExpectation(description: "timeControlStatus changed to paused")
        pauseExpectation.isInverted = false

        // Observe timeControlStatus
        var statusObservation: NSKeyValueObservation?
        statusObservation = player.observe(\.timeControlStatus, options: [.new, .old]) { p, change in
            let ct = p.currentTime().seconds
            let dur = p.currentItem?.duration.seconds ?? -1
            let assetDur = p.currentItem?.asset.duration.seconds ?? -1
            let seekable = p.currentItem?.seekableTimeRanges.last?.timeRangeValue.duration.seconds ?? -1
            let loaded = p.currentItem?.loadedTimeRanges.last?.timeRangeValue.end.seconds ?? -1
            let bufferEmpty = p.currentItem?.isPlaybackBufferEmpty ?? false
            let bufferFull = p.currentItem?.isPlaybackBufferFull ?? false
            let likelyToKeepUp = p.currentItem?.isPlaybackLikelyToKeepUp ?? false

            let newStatus = change.newValue ?? .paused
            let statusStr: String
            switch newStatus {
            case .paused: statusStr = "PAUSED"
            case .playing: statusStr = "PLAYING"
            case .waitingToPlayAtSpecifiedRate: statusStr = "WAITING"
            @unknown default: statusStr = "UNKNOWN"
            }

            print("[DIAG] timeControlStatus → \(statusStr)")
            print("       currentTime: \(ct)")
            print("       item.duration: \(dur)")
            print("       asset.duration: \(assetDur)")
            print("       seekable.duration: \(seekable)")
            print("       loaded.end: \(loaded)")
            print("       bufferEmpty: \(bufferEmpty)")
            print("       bufferFull: \(bufferFull)")
            print("       likelyToKeepUp: \(likelyToKeepUp)")
            print("       player.rate: \(p.rate)")
            print("       reasonForWaiting: \(String(describing: p.reasonForWaitingToPlay))")

            events.append((statusStr, ct, dur))

            if newStatus == .paused && ct > 100 {
                pauseExpectation.fulfill()
            }
        }

        // Observe item status
        var itemStatusObservation: NSKeyValueObservation?
        itemStatusObservation = item.observe(\.status, options: [.new]) { item, _ in
            print("[DIAG] item.status → \(item.status.rawValue) (0=unknown, 1=readyToPlay, 2=failed)")
            if let error = item.error {
                print("[DIAG] item.error: \(error)")
            }
        }

        // Observe itemDidPlayToEndTime notification
        var notifToken: NSObjectProtocol?
        notifToken = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { notif in
            let ct = player.currentTime().seconds
            let dur = player.currentItem?.duration.seconds ?? -1
            print("[DIAG] *** AVPlayerItemDidPlayToEndTime ***")
            print("       currentTime: \(ct)")
            print("       item.duration: \(dur)")
            endTimeExpectation.fulfill()
        }

        // Observe itemFailedToPlayToEndTime
        var failToken: NSObjectProtocol?
        failToken = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { notif in
            let ct = player.currentTime().seconds
            print("[DIAG] *** AVPlayerItemFailedToPlayToEndTime ***")
            print("       currentTime: \(ct)")
            if let error = notif.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error {
                print("       error: \(error)")
            }
        }

        // Observe playback stalled
        var stalledToken: NSObjectProtocol?
        stalledToken = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: item,
            queue: .main
        ) { _ in
            let ct = player.currentTime().seconds
            print("[DIAG] *** AVPlayerItemPlaybackStalled ***")
            print("       currentTime: \(ct)")
        }

        // Add periodic time observer to track progress near the end
        let interval = CMTime(seconds: 0.1, preferredTimescale: 1000)
        var timeObserverToken: Any?
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            let ct = time.seconds
            let dur = player.currentItem?.duration.seconds ?? -1
            if ct > 120 { // Only log last ~7 seconds
                print("[DIAG] time: \(String(format: "%.3f", ct)) / \(String(format: "%.3f", dur))  rate=\(player.rate)  bufEmpty=\(player.currentItem?.isPlaybackBufferEmpty ?? false)  likelyKeepUp=\(player.currentItem?.isPlaybackLikelyToKeepUp ?? false)")
            }
        }

        // Wait for item to be ready, then seek near end and play
        let readyExpectation = XCTestExpectation(description: "item ready to play")
        var readyObservation: NSKeyValueObservation?
        readyObservation = item.observe(\.status) { item, _ in
            if item.status == .readyToPlay {
                readyExpectation.fulfill()
            }
        }

        wait(for: [readyExpectation], timeout: 10)
        
        print("[DIAG] === Item ready, seeking to 120s and playing ===")
        print("[DIAG] item.duration: \(item.duration.seconds)")
        print("[DIAG] asset.duration: \(asset.duration.seconds)")

        // Seek to 120s (about 7 seconds before reported end)
        let seekExpectation = XCTestExpectation(description: "seek completed")
        player.seek(to: CMTime(seconds: 120, preferredTimescale: 1000), toleranceBefore: .zero, toleranceAfter: .zero) { finished in
            print("[DIAG] Seek to 120s finished: \(finished)")
            seekExpectation.fulfill()
        }
        wait(for: [seekExpectation], timeout: 10)

        // Start playback
        player.rate = 1.0
        print("[DIAG] === Started playback from ~120s ===")

        // Wait for either endTime or pause - give it 15 seconds max
        wait(for: [pauseExpectation], timeout: 15)

        // Wait a bit more to see if endTime fires after pause
        let postPauseWait = XCTestExpectation(description: "post-pause wait")
        postPauseWait.isInverted = true
        wait(for: [postPauseWait], timeout: 3)

        // Print summary
        print("\n[DIAG] === SUMMARY ===")
        print("[DIAG] Total events recorded: \(events.count)")
        for (i, event) in events.enumerated() {
            print("[DIAG] Event \(i): \(event.0) at currentTime=\(String(format: "%.3f", event.1)) duration=\(String(format: "%.3f", event.2))")
        }
        print("[DIAG] Final currentTime: \(player.currentTime().seconds)")
        print("[DIAG] Final item.duration: \(item.duration.seconds)")
        print("[DIAG] Final asset.duration: \(asset.duration.seconds)")
        print("[DIAG] Final player.rate: \(player.rate)")
        print("[DIAG] Final timeControlStatus: \(player.timeControlStatus.rawValue)")

        // Cleanup
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
        }
        statusObservation?.invalidate()
        itemStatusObservation?.invalidate()
        readyObservation?.invalidate()
        if let token = notifToken {
            NotificationCenter.default.removeObserver(token)
        }
        if let token = failToken {
            NotificationCenter.default.removeObserver(token)
        }
        if let token = stalledToken {
            NotificationCenter.default.removeObserver(token)
        }
    }
}
