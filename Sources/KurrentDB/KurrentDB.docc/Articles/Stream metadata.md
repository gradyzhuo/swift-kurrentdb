# Stream metadata

Set how many events a stream keeps, how long it keeps them and who may access it, and store data of your own next to those settings.

## Overview

Every stream has a metadata stream, `$$<stream>`, whose latest event holds a JSON object. The server reads the keys that start with `$`; every other key is yours. ``StreamMetadata`` holds that object exactly as stored, in ``StreamMetadata/data``. Its properties read from the object and its builders write to it, and every key it has no property for, whether another client wrote it or a later server version added it, is kept when you write the value back.

A builder replaces only the keys it sets, where they are, and appends a new key: every other key keeps its bytes and its place, so a number keeps every digit and two keys that differ only in Unicode normalization stay two keys, as the server reads them. A custom value you write is encoded with `JSONEncoder`, so it holds what its Swift type holds. When an object repeats a key, 3.0 reads the last occurrence, as the server does (see Metadata the server ignores). The object may nest arrays and objects at most 64 levels deep, itself being the first: deeper metadata throws `KurrentError.internalParsingError` when read, and a custom value that would nest deeper throws `KurrentError.encodingError` when written.

`setMetadata(metadata:expectedRevision:)` appends a new metadata event, which replaces the whole object, and `getMetadata()` returns the latest one, or `nil` when none has been written. It throws `KurrentError.internalParsingError` when the stored event is not a JSON object, or holds a value the server cannot read (see Metadata the server ignores below):

```swift
try await orders.setMetadata(metadata: StreamMetadata().maxCount(1_000))
if let metadata = try await orders.getMetadata() {
    print(metadata.maxCount ?? 0)   // 1000
}
```

## System fields

Each system field has a builder that returns an updated copy, and a read-only property that returns `nil` when the key is absent:

| Builder | Property | Stored key | Meaning |
|---------|----------|------------|---------|
| `maxCount(_:)` | ``StreamMetadata/maxCount`` | `$maxCount` | How many events the stream keeps; older ones become eligible for scavenging |
| `maxAge(_:)` | ``StreamMetadata/maxAge`` | `$maxAge` | How long the stream keeps an event, in whole seconds |
| `truncateBefore(_:)` | ``StreamMetadata/truncateBefore`` | `$tb` | Events before this revision are hidden from reads and later scavenged (a soft delete) |
| `cacheControl(_:)` | ``StreamMetadata/cacheControl`` | `$cacheControl` | How long intermediaries may cache the head of the stream, in whole seconds |
| `acl(_:)` | ``StreamMetadata/acl`` | `$acl` | Who may read, write, delete and manage the stream; reads ``StreamMetadata/Acl/serverDefault`` when absent |

```swift
let metadata = StreamMetadata()
    .maxCount(10_000)
    .maxAge(.seconds(7 * 24 * 60 * 60))
    .cacheControl(.seconds(10))
try await orders.setMetadata(metadata: metadata)
```

The value is stored as the server reads it:

```json
{"$cacheControl":10,"$maxAge":604800,"$maxCount":10000}
```

### Access control

`acl(_:)` takes one of two values:

- ``StreamMetadata/Acl/serverDefault``: the stream has no ACL of its own. The builder removes `$acl` and leaves every other key as it is, so `setMetadata(metadata:expectedRevision:)` appends a `$metadata` event without `$acl`. The server then applies the default from the `$settings` stream, `$userStreamAcl` for a user stream and `$systemStreamAcl` for a stream whose name starts with `$`, and follows any later change to `$settings`. With the built-in defaults everyone (`$all`) may read, write and delete a user stream and read and write its metadata. The server grants `$all` before any identity check, so it includes anonymous requests, as far as the server's settings for anonymous access allow them. Members of `$admins` always have access.
- ``StreamMetadata/Acl/stream(_:)``: the stream's own roles, a ``StreamMetadata/StreamAcl`` stored as the `$acl` object. A permission left at ``StreamMetadata/StreamAcl/Roles/defaults`` falls back to the default from `$settings`.

`$userStreamAcl` and `$systemStreamAcl` are keys of `$settings`, not values of a stream's `$acl`: the server reads `$acl` only as an object and ignores the whole metadata object for anything else.

```swift
if let stored = try await orders.getMetadata() {
    try await orders.setMetadata(metadata: stored.acl(.serverDefault))   // the other keys are written back as read
}
```

### Changing a stream's roles

A ``StreamMetadata/StreamAcl`` holds the roles of each permission as a ``StreamMetadata/StreamAcl/Roles`` value: ``StreamMetadata/StreamAcl/Roles/granted(_:)`` stores the list, and ``StreamMetadata/StreamAcl/Roles/defaults`` stores nothing, so the server applies the default from `$settings` for that permission. An array literal is `.granted`: `writeRoles(["ops"])` stores `"$w":["ops"]`; pass a `[String]` variable as `.granted(names)`. `.granted([])` grants the permission to no one but `$admins`.

Start from the roles already stored, or from ``StreamMetadata/StreamAcl/defaults`` when the stream has none, change the permissions you mean to, and write the metadata back, so the keys and roles you leave alone keep their values. Keep your own user, or a role it has, in the metadata write roles (`$mw`): otherwise you can no longer change the metadata.

```swift
let stored = try await orders.getMetadata() ?? StreamMetadata()
let roles: StreamMetadata.StreamAcl = switch stored.acl {
case .serverDefault: .defaults   // the stream's first ACL
case let .stream(current): current
}
try await orders.setMetadata(metadata: stored.acl(.stream(roles.writeRoles(["ops"]))))
```

To hand one permission back to the default from `$settings`, set it to `.defaults`, which removes its key:

<!-- snippet:continue -->
```swift
try await orders.setMetadata(metadata: stored.acl(.stream(roles.writeRoles(.defaults))))
```

`acl(.stream(.defaults))` stores `"$acl":{}`, in which every permission falls back to `$settings`: the server treats it the same as `acl(.serverDefault)`, which stores no `$acl`. The ``StreamMetadata/acl`` property still tells them apart: `"$acl":{}` reads as `.stream(.defaults)`, so compare with both when you check for the default.

### Durations are whole seconds

The server stores `$maxAge` and `$cacheControl` in whole seconds, so `maxAge(_:)` and `cacheControl(_:)` truncate any sub-second part: `.milliseconds(1500)` stores `1`. A duration under one second is written as it is, `0` or a negative number, and logged as a warning: the server ignores that field and applies the rest of the object.

```swift
let metadata = StreamMetadata().maxAge(.milliseconds(1500))
print(metadata.maxAge == .seconds(1))   // true
```

### Limits

The server accepts a metadata write whatever it holds, then ignores a value it cannot apply. Some values make it ignore the whole object, `$acl` included, so the builders refuse them: passing a value above its limit is a programmer error and stops the program.

| Builder | Largest value | Above it |
|---------|---------------|----------|
| `maxCount(_:)`, `truncateBefore(_:)` | `Int64.max` (9,223,372,036,854,775,807) | the server ignores the whole object |
| `cacheControl(_:)` | 922,337,203,685 seconds | the server ignores the whole object |
| `maxAge(_:)` | 62,000,000,000 seconds (about 1,964 years) | an age reaching back before the year 1 makes every read of the stream return nothing |

At the other end, `maxCount(0)` and a duration under one second are written and logged as a warning; the server ignores that field. A duration below -922,337,203,685 seconds, .NET's `TimeSpan.MinValue`, is refused like a value above its limit.

The properties read every value the server reads, so a value another client wrote can exceed these limits: a `$maxAge` above 62,000,000,000 seconds, for example. Check it before you pass it back to a builder.

## Metadata the server ignores

The server reads the metadata object member by member. When a system key holds a value it cannot read, it ignores the whole object, `$maxCount`, `$tb` and `$acl` included: the stream keeps every event and gets the default access rules. ``StreamMetadata/init(data:)``, and so `getMetadata()`, throws `KurrentError.internalParsingError` for such an object, naming the key and the value, as the .NET client does, rather than report settings the server does not apply:

| Key | The server reads |
|-----|------------------|
| `$maxCount`, `$tb` | an integer within `Int64`, written without a fraction or an exponent: `10`, not `10.0` or `1e1` |
| `$maxAge`, `$cacheControl` | the same, within ±922,337,203,685 seconds |
| `$tmp` | a boolean |
| `$acl` | an object whose keys are `$r`, `$w`, `$d`, `$mr` and `$mw`, each holding a string or an array of strings |

Zero and negative numbers are read: the server ignores only that field, and the properties read the stored value (`nil` for a negative `$maxCount` or `$tb`). Every other key may hold any JSON value.

When an object repeats a key, the server checks every occurrence in turn, so one invalid occurrence makes it ignore the object; when all are valid, the last one applies. ``StreamMetadata/data`` then holds only the last occurrence of each repeated key. Keys are compared by their Unicode scalars, as the server compares them: `"café"` written with a precomposed `é` and with `e` and a combining accent are two keys, and ``StreamMetadata/init(data:)`` keeps both in ``StreamMetadata/data``. The properties and the builders keep them apart too. Only `==` and `Codable` see the object as a Swift dictionary, whose `String` keys compare such keys equal: `==` treats two objects that differ only in such keys as equal, and encoding a ``StreamMetadata`` with `JSONEncoder` writes only one of them. Only writes from other tools produce such keys.

Like `JSONDecoder` and the server, ``StreamMetadata/init(data:)`` accepts a trailing comma after the last member of an object or array, and a UTF-8 byte order mark. It throws for UTF-16 and UTF-32 text, as the .NET client does: JSON exchanged between systems is UTF-8. A few values the server accepts cannot be read, and `getMetadata()` throws for them: a number beyond the range of `Double`, such as `1e400`, a lone surrogate escape, such as `"\ud800"`, and text that the server's parser tolerates but JSON does not allow, such as `[1,,2]`, text after the object, single quotes or `NaN`. Only raw writes from other tools produce them.

## Custom keys

Store data of your own as top-level keys of the object, next to the system fields. Describe it with a `Codable` type, write it with `customProperties(encoding:)` and read it back with `customProperties(as:)`:

<!-- snippet:toplevel -->
```swift
struct Ownership: Codable, Sendable {
    var tenant: String
    var team: String
    var retainedForAudit: Bool
}
```

```swift
let metadata = try StreamMetadata()
    .maxCount(10_000)
    .customProperties(encoding: Ownership(tenant: "acme", team: "billing", retainedForAudit: true))
try await orders.setMetadata(metadata: metadata)

if let stored = try await orders.getMetadata() {
    let ownership = try stored.customProperties(as: Ownership.self)
    print(ownership.team)   // billing
}
```

The object is stored as `{"$maxCount":10000,"retainedForAudit":true,"team":"billing","tenant":"acme"}`. `customProperties(as:)` decodes only the keys that do not start with `$`, so the system fields never reach your type. `customProperties(encoding:)` replaces the keys your value holds and leaves the others as they are.

To write or read a single key, use `customProperty(_:encoding:)` and `customProperty(_:as:)`. A value may be any JSON value: a string, a number, a boolean, an array or an object.

```swift
let metadata = try StreamMetadata()
    .customProperty("tenant", encoding: "acme")
    .customProperty("shards", encoding: [1, 2, 3])
let tenant = try metadata.customProperty("tenant", as: String.self)   // "acme"
let missing = try metadata.customProperty("region", as: String.self)  // nil
_ = (tenant, missing)
```

Encoding and decoding use `JSONEncoder` and `JSONDecoder` with their default strategies: a `Date` is stored as seconds since 1 January 2001 and `Data` as Base64. When other clients read a key, store such fields in a form they understand, such as an ISO 8601 string.

### Keys starting with $ are reserved

Keys that start with `$` belong to the server, including ones it adds in a later version. `customProperties(encoding:)` and `customProperty(_:encoding:)` throw `KurrentError.encodingError` for such a key, and `customProperty(_:as:)` returns `nil` for it. Set the system fields through their builders.

```swift
do {
    _ = try StreamMetadata().customProperty("$maxCount", encoding: 10)
} catch KurrentError.encodingError(let message, _) {
    print(message)   // Custom stream metadata key '$maxCount' must not start with '$'.
}
```

## Changing metadata other tools wrote

A metadata event replaces the whole object: `setMetadata(metadata:expectedRevision:)` writes every key the value holds and nothing else. To change one setting and keep everything else, including keys another client, a script or the server wrote, read the metadata, change it with the builders and write it back.

```swift
let current = try await orders.getMetadata() ?? StreamMetadata()
let updated = try current
    .maxAge(.seconds(30 * 24 * 60 * 60))
    .customProperty("reviewedBy", encoding: "ops")
try await orders.setMetadata(metadata: updated)   // every other key, `$` or custom, is written back as read
```

A read-modify-write has no optimistic concurrency check: `getMetadata()` does not return the revision of the `$$<stream>` event it read, so two writers that read the same metadata can overwrite each other's change, and the last write wins. This applies to the role change above too.

A value built with ``StreamMetadata/init()`` starts from the empty object `{}`, so writing it drops the keys the stream already had. To start from JSON you hold, such as one exported from another tool, use ``StreamMetadata/init(data:)``:

```swift
let imported = try StreamMetadata(data: Data(#"{"$maxCount":50,"owner":"billing"}"#.utf8))
print(imported.maxCount ?? 0)                                         // 50
print(try imported.customProperty("owner", as: String.self) ?? "")    // billing
```

## Soft delete replaces the metadata

`delete()` soft-deletes the stream by writing new metadata that holds only `$tb`: `{"$tb":9223372036854775807}`. Every other key, `$acl`, `$maxCount` and your custom keys included, is gone from then on. If the stream will be written to again, write its metadata again after the delete.
