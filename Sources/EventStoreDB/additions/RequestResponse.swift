//
//  RequestResponse.swift
//
//
//  Created by Grady Zhuo on 2023/12/12.
//

import Foundation
import GRPCEncapsulates

public typealias EmptyRequest = GenericGRPCRequest<EventStore_Client_Empty>

public typealias EmptyResponse = DiscardedResponse<EventStore_Client_Empty>
