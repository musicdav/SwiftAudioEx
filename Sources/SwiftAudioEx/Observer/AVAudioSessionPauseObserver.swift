//
//  AVAudioSessionPauseObserver.swift
//  SwiftAudio
//
//  Created by OpenAI Codex on 14/04/2026.
//

import Foundation
import AVFoundation

protocol AVAudioSessionPauseObserverDelegate: AnyObject {
    func audioSessionInterruptionBegan()
    func audioSessionRouteDidChange(reason: AVAudioSession.RouteChangeReason)
}

final class AVAudioSessionPauseObserver {

    private let notificationCenter: NotificationCenter
    weak var delegate: AVAudioSessionPauseObserverDelegate?

    init(notificationCenter: NotificationCenter = .default) {
        self.notificationCenter = notificationCenter
        startObserving()
    }

    deinit {
        stopObserving()
    }

    private func startObserving() {
        notificationCenter.addObserver(
            self,
            selector: #selector(handleInterruptionNotification(_:)),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(handleRouteChangeNotification(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }

    private func stopObserving() {
        notificationCenter.removeObserver(self)
    }

    @objc private func handleInterruptionNotification(_ notification: Notification) {
        guard
            let userInfo = notification.userInfo,
            let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else {
            return
        }

        if type == .began {
            delegate?.audioSessionInterruptionBegan()
        }
    }

    @objc private func handleRouteChangeNotification(_ notification: Notification) {
        guard
            let userInfo = notification.userInfo,
            let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
            let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue)
        else {
            return
        }

        delegate?.audioSessionRouteDidChange(reason: reason)
    }
}
