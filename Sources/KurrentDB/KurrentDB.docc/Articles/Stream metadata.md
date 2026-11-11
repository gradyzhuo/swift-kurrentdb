# Stream metadata

Set how many events a stream keeps, how long it keeps them and who may access it, and store data of your own next to those settings.

## Overview

Every stream has a metadata stream, `$$<stream>`, whose latest event holds a JSON object. The server reads the keys that start with `$`; every other key is yours. ``StreamMetadata`` holds the system fields and every other key of that object. Its properties read the system fields and its builders set them, and every key it has no property for, whether another client wrote it or a later server version added it, is kept when you write the value back.

``StreamMetadata`` reads and writes the JSON as the server reads it, which `JSONDecoder` and `JSONEncoder` do not, so it is neither `Decodable` nor `Encodable`: read the data of a `$$<stream>` event with ``StreamMetadata/init(data:)``, as `getMetadata()` does. `String(reflecting: metadata)` is the JSON that `setMetadata(metadata:expectedRevision:)` sends: the system fields first, then every other key in the order it was read or set.

A builder changes only the keys it sets. Every other key keeps its value: a number keeps every digit, and a nested object keeps its keys in their order. A custom value you write is encoded with `JSONEncoder`, so it holds what its Swift type holds. When an object repeats a key, 3.0 reads the last occurrence, as the server does (see Metadata the server ignores). The object may nest arrays and objects at most 64 levels deep, itself being the first: deeper metadata throws `KurrentError.internalParsingError` when read, and a custom value that would nest deeper throws `KurrentError.encodingError` when written.

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
{"$maxCount":10000,"$maxAge":604800,"$cacheControl":10}
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

The server reads the metadata object member by member. When it meets something it cannot read, it ignores the whole object, `$maxCount`, `$tb` and `$acl` included: the stream keeps every event and gets the default access rules. ``StreamMetadata/init(data:)``, and so `getMetadata()`, throws `KurrentError.internalParsingError` for such an object, naming the key and the value, as the .NET client does, rather than report settings the server does not apply:

| Key | The server reads |
|-----|------------------|
| `$maxCount`, `$tb` | an integer within `Int64`, written without a fraction or an exponent: `10`, not `10.0` or `1e1` |
| `$maxAge`, `$cacheControl` | the same, within ±922,337,203,685 seconds |
| `$tmp` | a boolean |
| `$acl` | an object whose keys are `$r`, `$w`, `$d`, `$mr` and `$mw`, each holding a role name or an array of role names |

Zero and negative numbers are read: the server ignores only that field, and the properties read the stored value (`nil` for a negative `$maxCount` or `$tb`). Every other key may hold any JSON value.

Two rules come from the server's JSON reader, Newtonsoft.Json, which tries every string as a date:

- A role name that reads as a date, such as `"2024-01-01T00:00:00"` or `"/Date(0)/"`, is not a string to the server, so it ignores the object. ``StreamMetadata/init(data:)`` throws for it, and `setMetadata(metadata:expectedRevision:)` throws `KurrentError.encodingError` rather than send it.
- A string that reads as a date outside the years 1 to 9999, such as `"/Date(253402300800000)/"` or `"9999-12-31T24:00:00"`, makes the reader fail wherever it stands, in a custom value too. Reading and writing both throw for it. Any other date-like string in a custom value is only a string.

A role written as a single string is the same as a list of that one name, to the server and to `==`: `"$r":"ops"` equals `"$r":["ops"]`. This holds for the five keys of `$acl` only. Role names themselves are compared byte by byte, by the server and by `==`: two names that differ only in Unicode normalization are two roles.

When an object repeats a key, the server checks every occurrence in turn, so one invalid occurrence makes it ignore the object; when all are valid, the last one applies, and only that one is written back. The server compares keys by their Unicode scalars: `"café"` written with a precomposed `é` and with `e` and a combining accent are two keys to it. ``StreamMetadata/init(data:)`` reads both and writes both back. Your own code names a custom key with a Swift `String`, which compares the two spellings equal: `customProperty(_:as:)` reads the first of them, `customProperty(_:encoding:)` replaces both with the key you pass, and `==` compares the first. Only writes from other tools produce such keys.

Newtonsoft.Json accepts more than standard JSON, and ``StreamMetadata/init(data:)`` reads all of it the same way: a trailing comma, single-quoted strings, unquoted keys (of the letters and digits Unicode 15.0 assigned, as .NET 8 knows them), integers written in octal or hexadecimal (`010` is 8, `0x10` is 16), `.5` and `1.`, `NaN`, `Infinity`, `undefined`, and comments inside the value of a custom key. A comment anywhere else, such as between two top-level keys or inside `$acl`, makes the server ignore the object. The text may be UTF-8, or UTF-16 or UTF-32 with a byte order mark; malformed bytes are read as U+FFFD, not refused. The server stops reading at the closing brace of the object, so anything after it is ignored and not kept.

A custom value is kept as standard JSON: `010` is written back as `8`, `.5` as `0.5`, a single-quoted string with double quotes, and comments are dropped. `NaN`, `Infinity` and `undefined` have no JSON form, so they are written back as they are, and `customProperty(_:as:)` throws for them. `customProperties(as:)` then throws too, whatever type it decodes into, and its error names the key: read the other keys one at a time with `customProperty(_:as:)`. A string starting with `/Date(` is written with its first slash escaped (`"\/Date(0)/"`), which the server reads the same way wherever the string stands. One difference from the server remains: in metadata longer than 922 characters, a `/Date(…)/` string with a malformed offset, such as `"/Date(0+08:00)/"`, may be read as a date here where the server reads a string, so reading throws for a role name or an out-of-range value of that shape. Only raw writes from other tools produce any of these.

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

`removingCustomProperty(_:)` removes a key and leaves every other key as it is:

```swift
let stored = try StreamMetadata().customProperty("tenant", encoding: "acme")
let cleared = try stored.removingCustomProperty("tenant")   // {}
_ = cleared
```

Encoding and decoding use `JSONEncoder` and `JSONDecoder` with their default strategies: a `Date` is stored as seconds since 1 January 2001 and `Data` as Base64. A whole number that fits `Int64` or `UInt64` is stored exactly and any other number as a `Double`, as the other KurrentDB clients store it; store a number that needs more digits as a string. When other clients read a key, store such fields in a form they understand, such as an ISO 8601 string.

### Keys starting with $ are reserved

Keys that start with `$` belong to the server, including ones it adds in a later version. `customProperties(encoding:)`, `customProperty(_:encoding:)` and `removingCustomProperty(_:)` throw `KurrentError.encodingError` for such a key, and `customProperty(_:as:)` returns `nil` for it. Set the system fields through their builders.

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
