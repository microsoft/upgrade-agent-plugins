# Logging Framework

**Category**: Modernization

**Applicable when**:
- A third-party logging framework is in use:
  - `log4net`
  - `NLog` (without existing `NLog.Extensions.Logging` integration)
  - `ELMAH`
  - `Common.Logging`
  - Significant `System.Diagnostics.Trace` usage (> 10 call sites)

**Not applicable when**:
- No logging framework detected
- Already using `Microsoft.Extensions.Logging`
- `Serilog` detected with existing `Serilog.Extensions.Logging` integration
  (already integrated, no migration needed)
- `NLog` detected with existing `NLog.Extensions.Logging` integration
  (already integrated, no migration needed)

**Default logic**:
- Recommend **Migrate to Extensions.Logging** if:
  - `log4net` or `ELMAH` detected (no clean .NET Core integration story)
  - `System.Diagnostics.Trace` only (no real logging framework — migrate fully)
  - `Common.Logging` detected (effectively abandoned, migrate away)
- Recommend **Keep Existing** if:
  - `Serilog` without adapter (excellent adapter available, team may prefer it)
  - `NLog` without adapter (excellent adapter available, team may prefer it)
  - Team has confirmed significant investment in framework-specific features

**Options**:
- **Migrate to Microsoft.Extensions.Logging** *(default when applicable)* —
  replaces existing logging with built-in abstraction. Consistent with .NET Core
  ecosystem. Supports pluggable providers.
- **Keep Existing Logging Framework** — retains current framework with appropriate
  adapter packages. Minimizes code changes.

**Stored as**: `Upgrade Options > Modernization > Logging Framework`

**Affects**: Whether logging migration tasks are added to the plan, which
packages are added during execution.
