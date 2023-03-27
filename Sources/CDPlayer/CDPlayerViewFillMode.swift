//
//  File.swift
//  
//
//  Created by Chando Park on 2023/03/27.
//

import Foundation
import AVKit

public enum CDPlayerViewFillMode {
    case resizeAspect
    case resizeAspectFill
    case resize
    
    init?(videoGravity: AVLayerVideoGravity){
        switch videoGravity {
        case .resizeAspect:
            self = .resizeAspect
        case .resizeAspectFill:
            self = .resizeAspectFill
        case .resize:
            self = .resize
        default:
            return nil
        }
    }
    
    var AVLayerVideoGravity: AVLayerVideoGravity {
        get {
            switch self {
            case .resizeAspect:
                return .resizeAspect
            case .resizeAspectFill:
                return .resizeAspectFill
            case .resize:
                return .resize
            }
        }
    }
}
