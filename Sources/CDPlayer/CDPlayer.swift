//
//  CDPlayer.swift
//  FoxSchool
//
//  Created by Littlefox iOS Developer on 2022/01/19.
//

import UIKit
import AVKit


public class CDPlayerView: UIView {
    
    deinit {
        print("deinit \(self)")
//        removePlayer()
    }
    
    public enum LoadStatus{
        case start
        case end(isSuccess: Bool, error: Error?)
    }
    
    public typealias PlayerProcessBlock = (LoadStatus) -> ()
    public typealias PlayerBootingProcessBlock = (AVPlayer.Status, Error?) -> ()
    public typealias VideoProcessBlock = (AVPlayerItem.Status, Error?) -> ()
    public typealias VideoLoadedTimeRangesBlock = ([CMTimeRange]) -> ()
    public typealias VideoDurationBlock = (_ duration: Double) -> ()
    public typealias VideoCurrentBlock = (_ currentTime: Double) -> ()
    public typealias VideoRateBlock = (_ rate: Float) -> ()
    public typealias VideoIsLikelyKeepUpBlock = (_ isLikelyKeepUp: Bool) -> ()
    public typealias VideoFinishedBlock = () -> ()
    
    private var _playerProcessBlock: PlayerProcessBlock?
    private var _playerBootingProcessBlock: PlayerBootingProcessBlock?
    private var _videoProcessBlock: VideoProcessBlock?
    private var _videoLoadedTimeRangesBlock: VideoLoadedTimeRangesBlock?
    private var _videoDurationBlock: VideoDurationBlock?
    private var _videoCurrentBlock: VideoCurrentBlock?
    private var _videoRateBlock: VideoRateBlock?
    private var _videoIsLikelyKeepUpBlock: VideoIsLikelyKeepUpBlock?
    private var _videoFinishedBlock: VideoFinishedBlock?
    
    private var statusContext = true
    private var statusItemContext = true
    private var statusKeepUpContext = true
    private var loadedContext = true
    private var durationContext = true
    private var currentTimeContext = true
    private var rateContext = true
    private var playerItemContext = true
    
    private let tPlayerTracksKey = "tracks"
    private let tPlayerPlayableKey = "playable"
    private let tPlayerDurationKey = "duration"
    private let tPlayerRateKey = "rate"
    private let tCurrentItemKey = "currentItem"
    
    private let tPlayerStatusKey = "status"
    private let tPlayerEmptyBufferKey = "playbackBufferEmpty"
    private let tPlaybackBufferFullKey = "playbackBufferFull"
    private let tPlayerKeepUpKey = "playbackLikelyToKeepUp"
    private let tLoadedTimeRangesKey = "loadedTimeRanges"


    public override class var layerClass: Swift.AnyClass {
        AVPlayerLayer.self
    }
    
    private var playerLayer: AVPlayerLayer {
        
        self.layer as! AVPlayerLayer
        
    }
    
    private var player: AVPlayer? {
        get {
            return playerLayer.player
        }
        
        set {
            playerLayer.player = newValue
        }
    }
    
    private var keepingPlayer: AVPlayer = AVPlayer()
    
    private var isCalcurateCurrentTime: Bool = true
    private var timeObserverToken: AnyObject?
    private weak var lastPlayerTimeObserve: AVPlayer?
    private var pictureInPictureController: AVPictureInPictureController?

    var isCanBackgroundPlay: Bool = true
    
    var isReleasePlayer: Bool{
        get{
            if let _ = self.playerLayer.player{
                return false
            }else{
                return true
            }
        }
        
        set{
            if newValue, self.isCanBackgroundPlay{
                self.player = nil
            }else{
                self.player = self.keepingPlayer
                self.play()
            }
        }
    }
    
    
    var isCanPIP: Bool = false{
        didSet{
            if isCanPIP{
                if AVPictureInPictureController.isPictureInPictureSupported(){
                    self.pictureInPictureController = AVPictureInPictureController(playerLayer: self.playerLayer)
                }
            }else{
                self.pictureInPictureController = nil
            }
        }
    }

    var fillMode: CDPlayerViewFillMode! {
        didSet {
            playerLayer.videoGravity = fillMode.AVLayerVideoGravity
        }
    }
    
    var maximumDuration: TimeInterval? {
        get {
            if let playerItem = self.player?.currentItem {
                return CMTimeGetSeconds(playerItem.duration)
            }
            return nil
        }
    }
    
    var currentTime: Double {
        get {
            guard let player = player else {
                return 0
            }
            return CMTimeGetSeconds(player.currentTime())
        }
        set {
            guard let timescale = player?.currentItem?.duration.timescale else {
                return
            }
            let newTime = CMTimeMakeWithSeconds(newValue, preferredTimescale: timescale)
            player!.seek(to: newTime,toleranceBefore: CMTime.zero,toleranceAfter: CMTime.zero)
        }
    }
    
    var interval = CMTimeMake(value: 1, timescale: 60) {
        didSet {
            if rate != 0 {
                addCurrentTimeObserver()
            }
        }
    }
    
    var rate: Float {
        get {
            guard let player = player else {
                return 0
            }
            return player.rate
        }
        set {
            if newValue == 0 {
                removeCurrentTimeObserver()
            } else if rate == 0 && newValue != 0 {
                addCurrentTimeObserver()
                self.isCalcurateCurrentTime = true
            }
            
            player?.rate = newValue
        }
    }
    
    var availableDuration: CMTimeRange {
        let range = self.player?.currentItem?.loadedTimeRanges.first
        if let range = range {
            return range.timeRangeValue
        }
        return CMTimeRange.zero
    }
    
    var url: URL? {
        didSet {
            guard let url = url else {
                return
            }
            self.preparePlayer(url: url)
        }
    }
    
    override public init(frame: CGRect) {
        super.init(frame: frame)
        NotificationCenter.default.addObserver(self, selector: #selector(playerItemDidPlayToEndTime(aNotification:)), name: NSNotification.Name.AVPlayerItemDidPlayToEndTime, object: nil)
    }
    
    convenience public init(){
        self.init(frame: .zero)
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        NotificationCenter.default.addObserver(self, selector: #selector(playerItemDidPlayToEndTime(aNotification:)), name: NSNotification.Name.AVPlayerItemDidPlayToEndTime, object: nil)
    }
    
    private func preparePlayer(url: URL) {
        
        self._playerProcessBlock?(.start)

        let asset = AVURLAsset(url: url)
        let requestKeys : [String] = [tPlayerTracksKey,tPlayerPlayableKey,tPlayerDurationKey]
        asset.loadValuesAsynchronously(forKeys: requestKeys) {
            DispatchQueue.main.async {
                for key in requestKeys{
                    var error: NSError?
                    let status = asset.statusOfValue(forKey: key, error: &error)
                    if status == .failed {
                        self._playerProcessBlock?(.end(isSuccess: false, error: error))
                        return
                    }
                    
                    if asset.isPlayable == false{
                        self._playerProcessBlock?(.end(isSuccess: false, error: error))
                        return
                    }
                }
                
                self.keepingPlayer.replaceCurrentItem(with: AVPlayerItem(asset: asset))
                if self.player == nil{
                    self.player = self.keepingPlayer
                }
                self.player?.currentItem?.audioTimePitchAlgorithm = .timeDomain
                self.addObserversPlayer(avPlayer: self.player!)
                self.addObserversVideoItem(playerItem: self.player!.currentItem!)
                self._playerProcessBlock?(.end(isSuccess: true, error: nil))
            }
        }
    }
    
    private func enableSoundSesstion(){
        do{
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
        }catch{
            
        }
    }
    
    private func addObserversPlayer(avPlayer: AVPlayer) {
        avPlayer.addObserver(self, forKeyPath: tPlayerStatusKey, options: [.new], context: &statusContext)
        avPlayer.addObserver(self, forKeyPath: tPlayerRateKey, options: [.new], context: &rateContext)
        avPlayer.addObserver(self, forKeyPath: tCurrentItemKey, options: [.old,.new], context: &playerItemContext)
    }
    
    private func removeObserversPlayer(avPlayer: AVPlayer) {
        
        avPlayer.removeObserver(self, forKeyPath: tPlayerStatusKey, context: &statusContext)
        avPlayer.removeObserver(self, forKeyPath: tPlayerRateKey, context: &rateContext)
        avPlayer.removeObserver(self, forKeyPath: tCurrentItemKey, context: &playerItemContext)
        
        if let timeObserverToken = timeObserverToken {
            avPlayer.removeTimeObserver(timeObserverToken)
        }
    }
    private func addObserversVideoItem(playerItem: AVPlayerItem) {
        playerItem.addObserver(self, forKeyPath: tLoadedTimeRangesKey, options: [], context: &loadedContext)
        playerItem.addObserver(self, forKeyPath: tPlayerDurationKey, options: [], context: &durationContext)
        playerItem.addObserver(self, forKeyPath: tPlayerStatusKey, options: [], context: &statusItemContext)
        playerItem.addObserver(self, forKeyPath: tPlayerKeepUpKey, options: [.new,.old], context: &statusKeepUpContext)
    }
    private func removeObserversVideoItem(playerItem: AVPlayerItem) {
        
        playerItem.removeObserver(self, forKeyPath: tLoadedTimeRangesKey, context: &loadedContext)
        playerItem.removeObserver(self, forKeyPath: tPlayerDurationKey, context: &durationContext)
        playerItem.removeObserver(self, forKeyPath: tPlayerStatusKey, context: &statusItemContext)
        playerItem.removeObserver(self, forKeyPath: tPlayerKeepUpKey, context: &statusKeepUpContext)
    }
    
    private func removeCurrentTimeObserver() {
        
        if let timeObserverToken = self.timeObserverToken {
            lastPlayerTimeObserve?.removeTimeObserver(timeObserverToken)
        }
        timeObserverToken = nil
    
    }
    
    private func addCurrentTimeObserver() {
        removeCurrentTimeObserver()
        lastPlayerTimeObserve = player
        self.timeObserverToken = player?.addPeriodicTimeObserver(forInterval: interval, queue: DispatchQueue.main) { [weak self] time-> Void in
            if let mySelf = self {
                if mySelf.isCalcurateCurrentTime{
                    self?._videoCurrentBlock?(mySelf.currentTime)
                }
            }
            } as AnyObject?
    }
    
    @objc private func playerItemDidPlayToEndTime(aNotification: NSNotification) {
        self._videoFinishedBlock?()
    }
    
    private func removePlayer() {
        guard let player = player else {
            return
        }
        player.pause()
        
        removeObserversPlayer(avPlayer: player)
        
        if let playerItem = player.currentItem {
            removeObserversVideoItem(playerItem: playerItem)
        }
        
        self.player = nil
        
    }
    
    public override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        
        if context == &statusContext {
            
            guard let avPlayer = player else {
                super.observeValue(forKeyPath: keyPath, of: object, change: change , context: context)
                return
            }
            self._playerBootingProcessBlock?(avPlayer.status, avPlayer.error)
            
        } else if context == &loadedContext {
            
            let playerItem = player?.currentItem
            
            guard let times = playerItem?.loadedTimeRanges else {
                return
            }
            
            let values = times.map({ $0.timeRangeValue})
            self._videoLoadedTimeRangesBlock?(values)
            
        } else if context == &durationContext{
            
            if let currentItem = player?.currentItem {
                self._videoDurationBlock?(currentItem.duration.seconds)
            }
            
        } else if context == &statusItemContext{
            //status of item has changed
            if let currentItem = player?.currentItem {
                self._videoProcessBlock?(currentItem.status, currentItem.error)
            }
            
        } else if context == &rateContext{
            guard let newRateNumber = (change?[NSKeyValueChangeKey.newKey] as? NSNumber) else{
                return
            }
            let newRate = newRateNumber.floatValue
            if newRate == 0 {
                removeCurrentTimeObserver()
            } else {
                addCurrentTimeObserver()
            }
            
            self._videoRateBlock?(newRate)
            
        }else if context == &statusKeepUpContext{
            
            guard let newIsKeppupValue = (change?[NSKeyValueChangeKey.newKey] as? Bool) else{
                return
            }
            
            self._videoIsLikelyKeepUpBlock?(newIsKeppupValue)
            
        } else if context == &playerItemContext{
            guard let oldItem = (change?[NSKeyValueChangeKey.oldKey] as? AVPlayerItem) else{
                return
            }
            removeObserversVideoItem(playerItem: oldItem)
            guard let newItem = (change?[NSKeyValueChangeKey.newKey] as? AVPlayerItem) else{
                return
            }
            addObserversVideoItem(playerItem: newItem)
        } else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change , context: context)
        }
    }
}

public extension CDPlayerView{
    func play(rate: Float = 1) {
        self.rate = rate
    }
    
    func pause() {
        self.isCalcurateCurrentTime = false
        self.rate = 0
    }
    
    func stop() {
        self.currentTime = 0
        self.pause()
    }

    func playFromBeginning() {
        self.currentTime = 0
        self.player?.play()
    }
}

public extension CDPlayerView{
 
    func setPlayerProcessBlock(block: @escaping PlayerProcessBlock){
        self._playerProcessBlock = block
    }
    
    func setPlayerBootingProcessBlock(block: @escaping PlayerBootingProcessBlock){
        self._playerBootingProcessBlock = block
    }
    
    func setVideoProcessBlock(block: @escaping VideoProcessBlock){
        self._videoProcessBlock = block
    }
    
    func setVideoLoadedTimeRangesBlock(block: @escaping VideoLoadedTimeRangesBlock){
        self._videoLoadedTimeRangesBlock = block
    }
    
    func setVideoDurationBlock(block: @escaping VideoDurationBlock){
        self._videoDurationBlock = block
    }
    
    func setVideoCurrentBlock(block: @escaping VideoCurrentBlock){
        self._videoCurrentBlock = block
    }
    
    func setVideoRateBlock(block: @escaping VideoRateBlock){
        self._videoRateBlock = block
    }
    
    func setVideoIsLikelyKeepUpBlock(block: @escaping VideoIsLikelyKeepUpBlock){
        self._videoIsLikelyKeepUpBlock = block
    }
    
    func setVideoFinishedBlock(block: @escaping VideoFinishedBlock){
        self._videoFinishedBlock = block
    }

}
