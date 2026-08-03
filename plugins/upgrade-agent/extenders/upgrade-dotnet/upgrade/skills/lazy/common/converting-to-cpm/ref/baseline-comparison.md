# Baseline Comparison

Verify the CPM conversion is version-neutral by comparing resolved package versions before and after conversion using `dotnet package list`. Binlogs are also captured as artifacts for manual inspection or troubleshooting.

## Capturing package lists

Use `dotnet package list` to snapshot resolved versions. Always build from a clean state first to ensure accurate resolution.

### Baseline (before conversion, step 2)

```bash
dotnet clean
dotnet build -bl:baseline.binlog
dotnet package list --format json > baseline-packages.json
```

### Post-conversion (after all changes, step 8)

```bash
dotnet clean
dotnet build -bl:after-cpm.binlog
dotnet package list --format json > after-cpm-packages.json
```

If `--format json` is not available (requires .NET 8 SDK+), use the default tabular output:

```bash
dotnet package list > baseline-packages.txt
```

For solution-scoped conversions, pass the solution file to all commands.

## Producing the comparison

Compare `baseline-packages.json` and `after-cpm-packages.json` per project. For each project, identify:

1. **Version changes**: Packages whose resolved version differs.
2. **Added packages**: Packages present after conversion but not in the baseline.
3. **Removed packages**: Packages present in the baseline but not after conversion.
4. **VersionOverride entries**: Packages that use `VersionOverride` (their version matches baseline but the mechanism changed).
5. **Transitive changes**: If `CentralPackageTransitivePinningEnabled` was set, note any transitive packages that are now pinned.

Present changes and unchanged packages in separate tables: a **Changes** table for version diffs, `VersionOverride` entries, and added/removed packages (with a status column), and an **Unchanged** table confirming identical resolution to baseline. If there are no changes, state the conversion is fully version-neutral.

## When comparison reveals unexpected differences

If the post-conversion package list resolves different versions than expected (beyond intentional changes like version conflict alignment or `VersionOverride`), investigate:

- Missing `<PackageVersion>` entries causing fallback behavior
- Conditional `<PackageVersion>` entries not matching the project's target framework
- Import order issues where a property referenced in `Directory.Packages.props` is not yet defined
- Transitive dependency resolution differences from version alignment
- Packages unexpectedly added or removed due to conditional ItemGroup changes

Flag any unexpected differences to the user before considering the conversion complete.

If investigation is blocked or the user asks how to manually diagnose build/restore issues, point them to the binlog artifacts captured during steps 2 and 8 (`baseline.binlog`, `after-cpm.binlog`). These are MSBuild binary logs containing the full structured build event stream — property evaluations, package resolutions, and target execution. They can be opened in the [MSBuild Structured Log Viewer](https://msbuildlog.com/):

```bash
winget install KirillOsenkov.MSBuildStructuredLogViewer
```
