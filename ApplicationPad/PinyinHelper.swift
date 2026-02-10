//
//  PinyinHelper.swift
//  ApplicationPad
//
//  Created by Jin, Kris on 2026/2/10.
//

import Foundation

/// 获取完整拼音 (网易有道词典 -> wangyiyoudaocidian)
func pinyin(_ string: String) -> String {
    let mutable = NSMutableString(string: string) as CFMutableString
    CFStringTransform(mutable, nil, kCFStringTransformToLatin, false)
    CFStringTransform(mutable, nil, kCFStringTransformStripDiacritics, false)
    return (mutable as String).replacingOccurrences(of: " ", with: "")
}

/// 获取拼音首字母 (网易有道词典 -> wyydcd)
func pinyinInitials(_ string: String) -> String {
    let mutable = NSMutableString(string: string) as CFMutableString
    CFStringTransform(mutable, nil, kCFStringTransformToLatin, false)
    CFStringTransform(mutable, nil, kCFStringTransformStripDiacritics, false)

    let pinyin = mutable as String
    // Split by space to get each character's pinyin, then take first letter
    let initials = pinyin.split(separator: " ").compactMap { $0.first }.map { String($0) }.joined()
    return initials
}
