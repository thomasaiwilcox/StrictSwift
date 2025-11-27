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
