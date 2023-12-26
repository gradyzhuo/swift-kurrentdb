//
//  File.swift
//  
//
//  Created by Ospark.org on 2023/10/17.
//

import Foundation

public enum ServerError: Error {
    case timeout
    case targetError(host: String, port: Int)
}

public enum ClientSettingsError: Error {
    case parseError(message: String)
    case optionNotFound(message: String, queryItem: URLQueryItem)
    case encodingError(message: String, encoding: String.Encoding)
}

public enum ClientError: Error {
    case streamNameError(message: String)
    case readResponseError(message: String)
    case projectionNameError(message: String)
}



public enum ReadEventError : Error {
    case GRPCDecodeException(message: String)
    
}
