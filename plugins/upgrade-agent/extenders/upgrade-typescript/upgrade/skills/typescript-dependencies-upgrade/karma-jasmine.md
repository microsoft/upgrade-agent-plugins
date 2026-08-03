# Karma / Jasmine Test-Stack Upgrades

This group upgrades together: the `karma` runner and its `karma-*` plugins (`karma-jasmine`,
`karma-chrome-launcher`, `karma-coverage`, `karma-jasmine-html-reporter`, …), the `jasmine-core`
framework (plus `jasmine` for Node specs and `jasmine-*` reporters), and the `@types/jasmine` types
(plus legacy `@types/jasminewd2`). `ng update` does not touch them, so upgrade them as their own group.

## Coupling rules

- `@types/jasmine`'s major must equal `jasmine-core`'s major.
- `karma-jasmine@5` requires `karma@^6`; keep `karma` and `karma-jasmine` on the same generation.
- `karma-jasmine` breaks on `jasmine-core@7` — never take the stack above jasmine 6 while Karma is
  present.
- **Angular projects: `jasmine-core@6` requires `zone.js@^0.16.0`.** Jasmine 6 removed the public
  `QueueRunner`, which Angular's `zone-testing` only guards for from `zone.js` 0.16.0 (Angular 21+).
  On `zone.js < 0.16` (Angular ≤ 20) `ng test` crashes at load, so cap the stack at `jasmine-core@5`
  (and `@types/jasmine@5`). Take jasmine-core to 6 only once `zone.js ≥ 0.16`.
- In an Angular project, `@angular-devkit/build-angular` requires `karma@^6.3.0`. Upgrade Angular
  first ([angular.md](./angular.md)), then reconcile this group.

## Upgrade steps

1. **Angular first (if present).** Finish the Angular upgrade before touching the test stack.
2. **Pick the `jasmine-core` cap.** Latest **6.x** normally; **5.x** on an Angular project whose
   `zone.js` is `< 0.16.0`. Never 7.x while Karma is present.
3. **Bump the whole group** via `typescript_upgrade_package_dependency_group`: `karma`, every
   `karma-*` plugin, `jasmine-core` (to the cap from step 2), `jasmine` if used, and `@types/jasmine`
   (matched to `jasmine-core`'s major). Override any target above the cap.
4. **Only if `jasmine-core` lands on 6.x, add an `overrides` block** to `package.json` so the Karma
   plugins resolve jasmine-core 6 instead of their bundled 4.x (yarn: use `resolutions`):

   ```json
   "overrides": {
     "karma-jasmine": { "jasmine-core": "^6.0.0" },
     "karma-jasmine-html-reporter": { "jasmine-core": "^6.0.0" }
   }
   ```

5. **Reinstall** with `typescript_install_dependencies`. An `ERESOLVE`/peer error means a member
   trails — align the `karma`/`karma-jasmine` majors and set `@types/jasmine` to `jasmine-core`'s
   major, then reinstall.
6. **Fix the source/config errors** using the table below.
7. **Compile, then run the tests** (see Validation).

## Errors and fixes

Search specs and the Karma/Jasmine config for these. Most surface at test time, not at compile time.

| Symptom / pattern | Fix |
| --- | --- |
| config `failFast` | Renamed (Jasmine 4) → `stopOnSpecFailure`. |
| config `oneFailurePerSpec` | Renamed (Jasmine 4) → `stopSpecOnExpectationFailure`. |
| config `randomTests` / `randomizeTests` / `Promise` | Removed (Jasmine 4) — use `Env#configure({ random: … })`; drop `Promise`. |
| custom matcher using global `matchersUtil` / `jasmine.pp` | Use the `matchersUtil`/`pp` passed into the matcher factory (globals removed in Jasmine 4). |
| `.toContain(` relying on `===` identity; `done(nonError)` or a second `done()` | Jasmine 4: `toContain` uses deep equality; a non-`Error` `done` argument or a repeated `done()` is a failure. |
| `getEnv().execute(callback)`; `node_boot.js` | Jasmine 5: `Env#execute` is async (no callback); use the exported `boot`. |
| backslashes in `spec_files` / `helpers` globs | Jasmine 5 treats `\` as an escape — use `/`. |
| duplicate `describe`/`it` names within one suite | Jasmine 6 defaults `forbidDuplicateNames: true` — rename them, or set it back to `false`. |
| custom reporter reading `result.expected` / `result.actual`; custom `specFilter` reading internal spec fields | Jasmine 6 removed `expected`/`actual` and passes spec **metadata** to filters — update them. |
| spying on `setTimeout` / `setInterval` with the mock clock installed | Jasmine 6 throws — stop spying on timing functions, or don't install the mock clock in that spec. |
| `ng test` crashes at load with `TypeError: Cannot read properties of undefined (reading 'prototype')` in `zone-testing.js` | jasmine-core 6 on `zone.js < 0.16`. Cap the stack at jasmine-core 5 (see Coupling rules), or upgrade Angular to bring `zone.js ≥ 0.16`. |

## Blockers

- **Node floor.** Jasmine 5 requires Node ≥ 18; Jasmine 6 requires Node ≥ 20. If CI/dev is on an
  older Node, the packages install but tests won't run — report the Node upgrade as a prerequisite.
- **Runner migration is out of scope.** Karma is deprecated (security fixes only). Bumping to
  Karma 6.x + Jasmine keeps an existing suite building; replacing Karma with Vitest / Web Test
  Runner / Jest is a separate migration that rewrites `angular.json` and removes `karma.conf.js`.
  Do not attempt it here — report it as a follow-up.

## Validation

- Run `typescript_compile_package`. The compiler will not catch most Jasmine breaks (config
  renames, deep-equality `toContain`, `forbidDuplicateNames`, async `Env#execute`); those fail at
  test time.
- If `validateRuntime` is true, call `typescript_validate_runtime` (REQUIRED) — a green compile with
  a red `ng test` is the expected failure mode here. Follow [SKILL.md](./SKILL.md) and
  [runtime-validation.md](./runtime-validation.md).

## Telemetry

After the attempt (success or failure), call `typescript_report_telemetry` once:
`eventType: "group_upgrade"`, `group: "karma-jasmine"`, `sessionId` (from the scan), `success`,
`fromVersion`/`toVersion` = starting/target `jasmine-core` major (e.g. `"3"` → `"6"`),
`strategy: "single-shot"`, `codemodsRun: 0` (Jasmine ships no official codemod), and `failureReason`
if failed (e.g. `peer_dep_unresolved`, `jasmine7_incompatible_with_karma`,
`jasmine6_requires_zonejs_016`, `node_floor_unmet`, `tests_failing_runtime`,
`compile_errors_remaining`). This is not the terminal event — the workflow finishes with
`typescript_write_upgrade_summary`.
