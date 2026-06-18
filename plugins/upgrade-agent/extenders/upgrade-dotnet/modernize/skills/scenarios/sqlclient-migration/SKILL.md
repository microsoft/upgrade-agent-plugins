---
name: sqlclient-migration
description: >
  Migrates .NET projects from System.Data.SqlClient to Microsoft.Data.SqlClient.
  Use when user wants to upgrade SqlClient, migrate to Microsoft.Data.SqlClient,
  or modernize SQL Server data access.
requires-extension: upgrade-dotnet
metadata:
  discovery: scenario
  importance: low
  traits: .NET|CSharp|VisualBasic|DotNetCore
  scenarioTraitsSet: [.NET]
---

# SqlClient Migration

## 1. Assessment

Scan the solution to build a complete picture of SqlClient usage. Capture findings in `assessment.md`.

### Packages to Scan For

Search all project files and package management files (`Directory.Packages.props`) for:
- `System.Data.SqlClient` (direct package reference)
- Assembly references to `System.Data` (older projects may use the framework assembly rather than a NuGet package)

### File Inventory

Search all code files across the solution for `using System.Data.SqlClient`. Record which files in which projects contain these usings — this gives a quick per-project file count that drives planning.

### Code Patterns to Identify

The patterns below help gauge complexity per project. You don't need to search for each one separately — note them as you encounter them during the usings scan or during execution:

| Pattern | What to Record |
|---------|---------------|
| `SqlConnection`, `SqlCommand`, `SqlDataReader`, `SqlDataAdapter` | Count and locations — core types that change namespace |
| `SqlBulkCopy` usage | Same namespace change, verify behavior matches |
| `SqlParameter` with `DbType.Time` or `DbType.Date` | DateTime/TimeSpan behavior difference (see risk indicators) |
| `SqlFileStream` | Moves to a different namespace |
| `SqlDataRecord`, `SqlMetaData` | Move to a different namespace |
| `SqlNotificationRequest` | Moves to a different namespace |

### Connection String Analysis

Search `app.config`, `web.config`, `appsettings.json`, and code files for connection strings targeting SQL Server. For each, record:
- Whether `Encrypt` is explicitly set (if not, behavior changes — see risk indicators)
- Whether `TrustServerCertificate` is explicitly set
- Whether the target server uses self-signed certificates (may need `TrustServerCertificate=true`)

### Risk Indicators

Flag these as higher complexity in the assessment:
- **Implicit encryption defaults**: Connection strings without explicit `Encrypt` setting — `Microsoft.Data.SqlClient` defaults to `Encrypt=true` (was `false`), which may break connections to servers without valid TLS certificates
- **DateTime/TimeSpan behavior**: Code passing `DateTime` for `DbType.Time` parameters — `Microsoft.Data.SqlClient` requires `TimeSpan`; `DbType.Date` now truncates time components
- **Self-signed certificates**: Environments using self-signed certs need `TrustServerCertificate=true` added
- **SqlClient v5.0+ enum change**: `Encrypt` property becomes `SqlConnectionEncryptOption` enum instead of `bool`

### Assessment Output

Create `assessment.md` in the workflow folder with this structure:

```markdown
# Assessment: System.Data.SqlClient to Microsoft.Data.SqlClient

## Affected Projects
| Project | Reference Type | Key Patterns | Connection String Risk | Risk |
|---------|---------------|-------------|----------------------|------|
| MyApp.Data | Package ref | SqlConnection, SqlBulkCopy | Encrypt not set | High |
| MyApp.Tests | Transitive | SqlConnection in test helpers | N/A | Low |

## Connection Strings Found
| Location | Encrypt Set? | TrustServerCertificate Set? | Action Needed |
|----------|-------------|---------------------------|---------------|
| appsettings.json | No | No | Review — defaults changed |

## Key Findings
- [Notable patterns, risks, or decisions needed]
```

## 2. Planning

Based on the assessment, create `plan.md` with tasks ordered bottom-up (leaf dependencies first, then consumers).

For each task include:
- Which projects or groups of projects are covered
- What changes are needed (packages, code, connection strings)
- Risk level and anything requiring user decision

Include a cross-cutting task for connection string review if any strings lack explicit encryption settings.

## 3. Execution

Execute the plan task by task. For any task that involves migrating SqlClient code or packages, apply the **migrating-to-microsoft-data-sqlclient** feature skill. It provides namespace mappings, package changes, encryption guidance, and validation steps.

After completing all tasks, do a final solution-wide search for any remaining `System.Data.SqlClient` references and fix stragglers.

## 4. Validation

- Build the full solution — zero errors required
- No remaining `System.Data.SqlClient` namespace references in code
- Connection strings reviewed and documented for encryption default changes
- If the project had tests, run them and report results
