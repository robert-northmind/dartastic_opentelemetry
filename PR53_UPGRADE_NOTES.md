# PR #53 — review notes (temporary)

> **Temporary file — delete before merging.** Captures what changed on this
> branch and why, for review. Tracks issue #50 and PR #53.

## Problem (issue #50)

Calling an SDK provider accessor before `OTel.initialize()` crashed with an
opaque cast error:

```
type 'APITracerProvider' is not a subtype of type 'TracerProvider'
```

and, once that happened, `OTel.initialize()` refused to run ("can only be
initialized once").

### Root cause

- The API package auto-installs a spec-mandated **no-op `OTelAPIFactory`** the
  first time *any* API call runs (commonly resource detection, which is on by
  default). It "wins" the `OTelFactory.otelFactory` race.
- SDK accessors then did `OTelAPI.tracerProvider(name) as TracerProvider`. With
  the no-op API factory installed, the returned object is an `APITracerProvider`
  (not the SDK subtype `TracerProvider`), so the downcast throws.
- `OTel.initialize()` used `OTelFactory.otelFactory != null` as its
  "already initialized" signal, conflating the auto-installed no-op factory with
  a real user init — so it also threw.

## Approach

This replaces PR #53's original "throw a clearer error" approach with the
maintainer's preferred design (issue #50 comment): **the SDK upgrades an
installed no-op API factory to a real SDK factory**, mirroring how the
Java/JS/Python SDKs replace the global no-op provider once the SDK is installed.
The public accessors keep returning concrete SDK types (no breaking API change).

## What changed (`lib/src/otel.dart`)

- **`_ensureSDKFactory({endpoint, serviceName, serviceVersion})`** — single
  chokepoint that returns the installed `OTelSDKFactory`, upgrading from (or
  installing over) a no-op `OTelAPIFactory` when needed. A *new* factory
  instance is installed on upgrade, which discards any no-op providers the API
  factory had cached; the API package re-syncs its own cached factory on its
  next call.
- **`_getAndCacheOtelFactory()`** now delegates to `_ensureSDKFactory()`. This
  also fixes a latent stale-cache bug (the previous version returned an eagerly
  cached factory even after the global was swapped).
- **`_userInitialized` flag** decouples "initialized" from "a factory exists".
  `initialize()` now:
  - throws only on a genuine second `initialize()` call (preserves the existing
    one-shot contract; matches Java's `GlobalOpenTelemetry.set`);
  - overwrites a no-op API factory or a provisional default SDK factory with the
    fully-configured factory;
  - still throws for a *foreign* (non-API, non-SDK) factory — defensive only;
    reachable solely if user code installed a custom `OTelFactory` subclass.
- **`OTel.isInitialized`** getter added; **`OTel.reset()`** clears
  `_userInitialized`.

### Behavior change to be aware of

Calling any `OTel.*` entry point before `initialize()` now **provisionally
upgrades** to a default SDK factory (no exporters/processors, so it exports
nothing) instead of throwing. A later `initialize()` replaces it with the
configured factory. Previously these calls threw `StateError`.

## Tests

- `test/unit/otel_initialization_error_test.dart` — rewritten to assert the
  upgrade behavior: API-factory-then-accessor no longer crashes (the exact #50
  repro); API-touch-then-`initialize()` succeeds; double `initialize()` throws;
  provisional-then-`initialize()` applies the configured service name;
  `reset()` re-enables `initialize()`.
- `test/unit/otel_sdk_test.dart` — updated the obsolete "throws when not
  initialized" case to assert the provisional upgrade instead.

> Not run in CI from this environment (no Dart toolchain available here).
> Run `dart pub get && dart analyze && dart test` locally.

## Open questions for review

1. **Scope of upgrade** — `_getAndCacheOtelFactory()` routes *all* callers
   (incl. pure-API helpers like `OTel.attributeString()` / `contextKey()`)
   through the upgrade. Acceptable ("using the `OTel` class implies SDK
   intent"), but could be narrowed to provider accessors only.
2. **Foreign-factory guard in `initialize()`** — defensive and effectively
   unreachable. Could be dropped so `initialize()` simply always overwrites; the
   guard in `_ensureSDKFactory()` (accessor path) is the valuable one because it
   prevents the opaque cast crash.

## Related

- API PR `dartastic_opentelemetry_api#26` (adds `_userInitialized` to the *API*)
  is not needed for this fix and should be closed — the SDK never routes through
  `OTelAPI.initialize()`, and the fix belongs in the SDK. The `_userInitialized`
  idea from it is applied here, in the SDK.
