//
//  Item.swift
//  SoundAnchor
//
//  Created by Flavio De Stefano on 1/24/25.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
