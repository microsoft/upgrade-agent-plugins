---
name: migrating-aspnet-framework-to-core
description: >
  Orchestrates migration of ASP.NET Framework (System.Web) MVC and WebAPI projects
  to ASP.NET Core. Covers only old .NET Framework web projects — not applicable to
  ASP.NET Core or modern .NET web projects (those are already on the target stack).
  Defines the ordered phase sequence (project file, host, config, DI, controllers,
  middleware, auth, views, cleanup), satellite skill dispatch, and migration unit
  breakdown for both in-place and side-by-side modes. Use when executing a task that
  upgrades a project with System.Web dependencies, HttpModules, HttpHandlers, MVC
  controllers, WebAPI controllers, or Global.asax. Also triggers for "migrate ASP.NET
  to Core", "upgrade MVC project", "convert WebAPI to ASP.NET Core". Not applicable
  to class libraries unless they directly reference System.Web.
metadata:
  discovery: lazy
  traits: .NET|CSharp|VisualBasic|DotNetCore
---

# ASP.NET Framework → ASP.NET Core Migration

## ⛔ Read This First

This skill defines **how to execute** a web project migration task:
- The migration steps and gates between them
- Which satellite skills to load and when
- Links to mode-specific guidance for task boundaries

It does not define which projects to migrate or in what order across the solution —
that is the strategy's responsibility.

**Do not mention internal step names (like "Phase 5") in chat.** Describe the work
in plain language: "migrating controllers", "setting up configuration", etc.

**Two modes** depending on the Project Approach upgrade option:

| Project Approach | Mode | Guidance |
|-----------------|------|----------|
| In-place rewrite | **In-Place** | Execute all steps sequentially within one task |
| Side-by-side | **Side-by-Side** | Load [side-by-side.md](side-by-side.md) for scaffold/migrate task boundaries |

Determine mode from `scenario-instructions.md` (Upgrade Options > Project Approach) before proceeding.

---

## Satellite Skill Loading Guide

This migration touches many complex feature areas. Each has a dedicated satellite skill
with depth this orchestrator does not repeat. Load satellites **just before** the phase
that needs them — not all upfront.

### When to Load Which Satellite

| Assessment Signal | Satellite Skill | Load Before |
|-------------------|----------------|-------------|
| `UsesHttpModules`, `UsesHttpHandlers`, `UsesGlobalAsax` | `migrating-global-asax`, `migrating-mvc-http-pipeline` | Middleware migration |
| `UsesHttpContextCurrent`, `UsesHttpServerUtility` | `migrating-mvc-httpcontext` | DI container setup |
| `UsesFormsAuth`, `UsesMembership`, `UsesWindowsAuth`, `UsesOwinAuth`, `UsesOAuthMiddleware` | `migrating-mvc-authentication` | Authentication migration |
| `UsesOwin`, `UsesKatana`, `UsesAppBuilder` | `migrating-owin-to-aspnet-core` | Middleware migration |
| `UsesSession`, `UsesTempData`, `UsesApplicationState` | `migrating-mvc-session-state` | DI container setup |
| `UsesCustomDependencyResolver`, `UsesAutofac`, `UsesUnity`, `UsesNinject`, `UsesCastleWindsor` | `migrating-mvc-dependency-injection` | DI container setup |
| `UsesAttributeRouting`, `UsesRouteConstraints`, `UsesAreaRouting` | `migrating-mvc-routing` | Controller migration |
| `UsesWebApiControllers`, `UsesHttpResponseMessage`, `UsesContentNegotiation`, `UsesCustomFormatters` | `migrating-mvc-controllers`, `migrating-mvc-content-negotiation` | Controller migration |
| `UsesMvcControllers`, `UsesChildActions`, `UsesHtmlHelpers` | `migrating-mvc-controllers` | Controller migration |
| `UsesCustomFilters`, `UsesOutputCache`, `UsesHandleError` | `migrating-mvc-filters` | Controller migration |
| `UsesCustomModelBinders`, `UsesFromUri`, `UsesValueProviders` | `migrating-mvc-model-binding` | Controller migration |
| `UsesMvcViews`, `UsesBundling`, `UsesHtmlHelpers`, `UsesChildActions` | `migrating-mvc-razor-views` | Views migration |

### Loading Rules

1. **During baseline capture** — inventory which satellites will be needed
   for this project and note them. Do not load them yet.
2. **Load satellite just before the step that needs it** — not all upfront. Token
   budget matters; load only what the current step requires.
3. **If a satellite is not available** — proceed with caution, note the gap, apply
   general knowledge, and flag areas requiring manual review.
4. **Multiple satellites may apply to the same step** — load all relevant ones before
   starting that step.

---

## Migration Steps

These steps apply to both modes. In-place executes them sequentially.
Side-by-side splits them across tasks — see [side-by-side.md](side-by-side.md).

---

### Baseline Capture

Before any changes, record:

**Endpoint inventory** (becomes acceptance checklist for final verification):
- All routes and HTTP methods
- Expected response shapes and status codes per endpoint
- Authentication/authorization rules per endpoint
- Custom HTTP headers set by the application

**Pipeline inventory** (drives middleware migration):
- All `HttpModule` registrations and their pipeline event hooks, in order
- All `HttpHandler` and `IHttpAsyncHandler` registrations
- All `Global.asax` event handlers in use

**Feature inventory** (determines satellite loading):
- Review assessment signals and note which satellites from the loading guide above apply
- Flag any `HttpContext.Current` / `ClaimsPrincipal.Current` static access patterns
- Flag any third-party DI container in use
- Flag session, TempData, or application state usage
- Flag any OWIN/Katana middleware

**Gate**: Baseline document exists. Satellite list noted. No proceeding until complete —
this document is the acceptance oracle for final verification.

---

### Project File and SDK

- Replace legacy `.csproj` format with SDK-style format
- Set `<TargetFramework>` to target version
- Remove `packages.config` — migrate all references to `<PackageReference>`
- Remove web-specific MSBuild imports (`Microsoft.WebApplication.targets`, etc.)
- Remove `System.Web` assembly references from project file
- Verify no orphaned references remain

**Gate**: Project loads in IDE without errors. No compilation required yet.

---

### Entry Point and Host

- Create `Program.cs` with minimal `WebApplication` host — no features, stub only
- Wire `app.MapGet("/health", () => "ok")` as a smoke test endpoint
- Verify: `dotnet build` succeeds, `dotnet run` starts, stub endpoint returns 200

**Gate**: App starts and responds. This is the "green field confirmed" gate.
Do not add any features until this is green — a broken host wastes all subsequent work.

---

### Configuration

- Migrate `Web.config` `<appSettings>` → `appsettings.json`
- Migrate `Web.config` `<connectionStrings>` → `appsettings.json` connection strings section
- Wire `IConfiguration` in `Program.cs`
- Replace all `ConfigurationManager.AppSettings["key"]` calls with `IConfiguration["key"]`
- Replace all `ConfigurationManager.ConnectionStrings["name"]` with `IConfiguration.GetConnectionString("name")`
- Migrate environment-specific transforms (`Web.Debug.config`) → `appsettings.Development.json`
- Move secrets (passwords, API keys) out of config files → User Secrets (dev) or environment variables

**Gate**: All configuration keys accessible via `IConfiguration`.
No `ConfigurationManager` references remain in non-legacy code.

**Note**: Do not migrate authentication configuration here — that belongs to the
authentication migration step.
Connection strings are config, auth settings are not.

> **If** assessment signals include `UsesCustomConfigSections`, `UsesEncryptedConfig`,
> or `UsesConfigTransforms` beyond simple appSettings → flag for manual review.
> Custom config section types have no direct equivalent and require IOptions<T> redesign.

---

### Dependency Injection Container

> **Load satellites before this phase**:
> - `migrating-mvc-dependency-injection` if any of: `UsesAutofac`, `UsesUnity`, `UsesNinject`,
>   `UsesCastleWindsor`, `UsesCustomDependencyResolver`
> - `migrating-mvc-httpcontext` if: `UsesHttpContextCurrent`, `UsesHttpServerUtility`
> - `migrating-mvc-session-state` if: `UsesSession`, `UsesApplicationState`

- Register all application services in `Program.cs` or extension methods
- Replace `DependencyResolver.SetResolver` (MVC) or `config.DependencyResolver` (WebAPI)
  with `builder.Services` registrations
- Register `DbContext`, repositories, application services
- Add `IHttpContextAccessor` registration if `HttpContext.Current` usage was found during baseline capture
- Register session services if session usage was found (`builder.Services.AddSession()`)
- Do not implement services that still have `System.Web` dependencies — stub them with
  `NotImplementedException` and a TODO comment, resolve during controller migration

**Lifetime mapping**:
| Old | New |
|-----|-----|
| Per-request / `InstancePerRequest` | `Scoped` |
| Singleton | `Singleton` |
| Transient / `InstancePerDependency` | `Transient` |

**Gate**: Application starts and DI container resolves without errors.
All services registered (stubs acceptable for System.Web-dependent ones).

---

### Controllers and Action Results

> **Load satellites before this phase**:
> - `migrating-mvc-routing` if: `UsesAttributeRouting`, `UsesRouteConstraints`, `UsesAreaRouting`
> - `migrating-mvc-controllers` if: `UsesWebApiControllers`, `UsesHttpResponseMessage`
> - `migrating-mvc-controllers` if: `UsesMvcControllers`, `UsesChildActions`
> - `migrating-mvc-filters` if: `UsesCustomFilters`, `UsesOutputCache`, `UsesHandleError`
> - `migrating-mvc-model-binding` if: `UsesCustomModelBinders`, `UsesFromUri`

> **In Side-by-Side mode**: This phase is the repeating migration unit.
> Each unit = one controller group (by feature area) + associated filters + models.
> Complete and validate each unit before starting the next.
> See Mode Reference section for unit ordering guidance.
>
> **Controller triage** (before creating units): Read each controller file to
> assess complexity — constructor dependencies, auth requirements, action count,
> use of complex features (child actions, custom filters, model binders), and
> any other signals that indicate migration difficulty. Group by feature area
> (folders, naming, areas). Order: simplest first, auth-dependent last.
> Complex controllers with many dependencies should be their own unit.
>
> **Per-unit dependency discovery** (when starting each unit): Use
> `get_code_dependencies` on the controller(s) in the current unit to discover
> explicit code dependencies — services, models, views, packages. Then also
> check for **implicit dependencies** not visible in the code graph:
> - Review baseline capture: which HTTP modules, handlers, or Global.asax
>   events affect this controller's endpoints?
> - Check for `HttpContext.Current`, `ConfigurationManager`, or static helper
>   usage that won't work in Core without explicit registration
> - Check `RouteConfig.cs` / `WebApiConfig.cs` for non-attribute routes that
>   serve this controller
> - Check `FilterConfig.cs` for global filters this controller depends on
>
> Verify each dependency is ready in the new project:
> - DI: are the controller's injected services registered? Replace stubs if needed.
> - Config: are the config keys the controller reads present in `appsettings.json`?
> - References: can the new project reference the class libraries this controller uses?
> - Routes: is `app.MapControllers()` in the pipeline? Are non-attribute routes configured?
> - Pipeline: are HTTP modules this controller depends on replicated as middleware?
>
> Fix any gaps before porting the controller code. Document in task.md.

**For each controller:**
- Change namespace from `System.Web.Mvc` or `System.Web.Http` to `Microsoft.AspNetCore.Mvc`
- MVC: keep `Controller` base class
- WebAPI: switch from `ApiController` to `ControllerBase`
- Apply `[ApiController]` attribute if pure API (no views) — understand its behavior
  changes before applying (auto-400, binding inference)
- Migrate route attributes — consult `migrating-mvc-routing` satellite for combining rules
- Migrate return types — consult `migrating-mvc-controllers` for WebAPI specifics
- Migrate binding source attributes (`[FromUri]` → `[FromQuery]`/`[FromRoute]`)
- Migrate associated filters — consult `migrating-mvc-filters` satellite
- Remove `AreaRegistration` classes — keep area folder structure, registration is now automatic

**Gate (per unit in side-by-side)**: Unit builds, all endpoints in unit return expected
status codes per baseline, unit tests pass.

**Gate (in-place)**: All controllers migrated, solution builds, all endpoints respond
per baseline.

---

### Middleware Pipeline

> **Load satellites before this phase**:
> - `migrating-global-asax`, `migrating-mvc-http-pipeline` if: `UsesHttpModules`, `UsesHttpHandlers`, `UsesGlobalAsax`
> - `migrating-owin-to-aspnet-core` if: `UsesOwin`, `UsesKatana`

**Pipeline ordering is the critical concern here.** Reconstruct from baseline inventory.

High-level mapping reference:

| Old construct | Core equivalent |
|---------------|----------------|
| `IHttpModule.BeginRequest` | Middleware registered before `next()` |
| `IHttpModule.EndRequest` | Middleware registered after `next()` |
| `IHttpModule.AuthenticateRequest` | Auth middleware — position relative to `UseAuthentication()` |
| `IHttpHandler` | Minimal API endpoint or terminal middleware |
| `IHttpAsyncHandler` | Async terminal middleware |
| `Global.asax Application_Start` | `Program.cs` startup code |
| `Global.asax Application_End` | `IHostApplicationLifetime.ApplicationStopping` |
| `Global.asax Application_Error` | Exception handling middleware |
| `DelegatingHandler` (WebAPI) | Middleware — position in pipeline must match original handler order |

> For anything beyond basic module-to-middleware mapping, consult `migrating-mvc-http-pipeline`.
> Pipeline ordering errors produce subtle bugs that are difficult to diagnose.

**Gate**: Application pipeline behaves equivalently to baseline for
non-authenticated requests. All custom middleware registered in correct order.

---

### Authentication and Authorization

> **Load satellite before this phase**:
> - `migrating-mvc-authentication` — always load for this phase when any auth is present.
>   Auth is security-critical and has multiple distinct migration paths.
>   Do not proceed based on general knowledge alone.

> Execute this step after the pipeline is stable (middleware migration complete).
> Auth is the hardest to debug when the pipeline is uncertain.

High-level path selection (satellite provides full detail for each):

| Detected auth mechanism | Migration path |
|------------------------|----------------|
| `FormsAuthentication` | Cookie authentication middleware |
| `SqlMembership` / `SimpleMembership` | ASP.NET Core Identity (schema migration required) |
| Custom `MembershipProvider` | Custom `IUserStore<T>` or `IAuthenticationHandler` |
| Windows Authentication | Negotiate middleware |
| OWIN OAuth / token server | IdentityServer / Duende / OpenIddict |
| Custom `IPrincipal` / claims | `IClaimsTransformation` |
| `Web.config <authorization>` rules | Policy-based authorization |

**Gate**: Authenticated and unauthenticated request flows match baseline.
Run the full auth rules inventory from baseline capture as acceptance checklist.

---

### Views and Static Assets (MVC projects only)

> **Load satellite before this phase**:
> - `migrating-mvc-razor-views` if: `UsesMvcViews`, `UsesBundling`, `UsesHtmlHelpers`,
>   `UsesChildActions`, `UsesDisplayTemplates`, `UsesEditorTemplates`

High-level checklist (satellite provides full detail):

- Remove `@Scripts.Render` / `@Styles.Render` calls — no built-in equivalent
- Replace common `HtmlHelper` calls with Tag Helpers (`Html.ActionLink` → `<a asp-*>`, etc.)
- Convert child actions (`Html.Action()`) to View Components
- Convert `@helper` Razor helpers to partial views or Tag Helpers
- Move static files from `Content/` and `Scripts/` to `wwwroot/`
- Add `app.UseStaticFiles()` to `Program.cs`
- Choose and configure bundling approach (WebOptimizer, npm pipeline, or direct references)
- Add `_ViewImports.cshtml` with Tag Helper namespace imports
- Verify `_ViewStart.cshtml` layout reference is correct

**Gate**: All views render without errors. Static assets load. No `@Scripts.Render`
or `@Styles.Render` references remain.

---

### Cleanup and Verification

- Remove all `#if NETFRAMEWORK` conditional blocks
- Remove remaining `System.Web` references if any remain (there should be none)
- Remove `WebApiConfig.cs`, `RouteConfig.cs`, `FilterConfig.cs`, `BundleConfig.cs`
  from old project's code that was copied to new project
- Remove `packages.config` if not already done
- Remove unused compatibility shims or adapter layers added during migration

> **Do NOT delete the old Framework project.** In side-by-side mode, the old
> project stays in the solution. Physical removal is a post-upgrade step for
> the user. In in-place mode, this section cleans up the converted project.

**Verify against baseline**:
- [ ] All endpoints return expected status codes
- [ ] Authentication flows work end to end (each auth rule from baseline)
- [ ] All configuration values load correctly
- [ ] No `System.Web` references remain (`dotnet list package` confirms)
- [ ] Solution builds with 0 errors and 0 migration-related warnings
- [ ] All tests pass
- [ ] Static assets load (MVC projects)

---

## Library Dependencies With System.Web References

If the task scope includes class libraries that reference `System.Web`:

- Apply config, DI, controllers, middleware, auth steps only — no project setup, no views
- Primary concern: replace `System.Web` API surface with abstractions injectable via DI
- Migrate before the web project that consumes them — they must be clean before controller migration
- Common patterns requiring architectural discussion (not just API swap):
  - `HttpContext.Current` in a library — load `migrating-mvc-httpcontext` satellite
  - `HttpServerUtility` usage — no direct equivalent, method-by-method replacement needed
  - Static auth access (`HttpContext.Current.User`) — requires `IHttpContextAccessor` threading care

---

## Mode Reference

### In-Place Mode

All migration steps execute sequentially within a single project upgrade task.
No task boundaries between steps.

### Side-by-Side Mode (Project Approach = Side-by-side)

**Load [side-by-side.md](side-by-side.md)** for the complete scaffold/migrate
task structure, scaffold checklist, and controller migration subtask ordering.
Old project is not deleted — removal is a post-upgrade step for the user.
