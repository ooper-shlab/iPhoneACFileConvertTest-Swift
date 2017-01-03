//
//  stdout+OutputStreamType.swift
//  OOPUtils
//
//  Created by OOPer in cooperation with shlab.jp, on 2016/1/10.
//
//

import Foundation

extension UnsafeMutablePointer: TextOutputStream {
    public func write(_ string: String) {
        if Pointee.self is FILE.Type {
            fputs(string, UnsafeMutableRawPointer(self).assumingMemoryBound(to: FILE.self))
        }
    }
}
