# Rules Roadmap

## Optional & Error Safety
- **ForceCastRule**: flag `as!` outside tests or guarded contexts.
- **TryOptionalUsageRule**: warn when `try?` results are unused or immediately discarded.
- **TryQuestionMarkHandlingRule**: require handling of `try?` return values, offering guidance to convert to `do/catch` or propagate errors.
- **ConcealedErrorRule**: flag functions that call multiple throwing APIs but swallow/convert failures into magic values instead of `throws`/`Result`.

## Closure Capture & Memory
- **WeakSelfCaptureRule**: require `[weak self]` in escaping closures for UI/network APIs when `self` is referenced.
- **UnownedCaptureRule**: flag `[unowned self]` in escaping closures unless justified (e.g., short-lived timers).
- **WeakDelegateRule**: enforce `weak var delegate` for class-bound protocols and delegate/dataSource properties.
- **RetainCyclePathRule**: detect reference cycles via closure properties/tasks stored on `self`, requiring `[weak self]` or annotations.
- **StructPreferencingRule**: flag classes that are effectively immutable or single-threaded; recommend converting to `struct`.

## Concurrency & Threading
- **MainThreadUIRule**: detect UI mutations from non-main contexts unless `@MainActor` or dispatched to `.main`.
- **TaskDetachedRule**: discourage `Task.detached` unless explicitly documented and non-UI.
- **FireAndForgetTaskRule**: warn when `Task {}` handles aren’t stored or awaited outside SwiftUI `.task`.
- **MixedConcurrencyAbstractionRule**: flag `Task` inside `DispatchQueue.async` (and vice versa) to encourage one abstraction.
- **AsyncEscapeRule**: flag synchronous functions starting long-lived tasks without exposing async signatures/handles.

## Availability & API Usage
- **DeprecatedAPIRule**: detect calls to APIs marked `@available(*, deprecated, …)` and surface replacement messages.
- **AvailabilityCheckRule**: require `if #available` / `@available` when invoking APIs above the deployment target.
- **NotificationObserverRule**: enforce removal of selector-based observers or require token-based APIs in `deinit`.
- **SensitiveDefaultsRule**: warn when `UserDefaults` keys contain `password`, `token`, `secret`, etc.; suggest Keychain.
- **UnusedImportRule**: detect imported modules that contribute no symbols (e.g., SwiftUI in CLI targets).
- **ReflectionUsageRule**: warn when Mirror/performSelector/Any existentials appear in hot or security-sensitive modules.

## Code Quality & Enforcement
- **UnimplementedCodeRule**: block `fatalError("Not implemented")`, `TODO`, `FIXME` outside tests unless explicitly annotated.
- **PublicDocumentationRule**: require doc comments for `public`/`open` APIs and `/// - Throws:` sections on throwing functions.

## Allocation & Performance Visibility
- **AllocationInHotPathRule**: detect heap allocations (Array growth, bridging, closure captures) inside loops or annotated “hot” functions.
- **CoWAmplificationRule**: flag large-value copies (Arrays/Data/structs) passed into escaping closures or copied repeatedly.
- **ExpensiveGetterRule**: warn when property getters/operators/Equatable/hash implementations perform I/O, JSON parsing, or heavy work.
- **PureFunctionSideEffectRule**: if a function signature looks pure (value types in/out, no throws/async), flag global state writes, I/O, or logging.

## Numeric & Bounds Safety
- **ExplicitWrappingIntentRule**: in low-level modules, require `&+`/`&-` where wrapping arithmetic is intended; flag ambiguous use of `+`/`-`.
- **BoundsCheckRule**: detect array subscripts derived from untrusted input without dominating guards (`if index < count`).

## Unsafe & FFI Boundaries
- **UnsafeAPIRestrictionRule**: limit `Unsafe*` usage to whitelisted modules or require explicit annotations.
- **FFINullCheckRule**: ensure C/ObjC-returned pointers are checked for null; convert error codes into Swift `Error`.
- **UnsafeGuardRule**: require bounds/type checks to precede pointer arithmetic in unsafe blocks (`assumingMemoryBound` etc.).

## Build Configuration Hygiene
- **BuildFlagBranchRule**: detect runtime `if isDebug` toggles and recommend `#if DEBUG` or type-level configuration for Zig-like explicitness.

---

## Advanced Concurrency & Memory Safety Rules

### Thread Safety Analysis
- **FalseSharingRule**: Detect when different threads modify adjacent memory locations that share cache lines
- **ThreadLocalLeakageRule**: Detect thread-local values escaping their intended scope
- **LockInversionRule**: Identify potential deadlock patterns in async/await code
- **TaskPriorityInversionRule**: Detect when high-priority tasks wait on low-priority resources

### Deep Sendable Analysis
- **DeepSendableRule**: Beyond surface-level Sendable conformance, check all nested types recursively
- **ConditionalSendableRule**: Detect types that are only Sendable under certain conditions
- **RuntimeSendableViolationRule**: Find cases where Sendable types are used in non-Sendable contexts

---

## Complex Code Pattern Detection

### Cognitive Complexity
- **NestedCognitiveLoadRule**: Measure mental effort required to understand code flow beyond simple nesting
- **ControlFlowEntanglementRule**: Detect spaghetti code patterns beyond cyclomatic complexity
- **BooleanLogicComplexityRule**: Flag overly complex conditional expressions (e.g., nested ternaries, complex De Morgan)

### Drift Analysis
- **InterfaceImplementationDriftRule**: Detect when implementations diverge from documented behavior
- **APIContractViolationRule**: Find breaches of implicit contracts (e.g., functions that shouldn't throw)
- **InvariantViolationRule**: Detect code that could break class invariants

---

## Architectural Smell Detection

### Dependency Rule Enforcement
- **StableDependenciesPrincipleRule**: Detect dependencies on less stable modules
- **AcyclicDependenciesRule**: Enforce that dependency graphs must be DAGs (already exists as CircularDependencyRule)
- **DependencyDistanceMetricsRule**: Flag dependencies that are "too far" in the architecture

### Domain Rule Violations
- **UbiquitousLanguageComplianceRule**: Ensure code uses proper domain terminology
- **BoundedContextLeaksRule**: Detect when domain concepts leak between contexts
- **AggregateRootViolationRule**: Identify improper direct access to internal entities

---

## Performance Pattern Analysis

### Memory Access Patterns
- **CacheLineAnalysisRule**: Detect patterns that cause cache misses
- **MemoryLayoutOptimizationRule**: Identify struct reordering opportunities for better cache utilization
- **ZeroCopyMissedOpportunityRule**: Find missed opportunities for zero-copy operations

### Algorithmic Complexity
- **HiddenQuadraticPatternRule**: Detect O(n²) algorithms disguised as linear operations
- **UnnecessaryAllocationRule**: Find allocations that could be avoided
- **EscapingClosureAnalysisRule**: Detect closures that capture more than necessary

---

## Advanced Security Patterns

### Side-Channel Attack Prevention
- **TimingAttackVectorRule**: Detect code vulnerable to timing attacks
- **PowerAnalysisResistanceRule**: Identify patterns that leak information through power usage
- **CacheAttackSurfaceRule**: Find code vulnerable to cache-based attacks

### Cryptographic Validation
- **DeprecatedCryptoUsageRule**: Detect use of deprecated cryptographic primitives
- **KeyManagementViolationRule**: Improper handling of cryptographic keys
- **RandomnessQualityRule**: Detect use of insufficient randomness for security operations

---

## Business Logic Validation

### State Machine Integrity
- **InvalidStateTransitionRule**: Detect illegal state changes
- **StateConsistencyRule**: Ensure object state remains consistent across operations
- **EventSourcingViolationRule**: Validate event sourcing patterns

### Resource Lifecycle Management
- **ResourceLeakRule**: Beyond ARC - detect file handles, network connections, etc.
- **DoubleCheckedLockingRule**: Find incorrect implementations of this pattern
- **RAIIViolationRule**: Detect improper resource acquisition patterns

---

## Meta-Analysis Rules

### Code Evolution Metrics
- **CodeChurnAnalysisRule**: Identify areas with frequent changes
- **BugHotspotPredictionRule**: Use historical data to predict likely bug locations
- **TechnicalDebtAssessmentRule**: Quantify technical debt based on code metrics

### Test Quality Analysis
- **MutationTestingRule**: Assess test quality by suggesting code mutations
- **CoverageQualityRule**: Measure if tests actually exercise edge cases
- **TestIsolationRule**: Detect tests that depend on each other (already exists as TestIsolationRule)

---

## Swift-Specific Advanced Rules

### Swift Concurrency Deep Analysis
- **ActorReentrancyIssueRule**: Detect re-entrancy problems in actor methods
- **AsyncSequenceBackpressureRule**: Find missing backpressure handling
- **ContinuationMisuseRule**: Detect unsafe continuation patterns

### Type System Abuse Detection
- **OptionalChainingDepthRule**: Limit nesting to prevent unreadable code
- **ForceCastSafetyRule**: Detect unsafe force casts that might crash
- **ProtocolWitnessViolationRule**: Ensure custom implementations match protocol semantics

### Memory Ownership Patterns
- **MoveSemanticsViolationRule**: Detect improper value movement
- **BorrowingRuleInfringementRule**: Find violations of Swift's borrowing rules
- **ExclusivityBreachRule**: Detect simultaneous access to mutable state
