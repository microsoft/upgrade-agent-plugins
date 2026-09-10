# Side-by-Side Migration Mode

Task structure when the Project Approach upgrade option selects Side-by-side.
The old Framework web project stays running while a new Core project is built
alongside it.

## Contents

1. [Task Boundaries](#task-boundaries)
2. [Scaffold Task Checklist](#scaffold-task-checklist) — includes the shared-database gate
3. [Migrate Task Subtask Ordering](#migrate-task-subtask-ordering)
4. [Migrate Task Final Subtasks](#migrate-task-final-subtasks)

## Task Boundaries

| Plan task | What happens |
|-----------|-------------|
| `scaffold-{name}` | Create new Core project + baseline capture + initial config/DI |
| `migrate-{name}` | Port controllers, middleware, auth, views — broken into subtasks. Final subtasks handle reference cleanup (re-point tests, remove multi-targeting). |

> **No decommission task.** The old Framework project is NOT deleted by the agent.
> Physical removal is a post-upgrade step documented in final validation for the
> user to perform after confirming production readiness.

---

## Scaffold Task Checklist

Load the `scaffolding-yarp-proxy-project` skill:
`get_instructions(kind='skill', query='scaffolding-yarp-proxy-project')`
Follow its instructions to create the new project (it handles tool detection,
script execution, and manual fallback automatically).

The scaffolding creates a bare-bones project (host + YARP proxy). That is NOT enough —
you must complete these additional steps before marking the scaffold task as done:

- [ ] **Baseline capture** — record all endpoints, routes, HTTP methods, auth rules,
  pipeline components, and feature inventory from the OLD project. Write to task.md.
  This becomes the acceptance checklist for the final verification step.
- [ ] **Scaffold project** — load `scaffolding-yarp-proxy-project` skill and follow it
  to create the new ASP.NET Core project with YARP proxy configuration
- [ ] **Decide the authentication interop path** — see "Authentication interop" below.
  This is a scaffold-time decision because the scaffold can pre-wire the Core half.
  Skipping it does not fail anything here; it surfaces later as users appearing signed
  out on the new app.
  Already decided if `Cross-App Cookie Authentication` is among the confirmed upgrade
  options — carry that value through rather than choosing again.
- [ ] **Verify host** — new project builds, starts, returns 200 on health endpoint,
  proxies requests to old app via YARP
- [ ] **Check for a shared database — do this BEFORE copying connection strings.** If the new
  Core project will use the same database as the still-running Framework app, you MUST load
  the shared-database skill and follow it before registering any `DbContext` or enabling any
  migration: `get_instructions(kind='skill', query='managing-shared-database-schema')`
  It decides who owns schema changes and forbids destructive DDL while both hosts are live.
  Copying a connection string is what creates the shared-database window — treat it as the
  trigger, not an afterthought.
- [ ] **Migrate global config** — copy `appSettings` and `connectionStrings` from
  `Web.config` to `appsettings.json`. Wire `IConfiguration` in `Program.cs`.
- [ ] **Initial DI registrations** — register `DbContext`, obvious shared services,
  `IHttpContextAccessor` if needed. Use stubs for services that can't be fully
  registered yet. Do NOT enable `Database.Migrate()` at startup — see the shared-database
  skill above.
- [ ] **Add `app.MapControllers()`** to the pipeline so controllers can be routed
- [ ] **Reference class libraries** — add project references to any multi-targeted
  or already-migrated class libraries the web project depends on

**Gate**: New project builds, starts, proxies to old app, has config and basic DI
working. The FIRST controller migrated should be able to resolve its dependencies.

Config and DI are NOT fully complete here — additional registrations and config keys
are added incrementally as each controller is migrated.

---

## Migrate Task Subtask Ordering

The migrate task is broken into subtasks. The ordering is critical for testability:

```
[Non-auth controllers, simplest first]
  xx.01-{feature}-controllers    ← one subtask per controller
  xx.02-{feature}-controllers    ← ordered simplest → most complex
  ...

[Middleware pipeline]
  xx.NN-middleware               ← single subtask, after all non-auth controllers

[Authentication]
  xx.NN-auth                     ← single subtask, after middleware

[Auth-dependent controllers]
  xx.NN-{auth-feature}-controllers  ← ONLY after auth is working
```

**Auth-protected controllers MUST come AFTER the auth subtask, not before.**
Controllers with `[Authorize]` will fail on every request until auth middleware
is configured. The sequence is: non-auth controllers → middleware → auth →
auth controllers.

> **Auth interop is a different thing from the auth subtask, and it is needed earlier.**
> While both apps are running, a user signed in on the Framework app is not signed in on
> the Core app unless the two are wired together. See **Authentication interop** at the
> end of this file. Not doing it does not fail a build or a subtask — it surfaces as
> users appearing signed out.

### Controller triage (before creating subtasks)

Read each controller file to assess complexity — constructor dependencies,
auth requirements, action count, use of complex features (child actions,
custom filters, model binders), and any other signals that indicate migration
difficulty. Group by feature area (folders, naming, areas). Order: simplest
first, auth-dependent last.

**One controller per subtask — no grouping.** Order: simplest
first, auth-dependent last. Complex controllers with many dependencies
get the same treatment as simple ones — one subtask each.

### Per-unit dependency discovery (when starting each subtask)

Use `get_code_dependencies` on the controller(s) in the current unit to
discover explicit code dependencies — services, models, views, packages.
Then also check for **implicit dependencies** not visible in the code graph:
- Review baseline: which HTTP modules, handlers, or Global.asax events affect
  this controller's endpoints?
- Check for `HttpContext.Current`, `ConfigurationManager`, or static helper
  usage that won't work in Core without explicit registration
- Check `RouteConfig.cs` / `WebApiConfig.cs` for non-attribute routes
- Check `FilterConfig.cs` for global filters this controller depends on

Verify each dependency is ready in the new project:
- DI: are the controller's injected services registered? Replace stubs if needed.
- Config: are the config keys the controller reads present in `appsettings.json`?
- References: can the new project reference the class libraries this controller uses?
- Routes: is `app.MapControllers()` in the pipeline? Are non-attribute routes configured?
- Pipeline: are HTTP modules this controller depends on replicated as middleware?

Fix any gaps before porting the controller code. Document in task.md.

### Each subtask should be testable on completion

| Subtask type | How to verify |
|-------------|---------------|
| Non-auth controller | Endpoints return expected status codes for anonymous requests |
| Middleware | Pipeline behavior matches baseline for non-authenticated requests |
| Auth | Login/logout flows work end to end |
| Auth interop | Sign in on the Framework app, then confirm the Core app still identifies the user in the same session |
| Auth controller | Protected endpoints enforce auth correctly |

---

## Migrate Task Final Subtasks

After all controller, middleware, and auth subtasks are complete:

### Views and static assets (MVC only)
Migrate views, layouts, and static files to the Core project.
See the main skill's Views and Static Assets section.

### Reference cleanup
- Re-point test project references from old web project to new Core project
- Remove multi-targeting from libraries that were dual-targeting only for the old project
- Remove compatibility shims or adapter layers no longer needed
- Verify solution builds with 0 errors after reference changes

### Final verification
- Verify all endpoints against baseline
- All tests pass (including re-pointed test projects)
- No `System.Web` references remain in the new project

> **The old Framework project stays in the solution.** Do not delete it.
> Final validation documents its removal as a post-upgrade step for the user.

### Middleware and Auth timing

- Middleware migration is a single subtask — after all non-auth controllers complete
- Auth migration is a single subtask — after middleware completes
- Neither is per-controller-unit — they apply to the whole new project

---

## Authentication interop

Side-by-side means both apps serve real traffic at the same time, so a session has to
span them. A user who signs in on the .NET Framework app is **not** signed in on the new
Core app until this is wired — they simply appear signed out, with no error and nothing in
the logs. The scaffold emits `AddAuthentication()` with no scheme configured, which
compiles and starts and authenticates nobody.

This is not the same work as the `xx.NN-auth` subtask. That subtask ports the old app's
own authentication code to Core. Interop is what keeps users signed in **while both are
running**, and it is needed from the moment the proxy serves its first request.

**If `Cross-App Cookie Authentication` is among the confirmed upgrade options, the path is
already chosen — map it, do not derive it again.** That option is settled with the user during
planning and recorded in the compact block, and it is never reopened afterwards:

| Confirmed value | Path |
|---|---|
| `Remote Authentication` | **Remote auth** |
| `Shared Cookie (Data Protection interop)` | **Shared cookie** |

Apply the **Use when** column below only when that option is **absent** from the confirmed
selections — the scaffold is reachable outside the .NET version upgrade scenario, and the
option does not trigger for every app. Absence is not a signal about which path is right; it
just means nobody has chosen yet, so choose from the criteria as written. Only the path
*selection* is gated on absence: **Wiring it** below applies either way, because a confirmed
value chooses the path, it does not remove the work.

Two supported paths — pick one, they are mutually exclusive:

| Path | How it works | Use when |
|---|---|---|
| **Shared cookie** | Both apps read the same encrypted cookie, via a shared Data Protection key ring | Both apps are cookie-authenticated and can reach shared key storage |
| **Remote auth** | The Core app asks the Framework app who the user is, over HTTP | The Framework app owns a sign-in flow that is not being moved yet, or the key ring cannot be shared |

**Wiring it:**

1. **Core half** — the `scaffolding-yarp-proxy-project` skill can pre-wire either path at
   scaffold time. See its "Authentication interop" section for the parameters. This is why
   the decision belongs in the scaffold checklist above, not here.
2. **.NET Framework half** — always a separate step, and the scaffold never does it. Load
   the matching skill:
   - shared cookie → `get_instructions(kind='skill', query='sharing-authentication-cookies-katana-interop')`
   - remote auth → `get_instructions(kind='skill', query='migrating-mvc-system-web-adapters')`

   One gate on the remote-auth line: when `Cross-App Cookie Authentication` is confirmed as
   `Remote Authentication` **and** `System.Web Adapters` is confirmed as `Direct Migration to
   ASP.NET Core APIs`, do not load that skill — it carries the shim overlay the user declined,
   and its "defer to the shim" rule would govern a migration they asked to do without shims.
   Wire the remote-app client from the Core-side handoff note instead and tell the user this
   half is not walked through step by step. That reduced walkthrough is the expected outcome,
   not a problem to fix by turning the overlay on. With either value absent, load it as above.

   When the project was scaffolded by `scaffold-project.ps1`, it also carries a
   `README.SHAREDCOOKIE.md` or `README.REMOTEAUTH.md` in its root with the specifics. The
   `scaffold_yarp_proxy_web_project` tool (the Visual Studio path) writes **no** README — there,
   state the Framework-side steps directly rather than pointing at a file that does not exist.

**Half-wired is the normal failure.** The Core half alone changes nothing observable — the
app still builds, still starts, still proxies. Do not treat "the scaffold configured auth"
as done, and tell the user the .NET Framework half is still outstanding.

**Verify with two browsers' worth of state, not one request.** Sign in on the Framework app,
then hit a Core endpoint in the same session and confirm the user is still identified.
A 200 from an anonymous endpoint proves nothing here.
