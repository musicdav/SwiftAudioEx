#!/usr/bin/env swift

import Foundation
import AVFoundation

/// Diagnostic script to observe AVPlayer behavior with the problematic FLAC file.
/// Runs standalone without any dependencies.

let flacPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "\(FileManager.default.currentDirectoryPath)/Tests/SwiftAudioExTests/Resources/Cornfield Chase.flac"

guard FileManager.default.fileExists(atPath: flacPath) else {
    print("ERROR: File not found at \(flacPath)")
    exit(1)
}

let url = URL(fileURLWithPath: flacPath)
let asset = AVURLAsset(url: url)
let item = AVPlayerItem(asset: asset)
let player = AVPlayer(playerItem: item)
player.volume = 0.0

class Observer: NSObject {
    let player: AVPlayer
    let item: AVPlayerItem
    var statusObs: NSKeyValueObservation?
    var itemStatusObs: NSKeyValueObservation?
    var timeObserverToken: Any?
    var endTimeToken: NSObjectProtocol?
    var failToken: NSObjectProtocol?
    var stalledToken: NSObjectProtocol?
    var didEnd = false
    var didPause = false
    var events: [(String, Double, Double)] = []
    
    init(player: AVPlayer, item: AVPlayerItem) {
        self.player = player
        self.item = item
        super.init()
    }
    
    func startObserving() {
        // Observe timeControlStatus
        statusObs = player.observe(\.timeControlStatus, options: [.new, .old]) { [weak self] p, change in
            guard let self = self else { return }
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
            
            self.events.append((statusStr, ct, dur))
            
            if newStatus == .paused && ct > 121 {
                self.didPause = true
            }
        }
        
        // Observe item status
        itemStatusObs = item.observe(\.status, options: [.new]) { item, _ in
            print("[DIAG] item.status → \(item.status.rawValue) (0=unknown, 1=readyToPlay, 2=failed)")
            if let error = item.error {
                print("[DIAG] item.error: \(error)")
            }
        }
        
        // Observe end time notification
        endTimeToken = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            let ct = self.player.currentTime().seconds
            let dur = self.player.currentItem?.duration.seconds ?? -1
            print("\n[DIAG] *** AVPlayerItemDidPlayToEndTime ***")
            print("       currentTime: \(ct)")
            print("       item.duration: \(dur)")
            self.didEnd = true
        }
        
        // Observe failure
        failToken = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            let ct = self.player.currentTime().seconds
            print("\n[DIAG] *** AVPlayerItemFailedToPlayToEndTime ***")
            print("       currentTime: \(ct)")
        }
        
        // Observe stalled
        stalledToken = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            let ct = self.player.currentTime().seconds
            print("\n[DIAG] *** AVPlayerItemPlaybackStalled ***")
            print("       currentTime: \(ct)")
        }
        
        // Periodic time observer
        let interval = CMTime(seconds: 0.1, preferredTimescale: 1000)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            let ct = time.seconds
            let dur = self.player.currentItem?.duration.seconds ?? -1
            if ct > 120 {
                print("[DIAG] time: \(String(format: "%.3f", ct)) / \(String(format: "%.3f", dur))  rate=\(self.player.rate)  bufEmpty=\(self.player.currentItem?.isPlaybackBufferEmpty ?? false)  likelyKeepUp=\(self.player.currentItem?.isPlaybackLikelyToKeepUp ?? false)  bufFull=\(self.player.currentItem?.isPlaybackBufferFull ?? false)")
            }
        }
    }
    
    func printSummary() {
        print("\n[DIAG] === SUMMARY ===")
        print("[DIAG] Total events: \(events.count)")
        for (i, event) in events.enumerated() {
            print("[DIAG]   Event \(i): \(event.0) at currentTime=\(String(format: "%.3f", event.1)) duration=\(String(format: "%.3f", event.2))")
        }
        print("[DIAG] Final currentTime: \(player.currentTime().seconds)")
        print("[DIAG] Final item.duration: \(item.duration.seconds)")
        print("[DIAG] Final asset.duration: \(asset.duration.seconds)")
        print("[DIAG] Final player.rate: \(player.rate)")
        print("[DIAG] Final timeControlStatus: \(player.timeControlStatus.rawValue)")
        print("[DIAG] itemDidPlayToEndTime fired: \(didEnd)")
        print("[DIAG] timeControlStatus paused near end: \(didPause)")
    }
}

let observer = Observer(player: player, item: item)
observer.startObserving()

print("[DIAG] === Loading FLAC file: \(flacPath) ===")

// Wait for item to be ready
var ready = false
let readyObs = item.observe(\.status) { item, _ in
    if item.status == .readyToPlay {
        ready = true
    }
}

// Run loop until ready
let startTime = Date()
while !ready && Date().timeIntervalSince(startTime) < 10 {
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
}

guard ready else {
    print("ERROR: Item never became ready")
    exit(1)
}

print("[DIAG] === Item ready ===")
print("[DIAG] item.duration: \(item.duration.seconds)")
print("[DIAG] asset.duration: \(asset.duration.seconds)")

// Seek to 120s
print("[DIAG] === Seeking to 120s ===")
var seekDone = false
player.seek(to: CMTime(seconds: 120, preferredTimescale: 1000), toleranceBefore: .zero, toleranceAfter: .zero) { finished in
    print("[DIAG] Seek finished: \(finished)")
    seekDone = true
}

while !seekDone {
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
}

// Start playback
print("[DIAG] === Starting playback from ~120s ===")
player.rate = 1.0

// Wait until either endTime fires, pause detected, or 15s timeout
let playStart = Date()
while !observer.didEnd && !observer.didPause && Date().timeIntervalSince(playStart) < 15 {
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
}

// Wait 3 more seconds after pause to see if endTime fires
if observer.didPause && !observer.didEnd {
    print("[DIAG] === Paused detected, waiting 3s more for endTime notification ===")
    let waitStart = Date()
    while !observer.didEnd && Date().timeIntervalSince(waitStart) < 3 {
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    }
}

observer.printSummary()
readyObs.invalidate()
exit(0)
