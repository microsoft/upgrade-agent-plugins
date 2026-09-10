# System.Web Adapters

**Category**: Compatibility
**Plan impact**: No

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

**Skill**: `migrating-mvc-system-web-adapters`
The skill is a **standing context skill** — loaded before Phase 0 and active for the
entire scaffold + migrate task duration, not pre-matched per task. It overrides three
feature satellites during those phases:
`migrating-mvc-httpcontext`, `migrating-mvc-http-pipeline`, `migrating-mvc-session-state`.
During the final cleanup subtasks of the migrate task it remains loaded alongside those
feature satellites, providing the shim → native mapping. Most upgrade options change
task structure or executor behavior only and carry no skill ID; an option that does have
one names it on a `**Skill**:` line in its own file, and the compact block in
[upgrade-options-index.md](upgrade-options-index.md) carries the matching `Skill:`
sub-line that loads it.

**Interactions**:
- **Cross-App Cookie Authentication**: [cross-app-cookie-auth.md](cross-app-cookie-auth.md)
  chooses how the Framework and Core hosts share an authenticated user during a
  side-by-side migration. Its **Remote Authentication** value is delivered by this skill and
  carries no binding of its own, so that guidance reaches the user only while this option is
  **Use System.Web Adapters** — not because Remote Authentication technically requires the
  shim overlay. The remote-app packages are separable from the compatibility shims, so
  **Direct Migration to ASP.NET Core APIs** does not rule that mechanism out; it only means
  the wiring is not walked through step by step. **That pairing is valid and must not be
  adjusted** — do not switch this option to **Use System.Web Adapters** merely to deliver the
  walkthrough, which would impose the whole shim overlay on a user who declined it.
- **Suppress the remote authentication client under shared cookies**: when
  Cross-App Cookie Authentication is **Shared Cookie (Data Protection interop)**, the
  remote-app wiring in this skill's side-by-side step must omit its authentication client.
  The shared cookie already authenticates the request, so registering the remote client on
  top authenticates every request twice and risks a redirect loop behind the reverse proxy.
  The shared-session client is a separate concern and stays. **This pairing is valid and must
  not be adjusted.** It is a wiring instruction, not a conflict between two selected values:
  do not "resolve" it by moving either option to another value.

**Affects**: Standing skill load at Phase 0, scaffold task for web projects,
`migrating-mvc-httpcontext` / `migrating-mvc-http-pipeline` / `migrating-mvc-session-state`
override behavior during migrate phases, cleanup subtasks within migrate task.
