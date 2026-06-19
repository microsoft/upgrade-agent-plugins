---
name: migrating-to-microsoft-data-sqlclient
description: >
  Migrates .NET projects from System.Data.SqlClient to Microsoft.Data.SqlClient, handling package
  references, namespace updates, connection string encryption changes, and behavioral differences.
  Use when upgrading SqlClient, replacing System.Data.SqlClient, migrating to
  Microsoft.Data.SqlClient, or modernizing SQL Server data access in C# or VB.NET projects
  (.csproj, .vbproj, .cs, .vb files).
metadata:
  discovery: lazy
  traits: .NET|CSharp|VisualBasic|DotNetCore
---

# System.Data.SqlClient to Microsoft.Data.SqlClient Migration

## Overview

Migrate .NET projects from `System.Data.SqlClient` to `Microsoft.Data.SqlClient`, covering package references, code files, connection string validation, and configuration changes. The migration includes documenting behavioral differences that require runtime verification.

## Scope Determination

- Single project specified → migrate that project only
- Solution specified → migrate all projects referencing `System.Data.SqlClient`
- Scope unclear → ask the user

NuGet package names and assembly names are case-insensitive. Account for this when searching for or removing dependencies to avoid missed references.

## Workflow

Complete all steps without pausing between them. Each step builds on the previous one, and partial migration leaves the codebase in a broken state.

```
Migration Progress:
- [ ] Step 1: Update package dependencies
- [ ] Step 2: Update code files
- [ ] Step 3: Validate migration (repeat Steps 2-3 until clean)
- [ ] Step 4: Build verification
- [ ] Step 5: Connection string validation
```

### Step 1: Update Package Dependencies

For each project with an **explicit** dependency on `System.Data.SqlClient` in the project file or imported MSBuild targets (skip projects receiving it transitively — adding a new direct reference would create unnecessary coupling):

- Remove the `System.Data.SqlClient` package reference and assembly reference
- Add `Microsoft.Data.SqlClient` with a version supporting the project's target framework. Use available tools to determine the best version; fall back to manual determination only if no tool is available
- **Central Package Management (CPM):** Also remove `System.Data.SqlClient` from `Directory.Packages.props`. Add `Microsoft.Data.SqlClient` as a `PackageVersion` element in `Directory.Packages.props` and a version-less `PackageReference` in the project file

### Step 2: Update Code Files

Search the affected projects **and** projects that depend on them (transitive consumers may reference `System.Data.SqlClient` types). Use search tools and pass root folders for all relevant projects.

- Replace `System.Data.SqlClient` usages with `Microsoft.Data.SqlClient` equivalents. Preserve all business logic — never insert placeholders
- Check for using statements, types, and API from the `System.Data.SqlClient` namespace (skip comments and string literal constants)
- For using statements: if other `System.Data.SqlClient` API usage remains in the file, replace the using; if no other usage exists, remove the using instead of replacing it. Do not add `Microsoft.Data.SqlClient` usings to files that had no `System.Data.SqlClient` usings
- Track any code that cannot be converted or has potential runtime behavior changes — flag these for the user

### Step 3: Validate Migration

Search for `System.Data.SqlClient` across all affected projects and their dependents. If any references remain, return to Step 2. Repeat until no `System.Data.SqlClient` references exist.

### Step 4: Build Verification

Build all modified projects. Fix all build errors before proceeding — a partial fix leaves the codebase unusable.

### Step 5: Connection String Validation

Search for connection strings in `app.config`, `web.config`, and `appsettings.json` across affected projects and dependents. For connection strings pointing to databases:

- If `Encrypt` or `TrustServerCertificate` are **not** explicitly set, flag for the user — defaults changed (see Key Behavioral Differences below)
- If `Encrypt` is a bool value and the target is `Microsoft.Data.SqlClient v5.0+`, convert it to the corresponding `SqlConnectionEncryptOption` enum value and flag for user validation

## Key Behavioral Differences

These differences cause silent runtime behavior changes. Flag them in the migration report.

### Encrypt Property Changes
- **System.Data.SqlClient**: `Encrypt` defaults to `false`
- **Microsoft.Data.SqlClient v4.0+**: `Encrypt` defaults to `true`
- **Microsoft.Data.SqlClient v5.0+**: `Encrypt` is a `SqlConnectionEncryptOption` enum (`Optional`, `Mandatory`, `Strict`), no longer a `bool`

### TrustServerCertificate
- In System.Data.SqlClient, server certificates were only validated when `Encrypt` was `true`
- In Microsoft.Data.SqlClient v4.0+, the driver always validates the server certificate based on `TrustServerCertificate`
- Self-signed certificates require `TrustServerCertificate=true`

### DateTime Behavior
- `DbType.Time`: System.Data.SqlClient accepts `DateTime`; Microsoft.Data.SqlClient requires `TimeSpan`
- `DbType.Date`: System.Data.SqlClient sends date and time; Microsoft.Data.SqlClient truncates time components

### Namespace Mappings (v5.0+)

| Old Namespace | New Namespace |
|---|---|
| `System.Data.SqlClient.*` | `Microsoft.Data.SqlClient.*` |
| `Microsoft.SqlServer.Server.SqlDataRecord` | `Microsoft.Data.SqlClient.Server.SqlDataRecord` |
| `Microsoft.SqlServer.Server.SqlMetaData` | `Microsoft.Data.SqlClient.Server.SqlMetaData` |
| `System.Data.SqlTypes.SqlFileStream` | `Microsoft.Data.SqlTypes.SqlFileStream` |
| `System.Data.Sql.SqlNotificationRequest` | `Microsoft.Data.Sql.SqlNotificationRequest` |
| `System.Data.OperationAbortedException` | `Microsoft.Data.OperationAbortedException` |

## Success Criteria

- No `System.Data.SqlClient` references remain in affected projects
- All modified projects build without errors
- Connection strings reviewed and documented for encryption default changes
- Any unconvertible patterns or behavioral changes flagged for the user
