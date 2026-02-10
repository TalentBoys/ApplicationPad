//
//  PinyinHelper.swift
//  ApplicationPad
//
//  Created by Jin, Kris on 2026/2/10.
//

import Foundation

func pinyin(_ string: String) -> String {
    let mutable = NSMutableString(string: string) as CFMutableString
    CFStringTransform(mutable, nil, kCFStringTransformToLatin, false)
    CFStringTransform(mutable, nil, kCFStringTransformStripDiacritics, false)
    return (mutable as String).replacingOccurrences(of: " ", with: "")
}
