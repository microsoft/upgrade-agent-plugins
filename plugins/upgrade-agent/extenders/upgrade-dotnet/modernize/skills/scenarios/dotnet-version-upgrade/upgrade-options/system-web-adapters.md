# System.Web Adapters

**Category**: Compatibility

**Applicable when**:
- Any of the following detected:
  - `System.Web` assembly references
  - ASP.NET Framework MVC project
  - ASP.NET Framework WebAPI project
  - `HttpContext.Current` usage
  - `HttpModule` or `HttpHandler` registrations

**Not applicable when**:
- No `System.Web` references anywhere in the solution
- Projects are already ASP.NET Core

**Default logic**:
- Recommend **Use System.Web Adapters** if:
  - Side-by-side web migration is selected OR likely (web projects detected), OR
  - `HttpContext.Current` usage is widespread (> 10 occurrences), OR
  - Large web project (> 10k LOC in web layer)
- Recommend **Direct Migration** if:
  - Small web project (≤ 10 controllers, minimal middleware), AND
  - In-place approach confirmed (Project Approach option), AND
  - Low `HttpContext.Current` usage (isolated, easy to replace)

**Options**:
- **Use System.Web Adapters** *(default when applicable)* — adds
  `Microsoft.AspNetCore.SystemWebAdapters` package. Provides compatibility
  shims for `HttpContext.Current`, `HttpRequest`, `HttpResponse`. Enables
  incremental migration. Requires cleanup pass after migration completes.
- **Direct Migration to ASP.NET Core APIs** — no adapter shims. All `System.Web`
  usage replaced immediately with native ASP.NET Core equivalents. More upfront
  work, cleaner result, no compatibility layer to remove later.

**Stored as**: `Upgrade Options > Compatibility > System.Web Adapters`

**Skill**: `aspnet-system-web-adapters`
This is the only option that carries a skill ID. The skill is a **standing context skill** —
loaded before Phase 0 and active for the entire scaffold + migrate task duration, not
pre-matched per task. It overrides three feature satellites during those phases:
`aspnet-httpcontext-migration`, `aspnet-pipeline-migration`, `aspnet-session-migration`.
During the final cleanup subtasks of the migrate task it remains loaded alongside those
feature satellites, providing the shim → native mapping. All other upgrade options change
task structure or executor behavior only — none carry a skill ID.

**Affects**: Standing skill load at Phase 0, scaffold task for web projects,
`aspnet-httpcontext-migration` / `aspnet-pipeline-migration` / `aspnet-session-migration`
override behavior during migrate phases, cleanup subtasks within migrate task.
