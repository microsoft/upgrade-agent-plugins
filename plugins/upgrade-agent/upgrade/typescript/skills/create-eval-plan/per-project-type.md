# Per-project-type templates and guidance

Each section gives confirmation signals, what to validate, and a starter template. Templates use `npm`/`npx` — substitute `pnpm`/`yarn`/`bun` if the project's lockfile indicates it.

Every template starts with the same `setup[]`:

```jsonc
"setup": [ { "command": "npm", "args": ["install"] } ]
```

Replace `npm install` with `pnpm install --frozen-lockfile`, `yarn install --frozen-lockfile`, or `bun install` if appropriate. For workspaces, you may need `--filter <package>` or to run install at the workspace root.

---

## webapp

**Confirmation signals:** depends on `react-dom` / `vue` / `svelte` / `solid-js` / `@angular/platform-browser` / `next`, or `scripts` has `dev` / `start` / `serve` that boots a dev server (Vite / webpack-dev-server / Next / Angular CLI).

**What to validate:** the dev server starts, the home route renders, and one or more user flows still work end-to-end. Pure HTML scraping is weak — meaningful flows need Playwright recordings.

**Prerequisite:** Record at least one Playwright `.spec.ts` before authoring the plan. Read [recording.md](./recording.md) end-to-end — confirm the recording opt-in with the user first (Step 0); they may prefer faster `http-probe` coverage.

**Starter template:**

```jsonc
{
  "projectType": "webapp",
  "devServer": {
    "command": "npm",
    "args": ["run", "dev"],
    "url": "http://localhost:5173/"
  },
  "setup": [ { "command": "npm", "args": ["install"] } ],
  "assertions": [
    {
      "name": "tsc-no-emit",
      "kind": "process",
      "command": "npx",
      "args": ["tsc", "--noEmit"],
      "verificationMethod": "exit-code",
      "expected": "0",
      "timeoutSeconds": 180
    },
    {
      "name": "dev-server-serves-home",
      "kind": "http-probe",
      "startCommand": "npm",
      "startArgs": ["run", "dev"],
      "url": "http://localhost:5173/",
      "verificationMethod": "http-status",
      "expected": "200",
      "timeoutSeconds": 120
    },
    {
      "name": "login-flow",
      "kind": "playwright-route",
      "scriptPath": ".tsupgrader/runtime-validation/playwright-scripts/login.spec.ts",
      "verificationMethod": "exit-code",
      "expected": "0",
      "timeoutSeconds": 120
    }
  ]
}
```

**Adapt:** swap the `url` port to match what the project's dev server actually binds (Vite 5173, Next 3000, Angular 4200, CRA 3000, Webpack default 8080). The top-level `devServer` block is what `playwright-route` assertions rely on — the runner starts it once, waits for `url` to respond, and kills it (process tree) after all assertions complete, even on failure.

---

## server

**Confirmation signals:** depends on `express`, `fastify`, `koa`, `hapi`, `@nestjs/core`, `apollo-server`, `graphql-yoga`, etc., or has source that calls `.listen(<port>)`. No browser-side framework.

**What to validate:** the server boots, each meaningful HTTP route responds with the expected status (and optionally a stable body substring). Don't try to validate business logic — that's what tests are for. Runtime validation here is "do the endpoints still answer".

### Endpoint discovery (do not skip)

Don't make up routes. Don't ask the LLM to "imagine what endpoints this server probably has". Scan the source:

1. **Find the entrypoint.** Read `package.json`'s `main`, `module`, or `scripts.start` to find the file that boots the server.
2. **Grep for route declarations** in the project (not in `node_modules`):
   - Express / Connect: `app.get(`, `app.post(`, `app.put(`, `app.delete(`, `app.patch(`, `router.<verb>(`.
   - Fastify: `fastify.get(`, `fastify.route(`, `.register(` with route-plugin shapes.
   - Koa: `router.<verb>(`.
   - Hapi: `server.route(`.
   - NestJS: `@Get(`, `@Post(`, `@Put(`, `@Delete(`, `@Patch(`, `@All(` decorators; also `@Controller('<base>')` to find the prefix.
   - Apollo / GraphQL Yoga: there's typically one HTTP endpoint (`/graphql`); the routes live in the GraphQL schema, not HTTP. Probe `/graphql` with `http-status` and consider one `output-contains` against the introspection response.
3. **Pick a small representative subset.** Don't add an assertion for every route — pick:
   - The health / readiness route (`/health`, `/healthz`, `/_status`, `/ping`) if one exists.
   - The primary read endpoint (e.g., a `GET /api/<resource>` that lists things).
   - One write endpoint if the project has dummy / fixture data that makes it safely re-runnable.
4. **Ask the user to confirm the subset.** Discovery may find dozens; the user knows which 3–5 actually matter.

### Starter template

```jsonc
{
  "projectType": "server",
  "setup": [ { "command": "npm", "args": ["install"] } ],
  "assertions": [
    {
      "name": "tsc-no-emit",
      "kind": "process",
      "command": "npx",
      "args": ["tsc", "--noEmit"],
      "verificationMethod": "exit-code",
      "expected": "0",
      "timeoutSeconds": 180
    },
    {
      "name": "server-boots-healthz-200",
      "kind": "http-probe",
      "startCommand": "npm",
      "startArgs": ["run", "start"],
      "url": "http://localhost:3000/healthz",
      "verificationMethod": "http-status",
      "expected": "200",
      "timeoutSeconds": 60
    },
    {
      "name": "list-widgets-route",
      "kind": "http-probe",
      "startCommand": "npm",
      "startArgs": ["run", "start"],
      "url": "http://localhost:3000/api/widgets",
      "verificationMethod": "http-status",
      "expected": "200",
      "timeoutSeconds": 60
    }
  ]
}
```

**Adapt:**
- If `npm run start` doesn't exist, use the actual boot command. Common alternatives: `node dist/index.js`, `ts-node src/index.ts`, `tsx src/index.ts`, `npm run dev`.
- If the server reads its port from an env var, set it via a setup-time `.env` if needed, or hardcode via `startArgs` (e.g., `["run", "start", "--", "--port", "3000"]`).
- For NestJS projects, prefer `npm run start:prod` (compiled, fast boot) over `npm run start:dev` (watch mode never exits the way the probe expects).

---

## cli

**Confirmation signals:** `package.json` has a `bin` field, or `scripts` references a CLI entry such as `bin/<name>.js`. The package is invoked via a terminal command, not imported.

**What to validate:** the CLI starts up, prints its help/version, and one or two real subcommands still work against fixture data shipped in the repo. Avoid commands that touch the network or require user-specific state.

### Starter template

```jsonc
{
  "projectType": "cli",
  "setup": [ { "command": "npm", "args": ["install"] } ],
  "assertions": [
    {
      "name": "tsc-no-emit",
      "kind": "process",
      "command": "npx",
      "args": ["tsc", "--noEmit"],
      "verificationMethod": "exit-code",
      "expected": "0",
      "timeoutSeconds": 180
    },
    {
      "name": "cli-help-exits-zero",
      "kind": "process",
      "command": "node",
      "args": ["./bin/mycli.js", "--help"],
      "verificationMethod": "exit-code",
      "expected": "0"
    },
    {
      "name": "cli-help-banner",
      "kind": "process",
      "command": "node",
      "args": ["./bin/mycli.js", "--help"],
      "verificationMethod": "output-contains",
      "expected": "mycli - manage your widgets"
    },
    {
      "name": "cli-subcommand-against-fixture",
      "kind": "process",
      "command": "node",
      "args": ["./bin/mycli.js", "list", "--config", "test/fixtures/sample.json"],
      "verificationMethod": "exit-code",
      "expected": "0",
      "timeoutSeconds": 30
    }
  ]
}
```

**Adapt:** look at the project's actual `bin` entry path. If the project uses a shebang and is installed locally, invoke `npx <name>` instead of `node ./bin/<name>.js`. Choose `output-contains` strings carefully — see [output-contains.md](./output-contains.md).

---

## electron

**Confirmation signals:** `electron` in `dependencies` / `devDependencies`. Has a `main` field pointing to the electron entry script. Often has a renderer-process source tree (`src/renderer/`) and a main-process source tree (`src/main/`).

**What to validate:** the app can package and boot in headless mode. Driving the actual window is out of scope here — we just verify the main process starts, the renderer loads, and exits cleanly when sent a quit signal. Use `--no-sandbox` to allow headless boot in CI / WSL where the OS sandbox isn't usable.

### Starter template

```jsonc
{
  "projectType": "electron",
  "setup": [ { "command": "npm", "args": ["install"] } ],
  "assertions": [
    {
      "name": "tsc-no-emit",
      "kind": "process",
      "command": "npx",
      "args": ["tsc", "--noEmit"],
      "verificationMethod": "exit-code",
      "expected": "0",
      "timeoutSeconds": 180
    },
    {
      "name": "electron-builds",
      "kind": "process",
      "command": "npm",
      "args": ["run", "build"],
      "verificationMethod": "exit-code",
      "expected": "0",
      "timeoutSeconds": 300
    },
    {
      "name": "electron-smoke-headless-exits-zero",
      "kind": "process",
      "command": "npx",
      "args": ["electron", ".", "--no-sandbox", "--smoke-test"],
      "verificationMethod": "exit-code",
      "expected": "0",
      "timeoutSeconds": 60
    }
  ]
}
```

**Adapt:**
- `--smoke-test` is an Electron flag that boots the app, fires `ready`, and exits — perfect for runtime validation. If the project's main process intercepts CLI flags and doesn't pass through to Electron's argv, you may need to add a small `--smoke-test` handler in the main process (one-line: `if (process.argv.includes('--smoke-test')) app.quit();`). Discuss with the user before adding code to their main process.
- `--no-sandbox` is required on Linux CI runners and inside WSL where the user-namespace sandbox is unavailable. On Windows / macOS native it's harmless. We always include it so the plan is portable.
- If the project doesn't have a build step (uses raw `.js` files), drop the `electron-builds` assertion.

---

## library

**Confirmation signals:** no `bin`, no dev-server script, no `.listen(`. Source exports symbols for consumption via `import`. Has a `main` / `module` / `exports` field but no executable entry.

**What to validate:** the library still compiles (`tsc --noEmit`), its tests still pass, and its build emits the public entry files at the expected paths.

### Starter template

```jsonc
{
  "projectType": "library",
  "setup": [ { "command": "npm", "args": ["install"] } ],
  "assertions": [
    {
      "name": "tsc-no-emit",
      "kind": "process",
      "command": "npx",
      "args": ["tsc", "--noEmit"],
      "verificationMethod": "exit-code",
      "expected": "0",
      "timeoutSeconds": 180
    },
    {
      "name": "tests-pass",
      "kind": "process",
      "command": "npm",
      "args": ["test"],
      "verificationMethod": "test-results",
      "expected": "0",
      "timeoutSeconds": 300
    },
    {
      "name": "build-emits-main",
      "kind": "process",
      "command": "node",
      "args": ["-e", "require('fs').accessSync(require('./package.json').main); console.log('BUILD_OK')"],
      "verificationMethod": "output-contains",
      "expected": "BUILD_OK"
    }
  ]
}
```

**Adapt:**
- **Detect the test runner from `package.json` first** (`scripts.test` command + `devDependencies`), then set the args to match: **Jest / Mocha / Jasmine / ava / `node --test`** run once by default → `["test"]` (shown above). **Vitest** watches by default → forward `--run` (`["test", "--", "--run"]`). Don't pass `--run` to a non-Vitest runner — it errors. When unsure, the bare `["test"]` is the safe default.
- The `build-emits-main` assertion is a sentinel example from [output-contains.md](./output-contains.md): it succeeds with the literal `BUILD_OK` only if the `main` file exists. If you'd rather just exit-code, replace with `node -e "require('fs').accessSync(require('./package.json').main)"` and `verificationMethod: "exit-code"`.
- If the project doesn't have a build step (publishes raw `.ts`), drop `build-emits-main` entirely.

---

## framework / plugin

For VS Code extensions, Babel / Webpack / Rollup plugins, Nx / Lerna / Turbo workflows, etc., use the `library` template as a starting point and add type-specific assertions:

- **VS Code extension**: add a `process` assertion that runs `vsce package --no-dependencies --out /tmp/test.vsix` (verify the package builds) plus `exit-code: 0`.
- **Babel plugin**: add a `process` assertion that runs `npx babel test/fixtures/input.js --plugins=./` and verify the output `exit-code: 0` (the plugin loaded without throwing).
- **Webpack / Rollup plugin**: add a `process` assertion that runs the bundler against a tiny fixture entry.

For all of these, `projectType: "plugin"` (single-host plugins) or `"framework"` (multi-package build systems) is the closest match.

---

## other

Use as a last resort. The plan still works — it just doesn't get type-specific dashboard treatment. Add whatever assertions make sense; the schema rules in [plan-schema.md](./plan-schema.md) apply unchanged.
