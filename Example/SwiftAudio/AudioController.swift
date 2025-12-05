//
//  AudioController.swift
//  SwiftAudio_Example
//
//  Created by Jørgen Henrichsen on 25/03/2018.
//  Copyright © 2018 CocoaPods. All rights reserved.
//

import Foundation
import SwiftAudioEx

class AudioController {
    
    static let shared = AudioController()
    let player: QueuedAudioPlayer
    
    let sources: [AudioItem] = [
        DefaultAudioItem(
            audioUrl: "https://alist.ecust.space/navidrome/rest/stream?u=admin&t=6fdf5e49cd781eda0352e613ec11e911&s=4e713f&f=json&v=1.8.0&c=NavidromeUI&id=lmQhizIVVHW9Wwtyet1yaG&_=1764637250453",
            artist: "Navidrome",
            title: "Track 1 (FLAC)",
            sourceType: .stream,
            artwork: #imageLiteral(resourceName: "22AMI"),
            fileType: "flac"
        ),
        DefaultAudioItem(
            audioUrl: "https://alist.ecust.space/navidrome/rest/stream?u=admin&t=6fdf5e49cd781eda0352e613ec11e911&s=4e713f&f=json&v=1.8.0&c=NavidromeUI&id=wAXeStS2XpEyxloQsc5um2&_=1764637250453",
            artist: "Navidrome",
            title: "Track 2 (FLAC)",
            sourceType: .stream,
            artwork: #imageLiteral(resourceName: "cover"),
            fileType: "flac"
        ),
        DefaultAudioItem(
            audioUrl: "https://alist.ecust.space/navidrome/rest/stream?u=admin&t=6fdf5e49cd781eda0352e613ec11e911&s=4e713f&f=json&v=1.8.0&c=NavidromeUI&id=EXR7OJCSAaPrVtPn9j3Q2z&_=1764637250453",
            artist: "Navidrome",
            title: "Track 3 (FLAC)",
            sourceType: .stream,
            artwork: #imageLiteral(resourceName: "22AMI"),
            fileType: "flac"
        ),
    ]
    
    init() {
        let controller = RemoteCommandController()
        player = QueuedAudioPlayer(remoteCommandController: controller)
        player.remoteCommands = [
            .stop,
            .play,
            .pause,
            .togglePlayPause,
            .next,
            .previous,
            .changePlaybackPosition
        ]
        player.progressiveDownload = true
       
        player.repeatMode = .queue
        DispatchQueue.main.async {
            self.player.add(items: self.sources)
        }
    }
    
}
