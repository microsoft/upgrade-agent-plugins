# Karma / Jasmine to Vitest

Read this when the source project runs its tests with Karma and/or Jasmine and the target runner is
Vitest. It supplements the generic [framework-migration](../SKILL.md) workflow.

This is a **test-runner migration**: it replaces the runner, its configuration, and — where semantics
differ — spy behavior, matchers, async style, and browser environment. It must **not** change the
application's runtime behavior. Upgrading Karma/Jasmine *within* the same runner is a different task,
covered by [typescript-dependencies-upgrade/karma-jasmine.md](../../typescript-dependencies-upgrade/karma-jasmine.md);
that guide explicitly defers runner *replacement* to this migration.

**Core principle:** Preserve observable behavior and every project contract (runtime, install, test
semantics, types, coverage, build, CI), prove each from a clean supported environment, and disclose
whatever cannot be verified. Just passing tests is not enough.

> **Scope note:** the spy, matcher, and API-conversion sections below assume the specs use **Jasmine**.
> If Karma runs a different framework (Mocha, QUnit), apply only the runner/config/browser-environment
> guidance here and use that framework's own conversion guidance for spec APIs.

## Official guidance (authoritative — read before editing)

- Angular projects: [Migrating from Karma to Vitest](https://angular.dev/guide/testing/migrating-to-vitest)
  (the `@angular/build:unit-test` builder and the `refactor-jasmine-vitest` schematic).
- Vitest: [Config](https://vitest.dev/config/), [Mocking](https://vitest.dev/guide/mocking),
  [Test environment](https://vitest.dev/guide/environment), [Browser Mode](https://vitest.dev/guide/browser/).

Treat these as the source of truth for current APIs and configuration.

## Defaults (apply unless repository evidence shows otherwise)

- Preserve the current test-discovery globs, framework bootstrap, preprocessors, aliases, and
  environment constants.
- Run Vitest beside the existing Karma/Jasmine suite until the target suite is proven, then cut over.
- Keep `describe`/`it`/`expect` as globals (`globals: true`) to minimize spec churn (the Angular CLI
  builder enables globals for you). In a non-Angular TS project this only affects runtime — also add
  `"types": ["vitest/globals"]` to the test tsconfig and remove `@types/jasmine` so ambient types don't clash.
- Pick the environment from the existing suite's needs: `node` for Node-only specs, `jsdom`/`happy-dom`
  for DOM tests, and Browser Mode for tests that need real layout, canvas, or browser APIs. A Karma
  browser suite usually maps to a DOM emulator by default.
- Do not change production dependencies or application code to make tests pass.

## Inventory (parent Phase 1)

Record in `inventory.md`:

- **Runtime contract**, from `engines`, version files, CI images, containers, and deployment config —
  not from the developer machine.
- **Test baseline**: exact test-file count, test count, skipped count, runner exit status, and where
  coverage artifacts are written. Capture this via `typescript-runtime-validation` (see below).
- **Karma/Jasmine config**: `karma.conf.js` (frameworks, browsers, preprocessors, reporters,
  `karma-*` plugins, coverage (provider, reporters, thresholds, exclusions, output dir/filenames),
  `proxies`, `customLaunchers`, `client`), the bootstrap entry
  (`test.ts`/`src/test.ts`), `jasmine.json`, spec globs, custom matchers, global setup, fake-timer
  usage, Jasmine `random`/seed settings, any cross-file shared state, and the CI test command.
- **Build inputs the tests rely on**: templates, styles/SCSS, assets, path aliases, compile-time
  constants, polyfills.

Preserve the exact test-file and test counts through the migration — an unexplained drop means tests
were silently dropped, disabled, or merged.

## Compatibility matrix — choose the stack from the promised runtime, not the agent's host

Pick the Vitest ecosystem as one compatible unit against the **minimum promised runtime**, then pin
it. The rows below are the components that must all be chosen to work with each other and with that
runtime — not independent choices:

| Component | Inspect | Notes |
| --- | --- | --- |
| Node | `engines`, CI images, containers, deploy config | Vitest/Vite majors drop old Node fast — pin to versions that support the floor. |
| Package manager | CI, lockfile, docs | Keep the lockfile format the CI package manager supports. |
| TypeScript | compiler dep, framework requirement | Very old TS may not parse current Vitest type declarations. |
| Framework | Angular/React/Vue version | Use the framework's supported Vitest toolchain (plugin/builder). |
| Bundler + its plugins | Webpack/Vite/Rollup and their plugin peer ranges | These version together: keep the bundler and each plugin within their current majors and satisfy the published peer ranges instead of forcing a major bump. |
| Vitest stack | `vitest`, `vite`, DOM lib, coverage provider | Match `@vitest/*` packages (coverage, browser provider) to the Vitest generation; choose `vite` and the DOM lib by their own peer/`engines` ranges — they version independently. Satisfy published peers; don't force majors to match. |

Install must be reproducible: the repository's normal clean install (e.g. `npm ci`) must succeed from
the lockfile. Flags like `--legacy-peer-deps`, `--force`, or `--ignore-engines` are diagnosis aids,
never completion criteria — resolve the underlying peer conflict instead.

State explicitly whether the migration **preserves** the current runtime or **raises** it as a
coordinated, user-approved change.

## Configuration mapping

Reproduce the Karma pipeline in Vitest; do not simplify by deleting inputs.

| Karma / Jasmine | Vitest |
| --- | --- |
| `frameworks: ['jasmine']`, browser globals | `globals: true` (or import from `vitest`) |
| `browsers: ['Chrome']` (real browser) | `environment: 'happy-dom' \| 'jsdom'`, or Browser Mode for real browsers |
| preprocessors (ts/scss/templates) | Vite transform + framework plugin; keep the same template/style compilation |
| `files` (specs) | `test.include` |
| `files` (setup/order-loaded scripts) | `test.setupFiles` / explicit imports — do **not** dump the whole `files` array into `test.include` or fixtures run as tests |
| `files` (fixtures, served assets), `proxies` | Vite static serving / server config |
| bootstrap `test.ts`, polyfills | `test.setupFiles` |
| `karma-coverage` (Istanbul) | Prefer `@vitest/coverage-istanbul` to keep the same metrics. Switching to `@vitest/coverage-v8` changes the reported numbers, so treat it as a contract change (surface it and get sign-off) rather than a silent default. Set `coverage.reporter`, `coverage.exclude`. |
| reporters | `test.reporters` |
| `customLaunchers`, `client` | Browser Mode provider options / runner options — migrate deliberately |
| Jasmine `random: true` (default) | Vitest does **not** shuffle by default — set `sequence.shuffle` + `sequence.seed` if you rely on randomization, and record the seed |
| shared browser/module context across files | Vitest isolates files by default (`isolate: true`) — remove unintended cross-file coupling, or set `isolate: false` deliberately and document why (the Angular builder defaults isolation off to resemble Karma) |
| per-run isolation of fresh spies | `restoreMocks: true` (see spies below) |

Config skeleton (adapt paths/env; ESM-safe path handling):

```ts
import { defineConfig } from 'vitest/config';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const dir = path.dirname(fileURLToPath(import.meta.url));

export default defineConfig({
  test: {
    globals: true,
    environment: 'happy-dom',
    setupFiles: [path.resolve(dir, 'src/test-setup.ts')],
    include: ['src/**/*.spec.ts'],
    restoreMocks: true,
    coverage: { provider: 'istanbul', reporter: ['text', 'lcov', 'html'] },
  },
});
```

Install Vitest plus the environment and coverage packages the config references, using the
repository's declared package manager — do not force `npm i` in a Yarn or pnpm repo, which resolves a
different graph and can write a stray `package-lock.json` CI never uses:

- npm: `npm i -D vitest happy-dom @vitest/coverage-istanbul`
- yarn: `yarn add -D vitest happy-dom @vitest/coverage-istanbul`
- pnpm: `pnpm add -D vitest happy-dom @vitest/coverage-istanbul`

Use `@vitest/coverage-v8` only as the validated V8 choice. A `coverage.provider` named in config but
not installed fails coverage at runtime.

**Angular projects** use the CLI builder instead of a hand-written config. This path is **experimental**
and needs an Angular CLI new enough to ship `@angular/build:unit-test` plus the `application` build
system; if the workspace is older, treat the required Angular upgrade as a separate, coordinated
decision rather than forcing it here.

1. `npm i -D vitest jsdom` (or `happy-dom`); for real browsers, `@vitest/browser-playwright` + `playwright`.
2. In `angular.json`, set the `test` builder to `@angular/build:unit-test`. It defaults to
   `tsConfig: tsconfig.spec.json` and `buildTarget: ::development`.
3. The `unit-test` builder does **not** accept `polyfills`/`assets`/`styles` on the test target — move
   them to the build configuration named by `buildTarget` (create a dedicated `testing` config if the
   `development` one doesn't fit).
4. For `fakeAsync`/`waitForAsync`, add `zone.js/plugins/vitest-patch` to that build configuration's
   **polyfills** (not the test target); plan to move suites to native `async` + Vitest fake timers.
5. Use a custom `vitest.config.ts` via `runnerConfig` for options the builder doesn't expose directly —
   e.g. `restoreMocks: true`.

## Iterate efficiently (without weakening the final gate)

Prove the risky mechanics on a small sample before bulk-converting, so a wrong assumption fails in
minutes rather than after every spec is touched. The complete coverage/validation gate still applies at
completion.

- **Pilot one representative path per hard mechanism** before converting all specs — for an Angular
  project, one service relying on constructor-injected metadata, one component with template + styles
  under TestBed, and one async test — and confirm decorator/provider reflection, style inlining, and
  zone/async behavior work.
- **Sample one test per browser-API family early** (canvas, media/audio, storage, event timing,
  `matchMedia`) so simulator gaps surface before bulk work, not at the end.
- **Iterate with coverage off** on a single file or family for speed; still require coverage when you finish each family and at the final validation.
- **Reserve clean installs** for baseline establishment, completion, and reruns after a
  manifest/lockfile change; reuse the already-validated dependency tree for targeted spec iterations
  that don't touch dependencies.
- **Smoke-test long-running scripts immediately after any runtime change** (`dev`, watch, `start`,
  `server:*`) — a raised runtime can break them, and catching it early keeps it inside the runtime
  decision instead of forcing a late workaround.

## Spec and API conversion (Jasmine)

Convert in small categories and review each diff for **semantic** change, not just syntax. Angular's
`ng g @schematics/angular:refactor-jasmine-vitest` schematic mechanizes the common cases (`fit`/`fdescribe`
→ `it.only`/`describe.only`, `xit`/`xdescribe` → `.skip`, `spyOn` → `vi.spyOn`, `jasmine.createSpy`
→ `vi.fn`, `jasmine.objectContaining`/`any` → `expect.objectContaining`/`any`); it does **not** install
deps, edit `angular.json`, remove Karma files, or handle complex spies. Scope it in a workspace with
`--project` / `--include` / `--file-suffix`, and always review its output.

Track every high-risk construct to an explicit decision about how it maps to Vitest (its
*disposition*) so none is silently dropped or behavior-changed: default-stub spies,
`jasmine.createSpy`/`createSpyObj`, call inspection (`calls.count`/`argsFor`/`mostRecent`),
`done`/`done.fail` callbacks, fake timers, custom/asymmetric matchers, focused (`fit`/`fdescribe`) and
skipped (`xit`/`xdescribe`) tests, browser-API usage, and the templates/styles compiled into tests. The migration is not done while any occurrence lacks a reviewed
disposition, a default Jasmine stub silently became a call-through spy, or the focused/skipped counts
changed without an approved reason.

### Spies — the critical semantic difference

Jasmine's `spyOn` **stubs** by default (original does not run, returns `undefined`). Vitest's
`vi.spyOn` **calls through** to the original by default. A blind `spyOn → vi.spyOn` swap can run real
side effects — state changes, I/O, doubled events — and make tests pass for the wrong reason. Classify
every spy by intent:

| Jasmine intent | Jasmine | Vitest |
| --- | --- | --- |
| Stub (default) + record | `spyOn(o, 'm')` | `vi.spyOn(o, 'm').mockReturnValue(r)` — pick a type-valid stub return; `() => undefined` via `.mockImplementation` only for void methods |
| Call real + record | `spyOn(o, 'm').and.callThrough()` | `vi.spyOn(o, 'm')` (default) |
| Return fixed value | `.and.returnValue(v)` | `.mockReturnValue(v)` |
| Fake implementation | `.and.callFake(fn)` | `.mockImplementation(fn)` |
| Resolve / reject | `.and.resolveTo(v)` / `.and.rejectWith(e)` | `.mockResolvedValue(v)` / `.mockRejectedValue(e)` |
| Standalone spy | `jasmine.createSpy()` | `vi.fn()` |
| Inspect calls | `spy.calls.count()` / `.argsFor(i)` / `.mostRecent().args` | `spy.mock.calls.length` / `spy.mock.calls[i]` / `spy.mock.lastCall` |

Create spies in each test or `beforeEach`, and enable `restoreMocks: true` — it restores `vi.spyOn`
originals before each test. It does **not** reset standalone `vi.fn` mocks or restore fake timers; use
`vi.clearAllMocks()`/`mockReset()` for persistent `vi.fn` mocks and `vi.useRealTimers()` for timers.

### Matchers, asymmetric matchers, timers, custom matchers

| Jasmine | Vitest |
| --- | --- |
| `jasmine.objectContaining` / `arrayContaining` | `expect.objectContaining` / `arrayContaining` |
| `jasmine.any(T)` / `anything()` / `stringMatching` | `expect.any(T)` / `anything()` / `stringMatching` |
| `jasmine.clock().install()` / `.tick(n)` / `.uninstall()` | `vi.useFakeTimers()` / `vi.advanceTimersByTime(n)` / `vi.useRealTimers()` |
| `jasmine.addMatchers({...})` | `expect.extend({...})` (rewrite, not a rename — see below) |

- `advanceTimersByTime(n)` covers synchronous timer callbacks; when a callback schedules promise work,
  use `await vi.advanceTimersByTimeAsync(n)` (or `runAllTimersAsync`).
- `addMatchers → expect.extend` is a **rewrite, not a rename**: a Vitest matcher is the function itself
  returning `{ pass, message: () => string }` (Jasmine's is a factory returning `{ compare() }` with a
  string message), equality moves from `matchersUtil` to `this.equals`, and TS users must augment
  Vitest's `Matchers` interface.

Audit matchers whose operand is a browser/collection type (`DOMTokenList`, `NodeList`,
`HTMLCollection`). Vitest may not treat these as containment targets — prefer the native contract, e.g.
`expect(el.classList.contains('open')).toBe(true)` over `expect(el.classList).toContain('open')`.

### Async

Modern Vitest does **not** support `done`-callback tests, so converting them is required, not optional
modernization. If the operation already returns a promise, `await` it or return it. For a callback API,
wrap it: `return new Promise((resolve, reject) => op(err => err ? reject(err) : resolve()))`, mapping
`done.fail`/errors to rejection. The runner process must exit zero with no unhandled-rejection
warnings — a green test count alone is insufficient.

### Assertions

Do not weaken assertions during translation. For each: same state/value/identity? Argument assertions
not reduced to call-count? Can `NaN`/`undefined` now pass? Layout-dependent tests must assert
deterministic values, not merely that a callback ran.

## Browser fidelity

Karma runs real browsers; `jsdom`/`happy-dom` emulate one in Node and — most importantly — do not do
real layout. Beyond that they differ: `jsdom` has no `matchMedia` and needs the optional `canvas`
package for canvas, while `happy-dom` implements a subset of these APIs. Don't assume browser-accurate
rendering, geometry (`getBoundingClientRect`, non-zero `offsetWidth`), or media playback; verify against
the pinned environment version. Classify each test:

| Needs | Environment |
| --- | --- |
| Pure logic, state, reducers | `node` |
| Basic DOM render + events | `jsdom` / `happy-dom` |
| Real layout, CSS, focus, selection, canvas, media | Browser Mode (`@vitest/browser-playwright` or `@vitest/browser-webdriverio`) |

When a simulator gap must be faked, make the fake **suite-local, minimal, typed, asserted, and
restored** — implement only the contract under test and record meaningful interactions. Never install
broad global no-ops merely to silence errors, and never delete templates/styles to make components
compile — reproduce the original preprocessor inputs instead.

## Types and quality

Test execution (transpile) is not type checking. Type-check specs and setup via, in order of
preference: the project's existing compiler, official Vitest types, or a dedicated `tsconfig.spec.json`.
**Include the files production tsconfigs usually exclude** — setup files, test/async adapters, and any
migration-added ambient declarations — and wire the check as its own runtime-validation assertion (for
example a `test:typecheck` script running `tsc -p tsconfig.spec.json --noEmit`). Passing Vitest and a
production build do not prove excluded setup/adapter code is semantically valid.
For a compiler too old to parse current Vitest declarations, add a **minimal, isolated** compatibility
shim for only the APIs used — not blanket `any`, spec exclusion, or suppression comments; give
migration-added declarations the narrowest known return type (for example a raw/text loader `require`
returns `string`, not `any`). A shim is a temporary bridge, not a fix: prefer raising TypeScript (an
approved **contract change**) when the project can take it, and when you keep the shim, record "upgrade
TypeScript" as an explicit follow-up in the completion report. If the incompatibility is broad, offer
to upgrade TypeScript first as its own task before continuing the runner migration.

Run lint early (mocks should return typed values like `() => undefined`, not empty bodies). Search the
diff for and eliminate: `as any` / `as unknown as`, `@ts-ignore` / `@ts-expect-error`, disabled/focused
tests, leftover `jasmine`/`karma` APIs, and spies missing explicit behavior where Jasmine originally
stubbed.

## Conditional legacy workarounds (only when the project requires them)

Do not apply to modern projects by default; each is a compatibility mechanism, not a recommended default:

- **Legacy Angular + Zone.js**: a custom ProxyZone/Jasmine-patch bridge. Prefer the official
  `zone.js/plugins/vitest-patch`. If a custom adapter is unavoidable, preserve the full callable API
  (`it.only`/`skip`/`each`, timeout args, `this`, test args) and test sync/async/callback/skipped/
  focused/parameterized cases.
- **ESM/UMD module identity**: when the framework reports missing decorators/duplicate context despite
  visible metadata,   check for a framework installed twice or mixed ESM/UMD builds; de-duplicate to a single installed
  copy of the framework in a single module format (all ESM or all UMD, via inline/alias) before adding
  casts or metadata patches.
- **Obsolete production dependency exposed by the migration**: either keep the obsolete dependency
  working under the target runtime, or replace it with a pinned, immutable-source equivalent (a fixed
  version or commit, not a floating range); validate the production build; and document any equivalence
  you cannot prove — keep such production changes separate from the test migration.

## Runtime validation (this pair)

All executable validation is delegated to the
[`typescript-runtime-validation`](../../typescript-runtime-validation/SKILL.md) skill and its eval
plan; do not author a parallel harness. Because the test command itself changes (Karma → Vitest), this
is a **migration**, not an in-place upgrade replay — use two independent `standalone` runs and let this
skill own the comparison (do not try to mutate one plan between runs; `upgrade` mode aborts on a
plan-hash change).

1. **Source run (before edits):** invoke `typescript-runtime-validation` in `standalone` mode against
   the source project. Its plan should cover the Karma/Jasmine suite plus type-check, lint, coverage,
   and the production build. Record the results and the exact test-file/test/skip counts in
   `inventory.md`. Do not migrate on top of an unexplained red run — first decide plan defect vs.
   genuine pre-existing failure.
2. **Target run (after migrating):** author a fresh eval plan for the migrated project whose
   `tests-pass` assertion is the Vitest command (`vitest run`, or `ng test` once the builder is
   switched), and run `standalone` mode again.
3. **Compare:** the target must match the source run — same passing test count (unless a change is
   intentional and documented), coverage generated, production build green, and any server/integration
   tests green. Fix an invalid assertion as a plan defect; fix a real failure in the migrated
   config/spec. Never weaken a check to force a pass.

You must validate with the persisted `typescript-runtime-validation` result; a hand-run of the same
commands does **not** satisfy the gate. If the tool times out or cannot produce a fresh result whose
plan hash matches the final plan, the migration is incomplete — fix the plan/tool, do not backfill
validation by hand. Keep the plan efficient so it can finish within the tool's budget: don't repeat the
same expensive step (e.g. a full production build) inside several assertions. If source coverage never
executed, record that percentage parity with the target is **unverified** rather than implying it is
preserved.

## Cutover and Karma/Jasmine removal gates

Cut over only after the parent skill's approval gate (framework-migration Phase 5), and keep
`migration-plan.md` and `completion-report.md` current. Switch local dev, the `test` script/target, and
CI to Vitest, then remove the source runner only when:

- clean install succeeds from the lockfile with no bypass flags;
- all intended spec files are discovered and the test/skip counts match the baseline;
- every high-risk Jasmine construct (default-stub spies, `done` callbacks, custom matchers,
  focused/skipped tests, browser-API fakes) is reconciled to an explicit disposition — none silently
  dropped or behavior-changed;
- the Vitest process exits zero with no unhandled errors, and coverage is generated at paths CI still
  consumes (check CI publishing, badges, and artifact-upload steps for hard-coded coverage paths), and
  when the provider changed from Istanbul that is an **approved contract change** with metric-difference
  evidence (coverage *generated* is not coverage *semantics preserved*);
- production build, type-check, lint, and server/integration tests pass;
- every **retained** first-party script (the scripts kept after removing Karma-specific ones such as a
  `test:karma` — for example `start`, `dev`, `build`, `test`, `server:*`) still runs under the declared
  minimum runtime — do not leave a retained command broken by the target runtime, and do not rewrite a
  stable script's behavior to work around the runtime choice without a separate approval;
- `karma.conf.js`, the Karma bootstrap (`test.ts`), and all `karma`/`karma-*`/`jasmine*` dev
  dependencies are removed, with no remaining `karma`/`jasmine` imports, config, or script references;
- docs and scripts refer to Vitest;
- any layer that could not be verified (e.g. a container/E2E scenario without Docker) is explicitly
  documented as unverified rather than assumed passing.
