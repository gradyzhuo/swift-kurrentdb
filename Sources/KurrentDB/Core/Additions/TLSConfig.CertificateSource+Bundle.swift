//
//  TLSConfig.CertificateSource+Bundle.swift
//  KurrentCore
//
//  Created by Grady Zhuo on 2024/1/1.
//

import Foundation
import GRPCNIOTransportCore

extension TLSConfig.CertificateSource {
    static func fileInBundle(forResource resourceName: String, withExtension extenionName: String, format: TLSConfig.SerializationFormat, inDirectory directory: String? = nil, inBundle bundle: Bundle = .main) -> Self? {
        guard let resourcePath = bundle.path(forResource: resourceName, ofType: extenionName, inDirectory: directory) else {
            return nil
        }
        return .file(path: resourcePath, format: format)
    }

    public static func crtInBundle(_ fileName: String, inDirectory directory: String? = nil, inBundle bundle: Bundle = .main) -> Self? {
        .fileInBundle(forResource: fileName, withExtension: "crt", format: .pem, inDirectory: directory, inBundle: bundle)
    }

    public static func pemInBundle(_ fileName: String, inDirectory directory: String? = nil, inBundle bundle: Bundle = .main) -> Self? {
        .fileInBundle(forResource: fileName, withExtension: "pem", format: .pem, inDirectory: directory, inBundle: bundle)
    }
}
