# KurrentDB-Swift

[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fgradyzhuo%2FKurrentDB-Swift%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/gradyzhuo/KurrentDB-Swift)
[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-lightgrey.svg)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Swift Package Index](https://img.shields.io/badge/Swift%20Package%20Index-available-brightgreen)](https://swiftpackageindex.com/gradyzhuo/KurrentDB-Swift)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fgradyzhuo%2FKurrentDB-Swift%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/gradyzhuo/KurrentDB-Swift)
[![Swift-build-testing](https://github.com/gradyzhuo/EventStoreDB-Swift/actions/workflows/swift-build-testing.yml/badge.svg)](https://github.com/offsky-studio/KurrentDB-Swift/actions/workflows/swift-build-testing.yml)

<div align=center>

**A modern, type-safe Swift client for Kurrent (formerly EventStoreDB)**

Built with ❤️ for Server-Side Swift and Event Sourcing

[📚 Documentation](https://swiftpackageindex.com/gradyzhuo/KurrentDB-Swift/documentation/kurrentdb) • [🚀 Getting Started](https://swiftpackageindex.com/gradyzhuo/kurrentdb-swift/1.11.2/documentation/kurrentdb/getting-started) • [💬 Discussions](https://github.com/gradyzhuo/KurrentDB-Swift/discussions)

</div>

---

## ✨ Why KurrentDB-Swift?

Event Sourcing is a powerful pattern for building scalable, auditable systems. KurrentDB-Swift brings this capability to the Swift ecosystem with a modern, type-safe client.

- 🎯 **Native Swift** - Designed for Swift from the ground up, not a wrapper
- ⚡ **Modern Concurrency** - Full async/await support with Swift 6 compatibility
- 🔒 **Type-Safe** - Leverages Swift's type system for compile-time safety
- 🚀 **Production-Ready** - Over 1 year of development, 425+ commits, 46 releases
- 📖 **Well-Documented** - Comprehensive guides on [Swift Package Index](https://swiftpackageindex.com/gradyzhuo/KurrentDB-Swift/documentation/kurrentdb)
- 🔧 **Actively Maintained** - Regular updates and responsive to issues

## 🎬 Quick Start

### Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/gradyzhuo/KurrentDB-Swift.git", from: "1.11.2")
]
```

### Your First Event

```swift
import KurrentDB

// 1. Connect to Kurrent
let client = KurrentDBClient(settings: .localhost())

// 2. Create an event
let event = EventData(
    eventType: "OrderPlaced",
    model: ["orderId": "order-123", "total": 99.99] // or any Codable instance.
)

// 3. Append to stream
try await client.appendStream("orders", events: [event]) {
    $0.revision(expected: .any)
}

// 4. Read events back
let events = try await client.readStream("orders") {
    $0.backward().startFrom(revision: .start)
}

for try await response in events {
    if let event = try response.event {
        print("Event: \(event.eventType)")
    }
}
```

**That's it!** You're now using Event Sourcing in Swift. 🎉

## 📖 Learn More

Check out our comprehensive documentation on Swift Package Index:

- 📘 [Getting Started Guide](https://swiftpackageindex.com/gradyzhuo/kurrentdb-swift/documentation/kurrentdb/getting-started)
- ✍️ [Appending Events](https://swiftpackageindex.com/gradyzhuo/kurrentdb-swift/documentation/kurrentdb/appending-events)
- 📖 [Reading Events](https://swiftpackageindex.com/gradyzhuo/kurrentdb-swift/documentation/kurrentdb/reading-events)
- 🔄 [Working with Projections](https://swiftpackageindex.com/gradyzhuo/kurrentdb-swift/documentation/kurrentdb/projections)
- 📚 [Full API Reference](https://swiftpackageindex.com/gradyzhuo/KurrentDB-Swift/documentation/kurrentdb)

## 🎯 Features

- ✅ Stream operations (append, read, delete)
- ✅ Subscriptions (catch-up and persistent)
- ✅ Projections management
- ✅ Optimistic concurrency control
- ✅ TLS/SSL support
- ✅ Cluster configuration
- ✅ Connection management with auto-reconnection
- ✅ Swift 6 ready (zero data-race safety)

## 📦 Requirements

- Swift 6.0 or later
- macOS 15+ / iOS 18+ / Linux
- Kurrent 24.2+ (or EventStoreDB 23.10+)

## 🏗️ Used in Production?

We'd love to hear about your experience! Share your story in [Discussions](https://github.com/gradyzhuo/KurrentDB-Swift/discussions) or add your project to our showcase.

## 🤝 Contributing

Contributions are welcome! Whether it's:

- 🐛 Bug reports
- 💡 Feature requests  
- 📖 Documentation improvements
- 🔧 Code contributions

Check out our [Contributing Guide](CONTRIBUTING.md) to get started.

## 💬 Community

- 💭 [GitHub Discussions](https://github.com/gradyzhuo/KurrentDB-Swift/discussions) - Ask questions, share ideas
- 🐛 [Issues](https://github.com/gradyzhuo/KurrentDB-Swift/issues) - Report bugs
- 🐦 [Dev.to](https://dev.to/gradyzhuo) - Follow for updates

## 📄 License

MIT License - see [LICENSE](Licence) for details.

## 🙏 Acknowledgments

Built with these excellent libraries:
- [grpc-swift](https://github.com/grpc/grpc-swift) - Swift gRPC implementation
- [swift-nio](https://github.com/apple/swift-nio) - Non-blocking I/O

Inspired by official Kurrent/EventStoreDB clients.

---

**⭐ If you find KurrentDB-Swift useful, please consider giving it a star! ⭐**

Made with ❤️ by [Grady Zhuo](https://github.com/gradyzhuo) and [contributors](https://github.com/gradyzhuo/KurrentDB-Swift/graphs/contributors)
