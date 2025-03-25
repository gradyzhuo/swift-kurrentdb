//
//  Cursor+Additions.swift
//  KurrentStreams
//
//  Created by 卓俊諺 on 2025/1/24.
//

extension Cursor where Pointer == CursorPointer {
    var direction: Direction {
        switch self {
        case .start:
            .forward
        case .end:
            .backward
        case let .specified(pointer):
            pointer.direction
        }
    }
}
