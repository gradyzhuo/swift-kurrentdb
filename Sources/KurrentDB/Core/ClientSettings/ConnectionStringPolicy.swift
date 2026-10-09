//
//  ConnectionStringPolicy.swift
//  KurrentCore
//

/// Marks how a connection string is validated.
///
/// The protocol has no requirements on purpose. Each policy is a concrete type with its own
/// `ClientSettings.parse(connectionString:policy:)` overload: a type outside this package can
/// conform to the marker, but it gets no `parse` overload, so nobody can plug in a policy that
/// relaxes the security rules. A future policy is a new struct plus a new overload in this package.
/// Use it through the static members, e.g. `.rfc3986`.
public protocol ConnectionStringPolicy: Sendable {}

/// Strict RFC 3986 parsing. The `parse(connectionString:)` and `fromEnv(key:)` overloads without `policy:` use it.
///
/// - Leading and trailing whitespace and newlines around the whole string are ignored; whitespace
///   anywhere else is an error.
/// - The authority holds at most one `@`. Credentials and query parameters accept only the
///   characters RFC 3986 allows there (plus `%XX` escapes), and an unencoded `@` in the query is
///   rejected on purpose: write it as `%40`.
/// - Anything outside the allowed sets (non-ASCII, control characters, `"` `<` `>` `\` `^` `` ` ``
///   `{` `|` `}`, ...) must be percent-encoded.
///
/// Passwords with arbitrary characters do not have to go through a connection string at all; use
/// `ClientSettings.authenticated(.credentials(username:password:))` instead.
public struct RFC3986Policy: ConnectionStringPolicy, Equatable {
    public init() {}
}

extension ConnectionStringPolicy where Self == RFC3986Policy {
    /// Strict RFC 3986 parsing; see ``RFC3986Policy``.
    public static var rfc3986: RFC3986Policy { .init() }
}
