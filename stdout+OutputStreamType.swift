//
//  stdout+OutputStreamType.swift
//  OOPUtils
//
//  Created by OOPer in cooperation with shlab.jp, on 2016/1/10.
//
//

import Foundation

extension UnsafeMutablePointer: OutputStreamType {
    public func write(string: String) {
        if Memory.self is FILE.Type {
            fputs(string, UnsafeMutablePointer<FILE>(self))
        }
    }
}