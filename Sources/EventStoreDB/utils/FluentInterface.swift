////
////  FluentInterface.swift
////
////
////  Created by Grady Zhuo on 2023/12/27.
////
//
// import Foundation
//
//// reference: https://www.appcoda.com.tw/fluent-interface/
// @dynamicMemberLookup
// public struct FluentInterface<Subject> {
//    public let subject: Subject
//
//    // 因為要動到 subject 的屬性，所以 keyPath 的型別必須是 WritableKeyPath
//    // 回傳值是一個 Setter 方法
//
//    public subscript<Value>(dynamicMember keyPath: WritableKeyPath<Subject, Value>) -> ((Value) -> FluentInterface<Subject>) {
//        // 因為在要回傳的 Setter 方法裡不能更改 self，所以要把 subject 從 self 取出來用
//        var subject = self.subject
//
//        // subject 實體的 Setter 方法
//        return { value in
//
//            // 把 value 指派給 subject 的屬性
//            subject[keyPath: keyPath] = value
//
//            // 回傳的型別是 FluentInterface<Subject> 而不是 Subject
//            // 因為現在的流暢界面是用 FluentInterface 型別來串，而不是 Subject 本身
//            return FluentInterface(subject: subject)
//        }
//    }
// }
