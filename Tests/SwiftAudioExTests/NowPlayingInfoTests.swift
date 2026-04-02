import XCTest
import MediaPlayer
@testable import SwiftAudioEx

class NowPlayingInfoTests: XCTestCase {

    var audioPlayer: AudioPlayer!
    var nowPlayingController: NowPlayingInfoController_Mock!

    override func setUp() {
        super.setUp()
        nowPlayingController = NowPlayingInfoController_Mock()
        audioPlayer = AudioPlayer(nowPlayingInfoController: nowPlayingController)
        audioPlayer.automaticallyUpdateNowPlayingInfo = true
        audioPlayer.volume = 0
    }

    override func tearDown() {
        audioPlayer = nil
        nowPlayingController = nil
        super.tearDown()
    }

    func testNowPlayingInfoControllerMetadataUpdate() {
        let item = Source.getAudioItem()
        audioPlayer.load(item: item, playWhenReady: false)

        XCTAssertEqual(nowPlayingController.getTitle(), item.getTitle())
        XCTAssertEqual(nowPlayingController.getArtist(), item.getArtist())
        XCTAssertEqual(nowPlayingController.getAlbumTitle(), item.getAlbumTitle())
        XCTAssertNotNil(nowPlayingController.getArtwork())
    }

    func testNowPlayingInfoControllerPlaybackValuesUpdate() {
        let item = LongSource.getAudioItem()
        audioPlayer.load(item: item, playWhenReady: true)

        XCTAssertNotNil(nowPlayingController.getRate())
        XCTAssertNotNil(nowPlayingController.getDuration())
        XCTAssertNotNil(nowPlayingController.getCurrentTime())
    }

    func testNowPlayingPlaybackValuesUpdatedOnlyWhenDurationChanges() {
        let initialCallCount = nowPlayingController.setKeyValuesCallCount

        audioPlayer.AVWrapper(didUpdateDuration: 120)
        let firstUpdateCallCount = nowPlayingController.setKeyValuesCallCount
        XCTAssertEqual(firstUpdateCallCount, initialCallCount + 1)

        audioPlayer.AVWrapper(didUpdateDuration: 120)
        XCTAssertEqual(nowPlayingController.setKeyValuesCallCount, firstUpdateCallCount)

        audioPlayer.AVWrapper(didUpdateDuration: 121)
        XCTAssertEqual(nowPlayingController.setKeyValuesCallCount, firstUpdateCallCount + 1)
    }
}
