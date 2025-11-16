# Contributing to KurrentDB-Swift

First off, thank you for considering contributing to KurrentDB-Swift! 🎉

It's people like you that make KurrentDB-Swift a great tool for the Swift community. We welcome contributions from everyone, whether you're fixing a typo, reporting a bug, or implementing a major feature.

## 📋 Table of Contents

- [Code of Conduct](#code-of-conduct)
- [How Can I Contribute?](#how-can-i-contribute)
- [Development Setup](#development-setup)
- [Pull Request Process](#pull-request-process)
- [Coding Guidelines](#coding-guidelines)
- [Testing Guidelines](#testing-guidelines)
- [Documentation Guidelines](#documentation-guidelines)
- [Community](#community)

## 🤝 Code of Conduct

This project and everyone participating in it is governed by our commitment to providing a welcoming and inspiring community for all. By participating, you are expected to uphold this commitment.

**In short:**
- Be respectful and inclusive
- Be collaborative and constructive
- Focus on what is best for the community
- Show empathy towards other community members

## 🎯 How Can I Contribute?

There are many ways to contribute to KurrentDB-Swift:

### 🐛 Reporting Bugs

Before creating bug reports, please check existing issues to avoid duplicates. When you create a bug report, include as many details as possible:

- **Use a clear and descriptive title**
- **Describe the exact steps to reproduce the problem**
- **Provide specific examples** (code snippets, logs, etc.)
- **Describe the behavior you observed** and what you expected
- **Include your environment details** (Swift version, OS, Kurrent version)

**Bug Report Template:**
```markdown
**Description:**
A clear description of what the bug is.

**Steps to Reproduce:**
1. Step one
2. Step two
3. ...

**Expected Behavior:**
What you expected to happen.

**Actual Behavior:**
What actually happened.

**Environment:**
- KurrentDB-Swift version:
- Swift version:
- OS: 
- Kurrent/EventStoreDB version:

**Code Sample:**
```swift
// Minimal code to reproduce the issue
```

**Additional Context:**
Any other context about the problem.
```

### 💡 Suggesting Features

Feature suggestions are welcome! Before creating a feature request:

- Check if the feature has already been suggested
- Make sure it aligns with the project's goals
- Provide a clear use case

**Feature Request Template:**
```markdown
**Problem Statement:**
What problem does this feature solve?

**Proposed Solution:**
How would you like this to work?

**Alternative Solutions:**
Have you considered any alternatives?

**Use Case:**
Describe a real-world scenario where this would be useful.

**Additional Context:**
Any other information or mockups.
```

### 📖 Improving Documentation

Documentation improvements are always appreciated:

- Fix typos or clarify existing documentation
- Add examples or tutorials
- Improve API documentation
- Write blog posts or guides

### 🔧 Contributing Code

We love code contributions! Here's how to get started.

## 🛠️ Development Setup

### Prerequisites

- Swift 5.9 or later
- macOS 13+ or Linux
- Docker (for running Kurrent locally)
- Git

### Setting Up Your Environment

1. **Fork the repository**
   ```bash
   # Click "Fork" on GitHub, then clone your fork
   git clone https://github.com/YOUR-USERNAME/KurrentDB-Swift.git
   cd KurrentDB-Swift
   ```

2. **Add upstream remote**
   ```bash
   git remote add upstream https://github.com/gradyzhuo/KurrentDB-Swift.git
   ```

3. **Install dependencies**
   ```bash
   swift package resolve
   ```

4. **Run Kurrent locally** (for testing)
   ```bash
   docker run -d -p 2113:2113 \
     --name kurrent-test \
     eventstore/eventstore:latest \
     --insecure --enable-atom-pub-over-http
   ```

5. **Build the project**
   ```bash
   swift build
   ```

6. **Run tests**
   ```bash
   swift test
   ```

### Project Structure

```
KurrentDB-Swift/
├── Sources/
│   └── KurrentDB/
│       ├── Client/          # Client implementation
│       ├── Models/          # Data models
│       ├── Operations/      # Stream operations
│       ├── Projections/     # Projection management
│       └── Subscriptions/   # Subscription handling
├── Tests/
│   └── KurrentDBTests/      # Test files
├── Documentation/
│   └── KurrentDB.docc/      # DocC documentation
└── Examples/                # Example projects (if any)
```

## 🔄 Pull Request Process

### Before You Start

1. **Check existing PRs** to avoid duplicate work
2. **Open an issue first** for major changes (to discuss the approach)
3. **Create a feature branch** from `main`

### Creating a Pull Request

1. **Create a branch**
   ```bash
   git checkout -b feature/your-feature-name
   # or
   git checkout -b fix/your-bug-fix
   ```

2. **Make your changes**
   - Write clean, readable code
   - Follow the coding guidelines
   - Add tests for new functionality
   - Update documentation

3. **Commit your changes**
   ```bash
   git add .
   git commit -m "feat: add support for XYZ"
   ```

   **Commit Message Format:**
   ```
   <type>: <description>

   [optional body]

   [optional footer]
   ```

   Types:
   - `feat`: New feature
   - `fix`: Bug fix
   - `docs`: Documentation changes
   - `test`: Adding or updating tests
   - `refactor`: Code refactoring
   - `perf`: Performance improvements
   - `chore`: Maintenance tasks

4. **Push to your fork**
   ```bash
   git push origin feature/your-feature-name
   ```

5. **Open a Pull Request**
   - Use a clear, descriptive title
   - Reference related issues
   - Describe what you changed and why
   - Include screenshots/examples if relevant

### Pull Request Template

```markdown
**Description:**
Brief description of what this PR does.

**Motivation:**
Why is this change needed?

**Changes:**
- Change 1
- Change 2
- ...

**Related Issues:**
Fixes #123

**Testing:**
- [ ] Unit tests added/updated
- [ ] Integration tests added/updated
- [ ] Manual testing performed

**Documentation:**
- [ ] Code comments added/updated
- [ ] DocC documentation updated
- [ ] README updated (if needed)

**Checklist:**
- [ ] Code follows project style guidelines
- [ ] Tests pass locally
- [ ] Documentation is updated
- [ ] No breaking changes (or clearly documented)
```

### Review Process

- Maintainers will review your PR as soon as possible
- Address any requested changes
- Once approved, a maintainer will merge your PR

## 📝 Coding Guidelines

### Swift Style

We follow the [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/) and [Swift.org formatting guidelines](https://swift.org/documentation/articles/formatting.html).

**Key Points:**

1. **Naming**
   ```swift
   // ✅ Good: Clear, descriptive names
   func appendToStream(_ streamName: String, events: [EventData]) async throws
   
   // ❌ Bad: Unclear abbreviations
   func append(_ s: String, evts: [EventData]) async throws
   ```

2. **Documentation**
   ```swift
   /// Appends events to a stream with optimistic concurrency control.
   ///
   /// - Parameters:
   ///   - streamName: The name of the stream to append to
   ///   - events: The events to append
   /// - Throws: `KurrentError` if the operation fails
   /// - Returns: The write result including the next expected revision
   public func appendToStream(
       _ streamName: String,
       events: [EventData]
   ) async throws -> WriteResult
   ```

3. **Error Handling**
   ```swift
   // ✅ Good: Specific error types
   enum KurrentError: Error {
       case connectionFailed(reason: String)
       case wrongExpectedRevision(expected: StreamRevision, actual: StreamRevision)
   }
   
   // ❌ Bad: Generic errors
   throw NSError(domain: "error", code: 1)
   ```

4. **Async/Await**
   ```swift
   // ✅ Good: Use async/await
   func readStream(_ streamName: String) async throws -> AsyncThrowingStream<Event, Error>
   
   // ❌ Bad: Completion handlers (unless necessary for compatibility)
   func readStream(_ streamName: String, completion: @escaping (Result<[Event], Error>) -> Void)
   ```

5. **Access Control**
   ```swift
   // Use appropriate access levels
   public class KurrentDBClient { }      // Public API
   internal struct StreamMetadata { }    // Internal implementation
   private func validateStream() { }     // Private helpers
   ```

### Code Organization

- One type per file (generally)
- Group related functionality
- Use extensions for protocol conformance
- Keep functions focused and small

## 🧪 Testing Guidelines

### Writing Tests

1. **Test Coverage**
   - Aim for high test coverage on critical paths
   - Test both success and failure cases
   - Include edge cases

2. **Test Structure**
   ```swift
   final class StreamOperationsTests: XCTestCase {
       var client: KurrentDBClient!
       
       override func setUp() async throws {
           client = KurrentDBClient(settings: .localhost())
       }
       
       func testAppendToStream() async throws {
           // Given
           let streamName = "test-\(UUID())"
           let event = EventData(eventType: "TestEvent", model: ["key": "value"])
           
           // When
           let result = try await client.appendStream(streamName, events: [event])
           
           // Then
           XCTAssertEqual(result.nextExpectedRevision, .specific(1))
       }
   }
   ```

3. **Integration Tests**
   - Test against real Kurrent instance (in Docker)
   - Use unique stream names (with UUIDs)
   - Clean up resources

4. **Test Naming**
   ```swift
   // Format: test[What]_[Condition]_[ExpectedResult]
   func testAppendToStream_WithValidEvent_ReturnsWriteResult() async throws { }
   func testAppendToStream_WithWrongRevision_ThrowsError() async throws { }
   ```

### Running Tests

```bash
# Run all tests
swift test

# Run specific test
swift test --filter KurrentDBTests.StreamOperationsTests

# Run with coverage
swift test --enable-code-coverage
```

## 📚 Documentation Guidelines

### DocC Documentation

1. **Document all public APIs**
   ```swift
   /// A client for interacting with Kurrent.
   ///
   /// Use `KurrentDBClient` to perform operations on event streams,
   /// manage subscriptions, and work with projections.
   ///
   /// ## Topics
   ///
   /// ### Creating a Client
   /// - ``init(settings:)``
   ///
   /// ### Stream Operations
   /// - ``appendStream(_:events:options:)``
   /// - ``readStream(_:options:)``
   public class KurrentDBClient { }
   ```

2. **Include Examples**
   ```swift
   /// Appends events to a stream.
   ///
   /// ```swift
   /// let event = EventData(eventType: "OrderPlaced", model: order)
   /// try await client.appendStream("orders", events: [event])
   /// ```
   ```

3. **Articles and Tutorials**
   - Add tutorials to `Documentation/KurrentDB.docc/`
   - Use clear, step-by-step instructions
   - Include complete, working examples

### README and Guides

- Keep the README concise and focused
- Link to detailed documentation
- Update examples when APIs change

## 💬 Community

### Getting Help

- 💭 [GitHub Discussions](https://github.com/gradyzhuo/KurrentDB-Swift/discussions) - Ask questions
- 🐛 [Issues](https://github.com/gradyzhuo/KurrentDB-Swift/issues) - Report bugs
- 📧 Email: [your-email@example.com] - Direct contact

### Staying Updated

- Watch the repository for notifications
- Follow announcements in Discussions
- Check the changelog for updates

## 🎉 Recognition

Contributors will be:
- Listed in the project's contributors page
- Mentioned in release notes (for significant contributions)
- Given credit in documentation (when appropriate)

## ❓ Questions?

Don't hesitate to ask questions! You can:
- Open a discussion on GitHub
- Comment on an existing issue or PR
- Reach out directly

## 🙏 Thank You!

Your contributions, no matter how small, are valued and appreciated. Thank you for helping make KurrentDB-Swift better for everyone! 🚀

---

*This guide is adapted from contributing guidelines used by successful open-source projects. It's a living document and will evolve based on community feedback.*