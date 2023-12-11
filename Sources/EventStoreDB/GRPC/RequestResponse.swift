//
//  File.swift
//  
//
//  Created by 卓俊諺 on 2023/12/12.
//

import Foundation
import GRPCSupport

public typealias EmptyRequest = GenericGRPCRequest<EventStore_Client_Empty>

public typealias EmptyResponse = DiscardedResponse<EventStore_Client_Empty>
