# Side-by-Side Migration Mode

Task structure when the Project Approach upgrade option selects Side-by-side.
The old Framework web project stays running while a new Core project is built
alongside it.

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
- [ ] **Verify host** — new project builds, starts, returns 200 on health endpoint,
  proxies requests to old app via YARP
- [ ] **Migrate global config** — copy `appSettings` and `connectionStrings` from
  `Web.config` to `appsettings.json`. Wire `IConfiguration` in `Program.cs`.
- [ ] **Initial DI registrations** — register `DbContext`, obvious shared services,
  `IHttpContextAccessor` if needed. Use stubs for services that can't be fully
  registered yet.
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

⛔ **Auth-protected controllers MUST come AFTER the auth subtask, not before.**
Controllers with `[Authorize]` will fail on every request until auth middleware
is configured. The sequence is: non-auth controllers → middleware → auth →
auth controllers.

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
