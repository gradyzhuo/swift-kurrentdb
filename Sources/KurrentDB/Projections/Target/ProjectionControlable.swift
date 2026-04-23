//
//  ProjectionControlable.swift
//  KurrentDB
//

/// Marks a projection target as supporting control operations by exposing the projection name.
public protocol ProjectionControlable {
    /// Name of the projection to control.
    var name: String { get }
}
