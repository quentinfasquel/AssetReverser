//
//  ViewController.swift
//  AssetReverserExample
//
//  Created by Quentin on 1/31/17.
//  Copyright © 2017 Quentin Fasquel. All rights reserved.
//

import UIKit
import AVFoundation
import AVKit
import AssetReverser

struct Segues {
    static let playVideo: String = "playVideo"
    static let playReverse: String = "playReverse"
}

class ViewController: UIViewController {

    var videoURL: URL!
    var reversedVideoURL: URL!

    @IBOutlet weak var playReverseButton: UIButton!

    override func viewDidLoad() {
        super.viewDidLoad()

        videoURL = Bundle.main.url(
            forResource: "countdown-sample",
            withExtension: "mp4")!

        reversedVideoURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("countdown-reversed")
            .appendingPathExtension("mp4")
        
        let asset = AVURLAsset(url: videoURL!)
        let reverseSession: AssetReverseSession = AssetReverseSession(asset: asset, outputFileURL: reversedVideoURL)
        reverseSession.reverseAsynchronously { reversedAsset, error in
            guard error == nil else {
                return
            }
            DispatchQueue.main.async {
                self.playReverseButton.isEnabled = true
            }
        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        guard let playerController = segue.destination as? AVPlayerViewController else {
            return
        }

        if segue.identifier == Segues.playVideo {
            playerController.player = AVPlayer(url: videoURL)
        } else if segue.identifier == Segues.playReverse {
            playerController.player = AVPlayer(url: reversedVideoURL)
        }
    }
}

