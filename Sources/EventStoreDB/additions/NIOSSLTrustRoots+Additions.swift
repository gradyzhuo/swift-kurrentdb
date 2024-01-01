//
//  File.swift
//  
//
//  Created by 卓俊諺 on 2024/1/1.
//

import Foundation
import NIOCore
import NIOPosix
import NIOSSL

extension NIOSSLTrustRoots{
    public static func fileInBundle(forResource resourceName: String, withExtension extenionName: String, inBundle bundle: Bundle = .main)->Self?{
        
        guard let resourcePath = bundle.path(forResource: resourceName, ofType: extenionName) else {
            return nil
        }
        return .file(resourcePath)
    }
    
    public static func crtInBundle(_ fileName: String, inBundle bundle: Bundle = .main)->Self? {
        return .fileInBundle(forResource: fileName, withExtension: "crt", inBundle: bundle)
    }
    public static func pemInBundle(_ fileName: String, inBundle bundle: Bundle = .main)->Self? {
        return .fileInBundle(forResource: fileName, withExtension: "pem", inBundle: bundle)
    }
}
