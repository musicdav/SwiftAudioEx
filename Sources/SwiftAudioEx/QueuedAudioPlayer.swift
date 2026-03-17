//
//  QueuedAudioPlayer.swift
//  SwiftAudio
//
//  Created by Jørgen Henrichsen on 24/03/2018.
//

import Foundation
import MediaPlayer
import CachingPlayerItem

/**
 An audio player that can keep track of a queue of AudioItems.
 */
public class QueuedAudioPlayer: AudioPlayer, QueueManagerDelegate {
    let queue: QueueManager = QueueManager<AudioItem>()
    fileprivate var lastIndex: Int = -1
    fileprivate var lastItem: AudioItem? = nil
    private var pendingForwardTransition = false

    public override init(nowPlayingInfoController: NowPlayingInfoControllerProtocol = NowPlayingInfoController(), remoteCommandController: RemoteCommandController = RemoteCommandController()) {
        super.init(nowPlayingInfoController: nowPlayingInfoController, remoteCommandController: remoteCommandController)
        queue.delegate = self
    }

    /// The repeat mode for the queue player.
    public var repeatMode: RepeatMode = .off
    /// Whether a forward transition should keep the previous track's download alive for reuse.
    /// Set to `false` to cancel the previous track download when switching songs.
    public var continueDownloadingPreviousTrackOnForwardTransition: Bool = false {
        didSet {
            if !continueDownloadingPreviousTrackOnForwardTransition {
                resetPreviousReusableItem()
            }
        }
    }
    public var preloadNextTrackEnabled: Bool = true {
        didSet {
            if preloadNextTrackEnabled {
                if wrapper.playbackActive {
                    preloadNextIfNeeded()
                }
            } else {
                resetPreloading()
            }
        }
    }

    public override var currentItem: AudioItem? {
        queue.current
    }

    /**
     The index of the current item.
     */
    public var currentIndex: Int {
        queue.currentIndex
    }

    override public func clear() {
        queue.clearQueue()
        resetPreloading()
        resetPreviousReusableItem()
        super.clear()
    }

    /**
     All items currently in the queue.
     */
    public var items: [AudioItem] {
        queue.items
    }

    /**
     The previous items held by the queue.
     */
    public var previousItems: [AudioItem] {
        queue.previousItems
    }

    /**
     The upcoming items in the queue.
     */
    public var nextItems: [AudioItem] {
        queue.nextItems
    }

    /**
     Will replace the current item with a new one and load it into the player.

     - parameter item: The AudioItem to replace the current item.
     - parameter playWhenReady: Optional, whether to start playback when the item is ready.
     */
    public override func load(item: AudioItem, playWhenReady: Bool? = nil) {
        handlePlayWhenReady(playWhenReady) {
            queue.replaceCurrentItem(with: item)
        }
    }

    /**
     Add a single item to the queue.

     - parameter item: The item to add.
     - parameter playWhenReady: Optional, whether to start playback when the item is ready.
     */
    public func add(item: AudioItem, playWhenReady: Bool? = nil) {
        handlePlayWhenReady(playWhenReady) {
            queue.add(item)
        }
    }

    /**
     Add items to the queue.

     - parameter items: The items to add to the queue.
     - parameter playWhenReady: Optional, whether to start playback when the item is ready.
     */
    public func add(items: [AudioItem], playWhenReady: Bool? = nil) {
        handlePlayWhenReady(playWhenReady) {
            queue.add(items)
        }
    }

    public func add(items: [AudioItem], at index: Int) throws {
        try queue.add(items, at: index)
    }

    /**
     Step to the next item in the queue.
     */
    public func next() {
        let lastIndex = currentIndex
        let playbackWasActive = wrapper.playbackActive;
        pendingForwardTransition = true
        _ = queue.next(wrap: repeatMode == .queue)
        if lastIndex == currentIndex {
            pendingForwardTransition = false
        }
        if (playbackWasActive && lastIndex != currentIndex || repeatMode == .queue) {
            event.playbackEnd.emit(data: .skippedToNext)
        }
    }

    /**
     Step to the previous item in the queue.
     */
    public func previous() {
        let lastIndex = currentIndex
        let playbackWasActive = wrapper.playbackActive;
        _ = queue.previous(wrap: repeatMode == .queue)
        if (playbackWasActive && lastIndex != currentIndex || repeatMode == .queue) {
            event.playbackEnd.emit(data: .skippedToPrevious)
        }
    }

    /**
     Remove an item from the queue.

     - parameter index: The index of the item to remove.
     - throws: `AudioPlayerError.QueueError`
     */
    public func removeItem(at index: Int) throws {
        try queue.removeItem(at: index)
    }


    /**
     Jump to a certain item in the queue.

     - parameter index: The index of the item to jump to.
     - parameter playWhenReady: Optional, whether to start playback when the item is ready.
     - throws: `AudioPlayerError`
     */
    public func jumpToItem(atIndex index: Int, playWhenReady: Bool? = nil) throws {
        try handlePlayWhenReady(playWhenReady) {
            if (index == currentIndex) {
                seek(to: 0)
            } else {
                _ = try queue.jump(to: index)
            }
            event.playbackEnd.emit(data: .jumpedToIndex)
        }
    }

    /**
     Move an item in the queue from one position to another.

     - parameter fromIndex: The index of the item to move.
     - parameter toIndex: The index to move the item to.
     - throws: `AudioPlayerError.QueueError`
     */
    public func moveItem(fromIndex: Int, toIndex: Int) throws {
        try queue.moveItem(fromIndex: fromIndex, toIndex: toIndex)
    }

    /**
     Remove all upcoming items, those returned by `next()`
     */
    public func removeUpcomingItems() {
        queue.removeUpcomingItems()
    }

    /**
     Remove all previous items, those returned by `previous()`
     */
    public func removePreviousItems() {
        queue.removePreviousItems()
    }

    func replay() {
        seek(to: 0);
        play()
    }

    // MARK: - AVPlayerWrapperDelegate

    override func AVWrapperItemDidPlayToEndTime() {
        event.playbackEnd.emit(data: .playedUntilEnd)
        if (repeatMode == .track) {
            self.pause()

            // quick workaround for race condition - schedule a call after 2 frames
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.016 * 2) { [weak self] in self?.replay() }
        } else if (repeatMode == .queue) {
            let shouldContinuePlaying = playWhenReady
            let lastIndex = currentIndex
            pendingForwardTransition = true
            _ = queue.next(wrap: true)
            if lastIndex == currentIndex {
                pendingForwardTransition = false
            }
            if shouldContinuePlaying && !playWhenReady {
                playWhenReady = true
            }
        } else if (currentIndex != items.count - 1) {
            let shouldContinuePlaying = playWhenReady
            let lastIndex = currentIndex
            pendingForwardTransition = true
            _ = queue.next(wrap: false)
            if lastIndex == currentIndex {
                pendingForwardTransition = false
            }
            if shouldContinuePlaying && !playWhenReady {
                playWhenReady = true
            }
        } else {
            wrapper.state = .ended
        }
    }

    // MARK: - QueueManagerDelegate

    func onCurrentItemChanged() {
        let lastPosition = currentTime;
        let didAdvanceForward = isForwardTransition(from: lastIndex, to: currentIndex)
        if didAdvanceForward,
           continueDownloadingPreviousTrackOnForwardTransition,
           let previousItem = lastItem,
           previousItem.getSourceType() == .stream,
           let wrapper = wrapper as? AVPlayerWrapper,
           let reusableItem = wrapper.takeActiveCachingItemForReuse()
        {
            setPreviousReusableItem(reusableItem, trackId: trackKey(for: previousItem))
        } else if didAdvanceForward {
            resetPreviousReusableItem()
        }

        if let currentItem = currentItem {
            assignReusableItemIfPossible(for: currentItem)
            super.load(item: currentItem)
        } else {
            super.clear()
        }
        event.currentItem.emit(
            data: (
                item: currentItem,
                index: currentIndex == -1 ? nil : currentIndex,
                lastItem: lastItem,
                lastIndex: lastIndex == -1 ? nil : lastIndex,
                lastPosition: lastPosition
            )
        )
        lastItem = currentItem
        lastIndex = currentIndex
        pendingForwardTransition = false
    }

    func onSkippedToSameCurrentItem() {
        pendingForwardTransition = false
        if (wrapper.playbackActive) {
            replay()
        }
    }

    func onReceivedFirstItem() {
        try! queue.jump(to: 0)
    }

    // MARK: - Preload Next
    private var preloadedIdentifier: String?
    private var preloadingItem: CachingPlayerItem?
    private var preloadingTrackId: String?
    private var previousReusableItem: CachingPlayerItem?
    private var previousReusableTrackId: String?

    private func resetPreloading() {
        preloadingItem?.cancelDownload()
        preloadingItem = nil
        preloadedIdentifier = nil
        preloadingTrackId = nil
    }

    private func resetPreviousReusableItem() {
        previousReusableItem?.cancelDownload()
        previousReusableItem = nil
        previousReusableTrackId = nil
    }
    
    private func trackKey(for item: AudioItem) -> String {
        if let id = item.getTrackIdentifier(), !id.isEmpty {
            return id
        }
        if let id = (item as? TrackIdentifiable)?.trackIdentifier(), !id.isEmpty {
            return id
        }
        return item.getSourceUrl()
    }

    override func AVWrapper(didChangeState state: AVPlayerWrapperState) {
        super.AVWrapper(didChangeState: state)
        if state == .playing, preloadNextTrackEnabled {
            preloadNextIfNeeded()
        }
    }

    private func isForwardTransition(from previousIndex: Int, to newIndex: Int) -> Bool {
        Self.shouldTreatAsForwardTransition(
            from: previousIndex,
            to: newIndex,
            pendingForwardTransition: pendingForwardTransition,
            repeatMode: repeatMode,
            itemCount: items.count
        )
    }

    static func shouldTreatAsForwardTransition(
        from previousIndex: Int,
        to newIndex: Int,
        pendingForwardTransition: Bool,
        repeatMode: RepeatMode,
        itemCount: Int
    ) -> Bool {
        guard pendingForwardTransition else { return false }
        guard previousIndex >= 0, newIndex >= 0, previousIndex != newIndex else { return false }
        if newIndex == previousIndex + 1 {
            return true
        }
        return repeatMode == .queue && itemCount > 0 && previousIndex == itemCount - 1 && newIndex == 0
    }

    private func setPreviousReusableItem(_ item: CachingPlayerItem, trackId: String) {
        if let existing = previousReusableItem, existing !== item {
            existing.cancelDownload()
        }
        previousReusableItem = item
        previousReusableTrackId = trackId
    }

    private func assignReusableItemIfPossible(for item: AudioItem) {
        let trackId = trackKey(for: item)
        guard let wrapper = wrapper as? AVPlayerWrapper else { return }

        if trackId == preloadingTrackId, let preloadedItem = preloadingItem {
            wrapper.assignReusableCachingItem(preloadedItem, forTrackId: trackId)
            preloadingItem = nil
            preloadingTrackId = nil
            return
        }

        guard continueDownloadingPreviousTrackOnForwardTransition else {
            resetPreviousReusableItem()
            return
        }

        if trackId == previousReusableTrackId, let previousItem = previousReusableItem {
            wrapper.assignReusableCachingItem(previousItem, forTrackId: trackId)
            previousReusableItem = nil
            previousReusableTrackId = nil
        }
    }

    private func preloadNextIfNeeded() {
        guard preloadNextTrackEnabled else { return }
        guard let nextItem = nextItems.first ?? (repeatMode == .queue ? items.first : nil) else { return }
        guard nextItem.getSourceType() == .stream else { return }

        let urlString = nextItem.getSourceUrl()
        guard let url = URL(string: urlString) else { return }

        let trackId = trackKey(for: nextItem)
        let identifier = trackId
        if preloadedIdentifier == identifier { return }

        let fileExtension = (nextItem as? FileTypeProviding)?.getFileType()
        let resolvedExtension = AudioCacheManager.shared.resolvedFileExtension(for: url, customFileExtension: fileExtension)
        let options = (nextItem as? AssetOptionsProviding)?.getAssetOptions()
        preloadedIdentifier = identifier
        preloadingItem?.cancelDownload()

        // Extract bitrate and duration if available
        let bitrateKbps: Int? = {
            guard let bitrate = (nextItem as? BitrateProviding)?.bitrateKbps, bitrate > 0 else { return nil }
            return bitrate
        }()
        let durationSeconds: Double? = {
            guard let duration = (nextItem as? DurationProviding)?.durationSeconds, duration > 0 else { return nil }
            return duration
        }()

        // Convert Int bitrateKbps to Double for CachingPlayerItem
        let bitrateDouble: Double? = bitrateKbps.map { Double($0) }
        let cachingItem = CachingPlayerItem(
            url: url,
            saveFilePath: AudioCacheManager.shared.fileURL(for: url, trackId: trackId, fileExtension: resolvedExtension).path,
            customFileExtension: resolvedExtension,
            avUrlAssetOptions: options,
            bitrateKbps: bitrateDouble,
            durationSeconds: durationSeconds
        )
        cachingItem.passOnObject = trackId
        if let wrapper = wrapper as? AVPlayerWrapper {
            cachingItem.delegate = wrapper
        }

        preloadingItem = cachingItem
        preloadingTrackId = trackId
        cachingItem.download()
    }
}

#if DEBUG
extension QueuedAudioPlayer {
    var debugPreloadingTrackId: String? { preloadingTrackId }
    var debugPreviousReusableTrackId: String? { previousReusableTrackId }
    var debugPreviousReusableItem: CachingPlayerItem? { previousReusableItem }

    func debugInjectPreloadingItem(_ item: CachingPlayerItem?, trackId: String?, identifier: String? = nil) {
        preloadingItem = item
        preloadingTrackId = trackId
        if let identifier = identifier {
            preloadedIdentifier = identifier
        }
    }

    func debugInjectPreviousReusableItem(_ item: CachingPlayerItem?, trackId: String?) {
        previousReusableItem = item
        previousReusableTrackId = trackId
    }

    func debugAssignReusableItemIfPossible(for item: AudioItem) {
        assignReusableItemIfPossible(for: item)
    }
}
#endif
