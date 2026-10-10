//
//  CertificateFallback.swift
//  KurrentDB
//

/// What ``ClientSettings/certificate(path:fallback:)`` does when the CA file it was given cannot
/// be read (missing, not readable, or empty).
///
/// There is deliberately no default: falling back widens trust from one private CA to every
/// certificate authority the system trusts, so it has to be written out.
public enum CertificateFallback: Sendable, Equatable {
    /// No fallback: throw `KurrentError.initializationError`.
    case none
    /// Leave the configured CA out, so the system's root certificates are trusted if no other CA
    /// is configured. Use it only
    /// when one configuration is shared by environments where the CA file is legitimately absent.
    case systemTrustRoots
}
