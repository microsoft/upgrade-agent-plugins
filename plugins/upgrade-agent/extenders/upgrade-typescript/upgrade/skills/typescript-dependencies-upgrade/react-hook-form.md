# React Hook Form Upgrades

Upgrade `react-hook-form` and the official `@hookform/*` packages present in the manifest as one
compatibility group, after any in-scope React upgrade. Resolve each package to its own latest
compatible version; their version numbers do not move in lockstep.

`@hookform/resolvers` v5 requires `react-hook-form` 7.55.0 or newer. It also relies on peer
validation libraries such as Zod, Yup, Joi, Ajv, or Valibot. Check the target resolver package's
published peer ranges and include an incompatible validation-library peer in the group rather than
forcing the install.

## Strategy

Upgrade directly to the target versions in one dependency-group pass. When crossing React Hook
Form v7, apply the official v7 codemods and then handle the remaining Controller, field-array, and
type changes manually. Do not replace type errors with `as any`: resolver errors usually mean the
schema's input type and validated output type have been incorrectly treated as the same type.

## Pre-upgrade audit

Search the package directory before changing versions and record every match:

| Pattern to find | Required handling |
| --- | --- |
| `ref={register` or `ref={register(` | Run the official `v7/update-register` codemod. |
| Destructured `errors` from `useForm()` | Run `v7/move-errors-to-formState`; v7 moved errors under `formState`. |
| `render={({ onChange` / `render={({ value` on `Controller` | Destructure those props from `field` in v7. |
| Object destructuring from `watch([` | v7 returns an array for an array of field names; change the receiving destructure to an array. |
| `setError(` with `shouldFocus` in the error object | Move `shouldFocus` to the third options argument. |
| `append(` / `prepend(` / `insert(` with a boolean focus argument | Replace the boolean with the v7 focus-options object. |
| `NestedValue` / `UnpackNestedValue` | Remove the deprecated wrapper and use the field value type directly. |
| `useForm<...>` next to a resolver schema with transforms/defaults/coercion | Verify schema input and output separately; do not assume one generic describes both. |
| `schemaOptions.context` passed to `yupResolver` | Pass mutable resolver context through `useForm({ context })`. |

## Order of operations

1. **Finish React first.** If React guidance is also in scope, complete it before this group.
2. **Check runtime and peer floors.** Confirm the target packages support the project's Node and
   React versions. For `@hookform/resolvers` v5+, require `react-hook-form >= 7.55.0` and satisfy the
   selected resolver's validation-library peer range.
3. **Upgrade the whole group.** Pass `react-hook-form`, all present `@hookform/*` packages, and any
   required validation-library peer to `typescript_upgrade_package_dependency_group`.
4. **Install before editing source.** Call `typescript_install_dependencies`. Resolve peer conflicts
   by selecting compatible published versions, not with `--force` or `--legacy-peer-deps`.
5. **Run the official v7 codemods when crossing v7.** From the package directory, use the project's
   package runner:

   ```text
   npx --yes @hookform/codemod v7/update-register . --dry
   npx --yes @hookform/codemod v7/update-register .
   npx --yes @hookform/codemod v7/move-errors-to-formState . --dry
   npx --yes @hookform/codemod v7/move-errors-to-formState .
   ```

   Use `yarn dlx` or `pnpm dlx` instead of `npx --yes` when appropriate. Inspect the dry-run output
   before applying it. These codemods are permitted source transforms; they do not replace the
   dependency installer.
6. **Apply the remaining v7 migrations.** Follow the pre-upgrade audit and official migration guide
   for Controller's `field` object, `watch` arrays, `setError`, field-array focus options,
   `shouldUnregister`, and renamed types. The regex KB may repair simple Controller/error
   destructuring only in files with new errors; do not depend on it for the full migration.
7. **Fix resolver input/output typing.** Resolver v5 can infer a schema's validated output. Prefer
   omitting explicit form generics when inference is correct. When input and output intentionally
   differ, specify all three parameters:

   ```ts
   useForm<SchemaInput, FormContext, SchemaOutput>({
     resolver: schemaResolver(schema),
   });
   ```

   For Zod, use `z.input<typeof schema>` and `z.output<typeof schema>` where transforms, coercion,
   or defaults make those types differ.
8. **Compile, test, and validate behavior.** Run `typescript_compile_package`, the project's form
   tests, and runtime validation. Exercise submission, validation errors, transformed/defaulted
   values, controlled fields, and field-array add/remove flows.

## Blockers

- If the target resolver has no published version compatible with the project's validation
  library, leave the resolver and React Hook Form unchanged and report the peer conflict.
- If the project cannot meet the target package's Node or React floor, do not force the install or
  silently upgrade those runtimes outside the user's requested scope.
- If schema input/output intent cannot be determined from the code and tests, stop and report the
  ambiguous forms instead of adding casts that erase the mismatch.

## Telemetry

After the group attempt, call `typescript_report_telemetry` once with:

- `eventType`: `"group_upgrade"`
- `group`: `"react-hook-form"`
- `sessionId`: from the scan response
- `success`: whether install, compile, and validation passed
- `fromVersion`: starting React Hook Form major
- `toVersion`: target React Hook Form major
- `strategy`: `"single-shot"`
- `codemodsRun`: number of official codemod transforms applied
- `failureReason`: when unsuccessful, for example `"peer_dep_unresolved"`,
  `"resolver_input_output_mismatch"`, or `"compile_errors_remaining"`

Return to the calling workflow so it can write the terminal upgrade summary.
