# StrictSwift

A strict, production-grade static analysis tool for Swift 6+ codebases that enforces an opt-in subset of Swift aligned with Rust-grade safety guarantees.

## Purpose

StrictSwift provides a purpose-built enforcement layer that catches concurrency, architecture, semantic, and memory risks before code reaches production. It enables "Critical Swift Mode" for modules where failure is unacceptable.

## Vision

StrictSwift bridges Swift's expressiveness with Rust's safety culture, bringing the borrow checker and Clippy experience to Swift modules without abandoning the ecosystem.

## Quick Start

```bash
# Install locally
git clone https://github.com/your-org/StrictSwift.git
cd StrictSwift
swift build

# Run analysis
swift run swift-strict check Sources/

# Create baseline for existing code
swift run swift-strict baseline --profile critical-core

# Run in CI
swift run swift-strict ci --format json
```

## Profiles

- **critical-core**: Errors for concurrency, architecture, and safety rules
- **server-default**: Balanced productivity and safety
- **library-strict**: API stability focus
- **app-relaxed**: Light checks for UI code
- **rust-equivalent** (beta): Rust-grade guarantees

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