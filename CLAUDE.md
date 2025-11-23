# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

StrictSwift is a static analysis tool for Swift 6+ codebases focused on extreme reliability and robustness. It's designed to enforce a strict subset of Swift suitable for critical backend services, infrastructure modules, and performance-sensitive code.

## Architecture

StrictSwift is built around these core components:

1. **SwiftSyntax-based AST Analysis** - Parses Swift source code using SwiftSyntax to build an Abstract Syntax Tree
2. **Modular Rule Engine** - Plugin-based architecture for different rule categories
3. **Dual Output System** - Generates both human-readable diagnostics and AI-agent JSON output
4. **Configuration Profiles** - Predefined profiles (critical-core, server-default, library-strict, app-relaxed) with different strictness levels

## Rule Categories

The tool analyzes code across multiple dimensions:

1. **Concurrency Safety** - Enforces Swift 6+ concurrency patterns, actor isolation, and Sendable compliance
2. **Value Semantics & Ownership** - Discourages class usage, detects retain cycles, promotes move-only types
3. **Performance Risk** - Identifies allocation hotspots, ARC-heavy patterns, and inefficient functional chains
4. **Robustness/Safety** - Bans force unwraps, try!, fatalError in production code
5. **Architectural Rules** - Enforces layered design, prevents god objects and monolithic files
6. **Dependency Integrity** - Detects circular dependencies at module and type levels
7. **Complexity & Monolith Detection** - Enforces limits on function length, nesting depth, and cyclomatic complexity

## Development Workflow

Since this is a new project (only PRD exists), the initial development should focus on:

1. Setting up the Swift Package structure with Package.swift
2. Creating Sources/ and Tests/ directories
3. Implementing core AST parsing infrastructure
4. Building the rule engine plugin system
5. Creating the CLI interface

## Key Requirements

- Performance target: Analyze 100k LOC in < 2 seconds
- Parallel AST passes for speed
- No compiler invocation required - pure SwiftSyntax analysis
- Must support both CLI and SwiftPM plugin integration
- JSON output format must be machine-readable for AI tools

## Configuration System

The tool uses YAML configuration with profiles. The most important profile is `critical-core` which:
- Uses errors for all violations (no warnings)
- Applies shortest thresholds for all limits
- Most restrictive policy across all rule categories