# StrictSwift

A strict, production-grade static analysis tool for Swift 6+ codebases that enforces an opt-in subset of Swift aligned with Rust-grade safety guarantees.

## Purpose

StrictSwift provides a purpose-built enforcement layer that catches concurrency, architecture, semantic, and memory risks before code reaches production. It enables "Critical Swift Mode" for modules where failure is unacceptable.

## Vision

StrictSwift bridges Swift's expressiveness with Rust's safety culture, bringing the borrow checker and Clippy experience to Swift modules without abandoning the ecosystem.

## Quick Start

### Installation

```bash
# Clone the repository
git clone https://github.com/thomasaiwilcox/StrictSwift.git
cd StrictSwift

# Build the tool
swift build

# Install globally (optional)
swift build -c release
cp .build/release/swift-strict /usr/local/bin/
```

### Usage

```bash
# Analyze Swift files
swift run swift-strict check Sources/

# Enable incremental analysis with caching (13x faster on repeat runs)
swift run swift-strict check Sources/ --cache --cache-stats

# Create baseline for existing code
swift run swift-strict baseline Sources/ --profile critical-core

# Run in CI with JSON output
swift run swift-strict ci Sources/ --format json

# Use different profiles
swift run swift-strict check Sources/ --profile rust-inspired
```

### SwiftPM Plugin

Add StrictSwift as a build tool plugin to your package:

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/thomasaiwilcox/StrictSwift.git", from: "1.0.0"),
],
targets: [
    .target(
        name: "YourTarget",
        plugins: [.plugin(name: "StrictSwiftPlugin", package: "StrictSwift")]
    ),
]
```

## Profiles

- **critical-core**: Errors for concurrency, architecture, and safety rules
- **server-default**: Balanced productivity and safety
- **library-strict**: API stability focus
- **app-relaxed**: Light checks for UI code
- **rust-inspired** (beta): Maximum strictness with Rust-inspired safety patterns

## Development

```bash
# Run tests
swift test

# Run with coverage
swift test --enable-code-coverage
```

## Documentation

See the [Implementation Plan](PHASE_0_IMPLEMENTATION.md) for detailed development phases.

## License

MIT