# `tests-pass` assertion — detect, generate, emit

Every eval plan should run the project's unit tests as part of validation. This file covers two cases:

1. **The project already has a usable test script** → emit one assertion that runs it.
2. **The project has no test script** → generate Vitest tests for the source files affected by the upcoming upgrades, add a `test` script, then emit the assertion.

The assertion uses `verificationMethod: "test-results"`: the pass criterion is **counts-based** — it passes when at least one test ran and none failed, regardless of the process exit code. Exit code `== 0` is used only as a fallback when the output can't be parsed into counts.

---

## Step 1 — Detect

Read `<packageDirectory>/package.json`. A usable test script exists when:

- A `scripts` entry runs the project's tests (most commonly named `test`, but some projects use `test:unit`, `tests`, `unit`, etc.), and
- Its value is **not** the npm-init placeholder `echo "Error: no test specified" && exit 1` (or any variant whose first effective command is `echo` + a non-zero exit).

If a usable script exists, record its **exact name** for Step 3 and skip to **Step 3 — Emit**.

Also record the **test runner** so Step 3 can choose the right flags: read the script's command and the project's `devDependencies`. `vitest` watches by default and needs `--run` for a single non-watch pass; `jest`, `mocha`, `jasmine`, `ava`, and `node --test` run once by default and need no watch flag. If the script already pins the runner into single-run mode (e.g. `"test": "vitest run"`), it usually needs no extra flags — but still watch for runner-specific cases (e.g. `react-scripts test` defaults to watch mode and needs `CI=true` / `--watchAll=false`; some `jest` CI setups want `--ci`).

If no usable script exists, continue with **Step 2 — Generate**.

## Step 2 — Generate (only when no test script exists)

Generate targeted regression tests so that breaking changes introduced by upgrades are caught automatically. These tests capture the **current runtime behavior** and must be green against the pre-upgrade code.

### 2a — Analyze what will change

Before writing any tests, understand the upgrade risk:

1. **Identify affected source files** — find `.ts`/`.tsx`/`.js` files (excluding `node_modules`) that import or reference the packages in the upgrade plan.
2. **For each affected file, read it** and identify:
   - Which APIs from the upgraded package are being used (function calls, components, hooks, classes, config).
   - How those APIs affect the application's behavior (rendering, data flow, routing, state, HTTP requests).
   - Which patterns are most likely to break (renamed exports, changed function signatures, removed defaults, altered return types).

### 2b — Design tests that capture runtime behavior

For each affected source file, design tests that would **fail if the upgraded package changes behavior**:

| What the code does | What to test |
|---|---|
| Renders a component using the package | Assert the component renders expected output/structure |
| Calls an API function with specific args | Assert the function returns expected values / has expected side effects |
| Uses hooks (React, Vue) | Assert the hook returns expected state, triggers expected updates |
| Configures routing | Assert routes map to correct components, params are extracted correctly |
| Makes HTTP requests via a client lib | Assert requests are formed correctly, responses are handled as expected |
| Uses a class or factory pattern | Assert instantiation works, methods return expected results |
| Relies on default exports or named exports | Assert the exports exist and have the expected type/shape |

**Focus on behavior, not implementation.** Test what the user would experience, not internal wiring. A good regression test answers: "If this package upgrade silently changes something, would this test catch it?"

### 2c — Write the tests

1. **Pick a test runner.** If the project already has Jest / Mocha / Jasmine in `devDependencies`, use it. Otherwise add `"vitest": "latest"` to `devDependencies` and call `typescript_install_dependencies`.
2. **Generate `.spec.ts` files** alongside each affected source file (or under `__tests__/`):
   - Use Vitest: `import { describe, it, expect, vi } from 'vitest';`
   - Import the actual module under test — don't rewrite its logic in the test.
   - Mock only what's necessary (network, filesystem, timers). **Do not mock the package being upgraded** — that's the whole point of the test.
   - Include a descriptive header comment: `// Regression tests for: <package>@<current-version> upgrade`.
   - Group tests by risk area: `describe('<package> - <feature area>', () => { ... })`.
3. **Add a `test` script** to `package.json`: `"test": "vitest run"` (or the equivalent for the chosen framework).
4. **Run the tests once** to confirm they are green against the current code. Fix any failures before continuing — the assertion will fail on baseline otherwise, and the comparison becomes meaningless.

### Examples

For a file that uses `react-router` v5:

```typescript
// Regression tests for: react-router@5.3.4 upgrade
import { describe, it, expect } from 'vitest';

describe('react-router - route rendering', () => {
  it('renders Dashboard at /dashboard', () => { /* ... */ });
  it('extracts :id param from /users/:id', () => { /* ... */ });
  it('redirects unauthenticated users to /login', () => { /* ... */ });
});
```

For a file that uses `axios`:

```typescript
// Regression tests for: axios@0.27.2 upgrade
import { describe, it, expect, vi } from 'vitest';

describe('axios - request interceptors', () => {
  it('attaches auth header to outgoing requests', () => { /* ... */ });
  it('handles 401 by redirecting to login', () => { /* ... */ });
  it('retries on network error up to 3 times', () => { /* ... */ });
});
```

## Step 3 — Emit

Append exactly one assertion to the plan's `assertions[]`:

```jsonc
{
  "name": "tests-pass",
  "kind": "process",
  "command": "npm",
  "args": ["test"],
  "verificationMethod": "test-results",
  "expected": "0",
  "timeoutSeconds": 300
}
```

- Substitute `npm` / `yarn` / `pnpm` / `bun` based on the project's lockfile.
- **Use the script name you recorded in Step 1.** If `package.json` defines `"test:unit"` (or any name other than `test`) for unit tests, use that instead:
  - npm / pnpm / bun: `"args": ["run", "test:unit"]`
  - yarn: `"args": ["test:unit"]`
- If the project's script already includes the runner flags (e.g., `"test": "vitest run"`), the args above are enough. Only forward extra flags when the script would otherwise watch: for **Vitest** append `--run` after `--` (`"args": ["test", "--", "--run"]`). **Jest**, **Mocha**, **Jasmine**, **ava**, and **`node --test`** run once by default and need no watch flag — match the runner you recorded in Step 1 and don't pass `--run` to a non-Vitest runner (it errors).
- Keep the assertion `name` exactly `tests-pass` — the comparison report and dashboards key on it.
- Use the **same** test command for baseline and post-upgrade — the parser keys off the runner banner, and switching mid-workflow invalidates the count comparison.
