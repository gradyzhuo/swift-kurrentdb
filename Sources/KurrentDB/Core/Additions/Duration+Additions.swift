//
//  Duration+Additions.swift
//  KurrentDB
//

import Foundation

extension Duration {
    /// Converts the `Duration` to a `TimeInterval` (seconds as a `Double`).
    var timeInterval: TimeInterval {
        let components = self.components
        return Double(components.seconds) + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }
}
