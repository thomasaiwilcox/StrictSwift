⸻

📄 StrictSwift – Product Requirements Document (PRD)

A strict, production-grade static analysis tool for Swift 6+ codebases that enforces an opt-in subset of Swift aligned with Rust-grade safety guarantees.

⸻

1. Purpose

Swift's move into backend, infrastructure, and safety-critical contexts introduced concurrency primitives and ownership hints, but teams still rely on review discipline and ad-hoc linting. StrictSwift provides a purpose-built enforcement layer that catches concurrency, architecture, semantic, and memory risks before code reaches production.

The tool targets the modules where failure is unacceptable:
	•	foundational backend services and daemons
	•	core infrastructure / engine crates
	•	performance-sensitive algorithms and pipelines
	•	long-lived worker processes and controllers
	•	security- or safety-critical components

StrictSwift enables “Critical Swift Mode”: a gate where only code complying with explicit safety rules may land.

⸻

2. Vision & Principles

StrictSwift bridges Swift’s expressiveness with Rust’s safety culture. It should feel like turning on the borrow checker and Clippy for select Swift modules—without abandoning Swift or rewriting libraries.

Guiding principles:
	•	Safety before convenience: default to error-level diagnostics for high-impact issues.
	•	Deterministic enforcement: results must be reproducible in CI, local CLI, and IDE integrations.
	•	Adoptable strictness: profiles and baselines make it possible to ratchet enforcement gradually.
	•	Transparent reasoning: every violation references ownership, concurrency, or architecture evidence.
	•	AI-friendly: machine-readable output enables automated fixes and auditing.
	•	Extensible: third parties can ship rule bundles that inherit the same guarantees.

⸻

3. Non-Goals

StrictSwift is not:
	•	a formatter (SwiftFormat already solves layout)
	•	a generic style linter (SwiftLint handles naming, whitespace, etc.)
	•	a compiler replacement or optimizer
	•	a full formal-verification system (but it can feed one)
	•	a domain-specific appliance (it stays general-purpose infrastructure)

⸻

4. Personas

1. Infrastructure / Critical-Systems Developer — wants Rust-grade safety without leaving Swift.
2. Backend Engineer — needs concurrency guarantees, dependency hygiene, and predictable performance.
3. Team Lead / Enterprise Architect — requires enforceable policies and audit trails for compliance.
4. OSS Maintainer — needs consistent contributions and automated guardrails for reviewers.
5. AI-assisted Developer — expects structured diagnostics their agent can consume.
6. Rust Refugee — appreciates Swift ergonomics but misses Rust’s ownership discipline.

⸻

5. Core Value Propositions
	•	Extreme Strictness: default-deny attitude toward risky patterns.
	•	Reliability: compile-time enforcement of concurrency, ownership, and memory safety invariants.
	•	Architecture Governance: keeps modules layered and dependency-safe.
	•	Performance Awareness: highlights ARC-heavy or allocation-prone code paths early.
	•	Predictability: keeps codebases small, testable, and reasoned about in isolation.
	•	AI Compatibility: exports JSON/graph data that copilots can reason about.
	•	Adoption Support: baselines + profiles make it feasible to roll out incrementally.

⸻

6. Product Overview

6.1 Architectural Summary
	•	Input: Swift source files (SwiftSyntax AST) + config file + optional baseline file.
	•	Analysis Pipeline:
		◦	Parser builds AST + symbol table.
		◦	Ownership Graph Builder annotates borrows, moves, escapes.
		◦	Rule Engine evaluates configured rules with cross-file context.
		◦	Reporter produces human diagnostics, JSON, and audit artifacts.
	•	Extensibility: rule engine exposes plugin API with stable rule metadata.
	•	Execution surfaces: CLI, SwiftPM build plugin, SourceKit-LSP service.

6.2 Workflow Snapshot
	1. `swift-strict baseline --profile critical-core` captures existing violations.
	2. Developers run `swift-strict check` locally for fast feedback (human output).
	3. CI runs `swift-strict ci --format json-detailed --fail-on error` using baselines.
	4. `swift-strict fix` provides safe automated rewrites for confined patterns.
	5. Teams review `swift-strict audit` reports before release to prove safety posture.

⸻

7. Rule Coverage & Scope

StrictSwift groups rules into families with phased depth. MVP scope focuses on high-signal issues; later releases deepen analysis.

7.1 Memory & Ownership
	MVP:
		•	Detect escaping references that can outlive their owner (dangling risk).
		•	Enforce exclusive mutable access when multiple borrows exist.
		•	Flag weak/unowned usage that can lead to use-after-free in async contexts.
	Later:
		•	Lifetime region inference with annotations when compiler hints are missing.
		•	Move-only type enforcement and copy-cost modeling.
		•	Capability tracking across actor hops.

7.2 Concurrency & Isolation
	MVP:
		•	Non-Sendable captures inside `@Sendable` closures.
		•	Mutable shared state touched from async contexts without isolation.
		•	Unstructured concurrency (fire-and-forget `Task {}` without ownership transfer).
		•	Actor isolation violations and `@unchecked Sendable` without proof comments.
	Later:
		•	Deadlock heuristics through lock-order analysis.
		•	Concurrency region inference and effect tracking.
		•	Async resource lifetime modeling.

7.3 Architecture, Dependencies & Imports
	MVP:
		•	Module-level cycle detection with directional rules.
		•	Type-level retain cycle heuristics (delegates, closure captures).
		•	File length, type count, and “god-type” limits for critical modules.
		•	Layer rules (domain → infra → platform) expressed in config.
	Later:
		•	Stable ABI contract checks and API versioning gates.
		•	Automatic dependency graph visualization exports.

7.4 API, Error Handling & Robustness
	MVP:
		•	Ban `force unwrap`, `try!`, `fatalError`, and raw `print` in production modules unless annotated.
		•	Require explicit error propagation for functions returning `Result`/`async throws`.
		•	Ensure public API entry points document error and threading guarantees.
	Later:
		•	Effect-system metadata for pure/impure separation.
		•	Policy hooks to enforce documentation examples.

7.5 Performance & Size Heuristics
	MVP:
		•	Highlight repeated allocations, ARC churn, and large struct copies inside hot loops (configurable).
		•	Warn on reference types inside algorithmic hot spots flagged in config.
	Later:
		•	SIL-level ARC inspection and zero-cost abstraction verification.
		•	Generic specialization bloat detection.

7.6 Unsafe Boundaries & Auditing
	MVP:
		•	Require explicit `// @strictswift:unsafe` markers with rationale.
		•	Audit unsafe blocks for invariant checklist compliance.
		•	Track boundary modules that expose unsafe APIs and ensure isolation.
	Later:
		•	Automatic documentation bundles for auditors.
		•	Detection of “unsafe but could be safe” regions with fix suggestions.

⸻

8. Configuration & Profiles

Profiles allow teams to pick the strictness they can tolerate:

	•	critical-core (default for infra modules) — errors for concurrency, architecture, and safety rules; warnings for select performance heuristics.
	•	server-default — balances productivity and safety; concurrency/ownership issues are errors, structural/perf issues warnings.
	•	library-strict — focuses on public API stability, module layering, and documentation completeness.
	•	app-relaxed — light-touch checks (unsafe APIs, obvious concurrency mistakes) for UI/prototype code.
	•	rust-inspired (beta) — opt-in profile applying Rust-inspired safety patterns, activated per-target only after the verification suite passes.

Configuration example:

```
profile: critical-core

rules:
  memory:
    detect_escaping_mutable: error
    enforce_exclusive_mutation: error
    weak_use_after_free: warning
  concurrency:
    require_sendable_capture: error
    unstructured_task: error
    mutable_global_state: error
  architecture:
    max_file_length: 350
    layered_dependencies:
      application → services → core → platform
  safety:
    force_unwrap: error
    try_bang: error
    fatal_error_without_annotation: error
  performance:
    large_struct_copy: warning
    arc_hot_path: warning
baseline: .strictswift-baseline.json
```

⸻

9. Adoption & Migration

	•	Baseline files record known violations so legacy code can adopt StrictSwift without blocking merges.
	•	`swift-strict migrate --from server-default --to critical-core` emits a step-by-step checklist (rules newly enforced, suggested refactors).
	•	Severity overrides can be scoped per-target or per-path to support carve-outs.
	•	Telemetry (opt-in) captures most common violations to inform default tuning.
	•	`swift-strict explain <rule>` links diagnostics to documentation, rationale, and remediation examples.

⸻

10. Output & Reporting

10.1 Human Diagnostics
Rust-style, actionable errors:

```
ERROR [Concurrency.non_sendable_capture]
  Non-Sendable value 'Cache' captured inside @Sendable closure.
  File: Sources/Engine/CacheWorker.swift:54
  Fix: mark Cache as Sendable or capture a Sendable wrapper (weak or actor hop).
```

10.2 Machine Output
Structured JSON for CI, AI assistants, and auditing:

```
{
  "version": 2,
  "profile": "critical-core",
  "baseline_applied": true,
  "summary": {
    "errors": 3,
    "warnings": 5,
    "analysis_time_ms": 480
  },
  "violations": [
    {
      "rule_id": "concurrency.non_sendable_capture",
      "severity": "error",
      "message": "Non-Sendable value 'Cache' captured…",
      "locations": [{"file": "Sources/Engine/CacheWorker.swift", "line": 54}],
      "ownership_context": "mutable_borrow",
      "suggested_fixes": ["wrap Cache inside Actor CacheHandle"]
    }
  ],
  "ownership_graph": {...},
  "unsafe_audit": {...}
}
```

10.3 Baselines & Audit Artifacts
	•	`.strictswift-baseline.json` stores fingerprinted violations with expiry dates.
	•	`strictswift-audit/` directory (optional) captures unsafe reviews and architecture graphs for compliance.

⸻

11. CLI & Automation

	•	`swift-strict check [path]` — local analysis with smart defaults.
	•	`swift-strict ci` — deterministic CI mode (non-interactive, JSON by default).
	•	`swift-strict baseline` — create/update baseline file with optional expiry.
	•	`swift-strict fix` — safe autofixes (capture lists, annotation insertion, import trimming).
	•	`swift-strict audit` — generate HTML/PDF summary of safety posture.
	•	`swift-strict unsafe-scan` — list unsafe blocks + owners.
	•	`swift-strict dependency-graph` — emit DOT/JSON graphs for viz tooling.
	•	`swift-strict profile-tune` — suggest rule thresholds from telemetry.
	•	`swift-strict benchmark` — run verification suite against sample packages.

⸻

12. SwiftPM Plugin & IDE Integration

	•	SwiftPM build plugin runs StrictSwift automatically for `release` and optionally `debug` builds; fails on error-level diagnostics according to profile.
	•	Supports incremental analysis by caching AST fragments per file.
	•	SourceKit-LSP integration surfaces diagnostics inline with quick-fix links.
	•	Xcode plugin (post-MVP) reuses same JSON protocol to avoid divergence.

⸻

13. Verification & Benchmark Harness

	•	Open-source harness runs StrictSwift against representative Swift packages (Vapor, AsyncHTTPClient, SwiftNIO samples, internal microservices).
	•	Each release must publish performance numbers (wall time, memory) and accuracy deltas (precision/recall for seeded violations).
	•	"Rust-inspired" profile graduates from beta only after passing the harness cases covering concurrency, ownership, and unsafe boundaries.
	•	Benchmarks execute nightly to catch regressions; results feed `swift-strict benchmark`.

⸻

14. Performance & Accuracy Targets

	•	Analyze 100k LOC ≤ 8 seconds on an 8-core laptop (baseline profile, warm cache).
	•	Incremental single-file analysis ≤ 300 ms (95th percentile).
	•	Memory footprint ≤ 750 MB for 100k LOC run.
	•	False-positive rate ≤ 5% for default profiles; <2% goal post-1.1.
	•	False-negative rate tracked via seeded test suite; aim for ≥95% detection of curated issues in harness.
	•	No compiler invocation; AST supplied via SwiftSyntax/SourceKit.

⸻

15. Extensibility & Plugin Strategy

	•	Rule bundles declare metadata (id, category, inputs, severity defaults, stability level).
	•	Plugins run inside the StrictSwift process with capability sandboxing (read-only AST, no filesystem writes).
	•	Versioned Rule API ensures compatibility as StrictSwift evolves.
	•	Marketplace-style registry (OSS first) lists vetted bundles such as `strictswift-network`, `strictswift-security`.
	•	Enterprise plugins can expose private diagnostics while still reporting aggregate counts for compliance.

⸻

16. Metrics

Technical:
	•	Median analysis time per LOC.
	•	False-positive / false-negative rates from harness.
	•	Adoption of incremental engine in IDE/SwiftPM plugin.

Adoption & Community:
	•	Number of repos using StrictSwift in CI.
	•	# of third-party rule bundles downloaded.
	•	Stars / contributors / community rulesets.

Business Impact:
	•	Reduction in production incidents attributed to concurrency or unsafe code.
	•	Average reviewer time saved on critical modules.
	•	Lead time to merge for safety-critical codepaths.

⸻

17. Risks & Mitigations
	•	Over-strictness blocking adoption → mitigated via baselines, per-rule overrides, and migration tooling.
	•	Performance regressions → mitigated by benchmark harness + incremental cache.
	•	False positives eroding trust → mitigated by explainable diagnostics, rule tuning, and telemetry-driven thresholds.
	•	Profile drift across execution surfaces → mitigated by single configuration source + hash embedded in reports.
	•	Plugin security concerns → mitigated by sandboxed rule API and signed bundle metadata.

⸻

18. MVP Scope (v1.0)

Must have:
	•	CLI (`check`, `ci`, `baseline`) + config loader.
	•	Module/type dependency cycle detection with layering rules.
	•	Concurrency safety checks (Sendable capture, mutable globals, actor isolation).
	•	Memory/ownership heuristics (escaping mutable references, weak use-after-free).
	•	Extreme-safety rules (`!`, `try!`, `fatalError`, `@unchecked Sendable`).
	•	Complexity & monolith detection (file length, type count, cyclomatic cap).
	•	Human diagnostics + JSON output + baseline file support.
	•	Unsafe block tracking with audit report.

Should have (v1.1 target):
	•	Autofix suggestions for common rule violations.
	•	Performance heuristics (ARC churn, large struct copy).
	•	Dependency graph visualization command.
	•	SourceKit-LSP surfacing of diagnostics.

Could have (post-1.1):
	•	SIL-aware ARC inspection.
	•	Effect-system metadata.
	•	AI-driven fix ranking based on telemetry.

⸻

19. Roadmap Highlights

	v1.1 — autofixes, telemetry-tuned thresholds, SourceKit integration, expanded performance heuristics.
	v1.3 — rust-inspired profile graduation (after harness validation), move-only enforcement, actor region inference beta.
	v2.0 — formal verification hooks, linear-type experiments, automated refactoring engine powered by rule metadata.

⸻

20. Success Criteria for Launch

StrictSwift v1 is successful when:
	1. At least one major Swift backend or infrastructure project enforces `critical-core` in CI.
	2. Participating teams report measurable reductions in concurrency or unsafe-code incidents.
	3. The verification harness shows ≤5% false positives and ≥95% detection on seeded issues.
	4. IDE (SourceKit-LSP) users receive the same diagnostics as CLI/CI runs.
	5. Third-party rule authors begin publishing vetted bundles, demonstrating extensibility.
	6. Security/compliance stakeholders can reference `swift-strict audit` outputs during reviews.

⸻

StrictSwift creates a pragmatic “Critical Swift Mode” by combining Rust-inspired safety rules with adoptable workflows, letting teams raise the confidence bar for their most important Swift code.
