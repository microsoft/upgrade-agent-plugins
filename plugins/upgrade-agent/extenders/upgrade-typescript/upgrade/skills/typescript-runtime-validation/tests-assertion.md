# `tests-pass` assertion — detect, generate, emit

Every eval plan should run the project's unit tests as part of validation. This file covers two cases:

1. **The project already has a usable test script** → emit one assertion that runs it.
2. **The project has no test script** → generate focused Vitest tests for the current validation context, add a `test` script, then emit the assertion.

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

Generate focused tests that capture the **current runtime behavior**. In an upgrade workflow they establish regression coverage before versions change; in a standalone workflow they exercise representative project behavior.

### 2a — Select the behavior to cover

Before writing tests, use the calling workflow's context:

- **Upgrade workflow:** identify `.ts`/`.tsx`/`.js` files (excluding `node_modules`) that import or reference packages in the upgrade plan. Read each affected file and identify the package APIs in use, how they affect behavior, and which breaking-change patterns are most relevant.
- **Standalone workflow:** identify the project's primary public or executable behavior from its README, exports, routes, CLI commands, and source entry points. Select a small representative set whose failure would make the project meaningfully unhealthy.

For each selected file, understand how it affects rendering, data flow, routing, state, HTTP requests, command output, or public API behavior.

### 2b — Design tests that capture runtime behavior

For each selected source file, design tests that would fail if the behavior being validated stopped working:

| What the code does | What to test |
|---|---|
| Renders a component using the package | Assert the component renders expected output/structure |
| Calls an API function with specific args | Assert the function returns expected values / has expected side effects |
| Uses hooks (React, Vue) | Assert the hook returns expected state, triggers expected updates |
| Configures routing | Assert routes map to correct components, params are extracted correctly |
| Makes HTTP requests via a client lib | Assert requests are formed correctly, responses are handled as expected |
| Uses a class or factory pattern | Assert instantiation works, methods return expected results |
| Relies on default exports or named exports | Assert the exports exist and have the expected type/shape |

**Focus on behavior, not implementation.** Test what the user would experience, not internal wiring. In an upgrade workflow ask, "If this package upgrade silently changes something, would this test catch it?" In standalone mode ask, "Would this fail if the project stopped performing this behavior?"

### 2c — Write the tests

1. **Pick a test runner.** If the project already has Jest / Mocha / Jasmine in `devDependencies`, use it. Otherwise add `"vitest": "latest"` to `devDependencies` and call `typescript_install_dependencies`.
2. **Generate `.spec.ts` files** alongside each selected source file (or under `__tests__/`):
   - Use Vitest: `import { describe, it, expect, vi } from 'vitest';`
   - Import the actual module under test — don't rewrite its logic in the test.
   - Mock only what's necessary (network, filesystem, timers). In an upgrade workflow, **do not mock the package being upgraded** — that's the whole point of the test.
   - Include a descriptive header comment:
     - Upgrade: `// Regression tests for: <package>@<current-version> upgrade`.
     - Standalone: `// Runtime validation coverage for: <behavior>`.
   - Group tests by risk area or validated behavior.
3. **Add a `test` script** to `package.json`: `"test": "vitest run"` (or the equivalent for the chosen framework).
4. **Run the tests once** to confirm they are green against the current code. Fix test defects before continuing. If the test exposes a genuine application failure, return that failure to the calling workflow rather than weakening the test.

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
