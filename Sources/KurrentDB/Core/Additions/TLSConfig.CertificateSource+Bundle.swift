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
        return bundle.path(forResource: resourceName, ofType: extenionName, inDirectory: directory).map{
            .file(path: $0, format: format)
        }
    }

    public static func crtInBundle(_ fileName: String, format: TLSConfig.SerializationFormat = .pem, inDirectory directory: String? = nil, inBundle bundle: Bundle = .main) -> Self? {
        .fileInBundle(forResource: fileName, withExtension: "crt", format: format, inDirectory: directory, inBundle: bundle)
    }

    public static func pemInBundle(_ fileName: String, format: TLSConfig.SerializationFormat = .pem, inDirectory directory: String? = nil, inBundle bundle: Bundle = .main) -> Self? {
        .fileInBundle(forResource: fileName, withExtension: "pem", format: format, inDirectory: directory, inBundle: bundle)
    }
}
