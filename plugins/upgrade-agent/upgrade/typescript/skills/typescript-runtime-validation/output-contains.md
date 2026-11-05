# Choosing `output-contains` substrings

`output-contains` is the most failure-prone verification method in an eval plan because it depends on tool output staying stable across the upgrade.

## How the match works

The runner concatenates the assertion's combined stdout + stderr (for `process` kind) or the HTTP response body (for `http-probe` kind), then runs:

```csharp
output.Contains(assertion.Expected, StringComparison.Ordinal)
```

Exact substring, case-sensitive, no globs, no regex. A single trailing space difference is enough to fail.

## When to use `output-contains`

Prefer this only when the assertion exists to confirm a specific user-visible string, e.g.:

- A CLI prints its version after `--version`, and you want to confirm the binary starts up at all.
- A server's health endpoint returns a literal `"ok"`.
- A startup banner contains a copyright line or product name that the project itself controls.

For everything else — "did the command succeed" — use `exit-code`.

## When NOT to use `output-contains`

- **Version numbers.** Versions change on every upgrade. `expected: "1.4.2"` regresses when the package bumps to `1.4.3`.
- **Error messages.** Tool authors rewrite error text constantly.
- **Stack traces or log timestamps.** Both are noise.
- **JSON.** Key order and whitespace are not guaranteed. Use a `process` assertion with `exit-code` instead.
- **Colored / ANSI-escaped output.** ANSI codes drift across terminal-emulator detection.

## Good substring choices

A good `expected` string is:

1. **Owned by the project being validated**, not by an upgraded dependency.
2. **Short and uniquely identifying.**
3. **Free of dynamic data** — no version, timestamp, count, path, hostname, port, username.
4. **Visible to the user in normal operation.**

### Examples

| Good | Bad |
|---|---|
| `"mycli - manage your widgets"` (CLI banner you own) | `"webpack 5.94.0"` (version drifts) |
| `"ok"` (server-owned health literal) | `"/home/runner/work/repo"` (path varies) |
| `"Applying migration"` (project source owns it) | `"compiled 47 modules in 1.2s"` (count drifts) |
| | `"DeprecationWarning: Buffer() is deprecated"` (dependency owns it) |
| | `"\u001b[32m✓\u001b[0m PASS"` (ANSI codes) |

## Sentinel pattern: wrap the real check in your own literal

If the underlying tool's output is too volatile but the *outcome* is binary, wrap the command in a helper that prints your own sentinel on success:

```jsonc
{
  "name": "schema-validates",
  "kind": "process",
  "command": "node",
  "args": ["-e", "require('./scripts/validate-schema.js').then(() => console.log('SCHEMA_OK'), () => process.exit(1))"],
  "verificationMethod": "output-contains",
  "expected": "SCHEMA_OK"
}
```

If your wrapper exits 0 on success and nonzero on failure anyway, just drop `output-contains` and use `exit-code: "0"`.

## Diagnosing match drift

If a substring you've chosen doesn't appear in the command's actual output, run the command manually first, copy a substring from its real output, and use that. Don't guess at the wording.
