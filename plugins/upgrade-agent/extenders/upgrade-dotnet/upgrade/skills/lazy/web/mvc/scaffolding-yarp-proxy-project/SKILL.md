---
name: scaffolding-yarp-proxy-project
description: >
  Scaffolds a new ASP.NET Core project with YARP reverse proxy alongside an existing
  .NET Framework MVC or WebAPI project for incremental side-by-side migration. Use when
  a migration task requires creating a new Core project that proxies to the old Framework
  app, when the side-by-side migration approach is selected, or when scaffold/YARP/proxy
  setup is needed. Also triggers for "create new Core project", "set up YARP proxy",
  "side-by-side project setup".
metadata:
  discovery: lazy
  traits: .NET|CSharp|VisualBasic|DotNetCore
---

# Scaffold ASP.NET Core Project with YARP Proxy

Creates a new ASP.NET Core web project alongside an existing .NET Framework
MVC or WebAPI project. The new project is configured with a YARP reverse proxy
that routes unhandled requests to the old project, enabling incremental
controller-by-controller migration.

> **Scope — .NET Framework → Core only.** This scaffold exists for *side-by-side incremental
> migration*: it adds `Microsoft.AspNetCore.SystemWebAdapters.CoreServices` and the
> `_MigrateToProjectGuid` link so a new Core app can front a **still-running .NET Framework**
> app. Do **not** run it for a Core-to-Core version upgrade (e.g. `net8.0` → `net10.0`) — there
> is no `System.Web` to adapt and no second app to strangle, so it would add meaningless
> dependencies and a bogus migration marker. Retarget the TFM in place instead. The
> **Production hardening** below is generic ASP.NET Core guidance that applies to any app behind
> a proxy; only the **Framework-side companion** is Framework-specific.
>
> Equally, do **not** run it for an in-place .NET Framework retarget (e.g. `net472` → `net48`).
> That upgrade produces no second app, and the proxy host itself must be ASP.NET Core — YARP and
> `SystemWebAdapters.CoreServices` have no .NET Framework target. In this scaffold the Framework
> app is the proxy's *backend* (`-OldAppUrl`), never its host.

## REQUIRED: Read This File Completely

This file contains **2 steps** and **10 sub-steps** for manual scaffolding. You MUST read all sections before starting:

| Step | Section | What It Covers |
|------|---------|----------------|
| 1 | Check for Existing Tool | Try `scaffold_yarp_proxy_web_project` tool first |
| 2 | Scaffold Using Script + Templates | Primary path — script + template files |
| 2.1 | Gather Parameters | Paths, TFM, URLs, package versions |
| 2.2 | Run the Script | Script copies templates, adds to solution, links projects |
| 2.3 | If Script Fails | Manual fallback — copy templates, replace placeholders |
| - | Production hardening | **Required** — forwarded headers, TLS, `UseAuthentication`, Framework-side companion |
| - | Template Files Reference | What each template contains |
| - | Success Criteria | Final checklist |

**Do not stop reading after Step 1.** If the tool is unavailable, you need Steps 2.1–2.10.

## Prerequisites

Before using this skill, you need:
- Path to the **old .NET Framework web project** (.csproj)
- Path to the **solution file** (.sln or .slnx) containing it
- **Target framework** for the new project (e.g., `net10.0`)
- **Project type**: MVC or WebAPI
- **New project name** (default: `{OldProjectName}.Core`)

## Step 1: Check for Existing Tool

First, check if `scaffold_yarp_proxy_web_project` tool is available in your
environment. If it is, use it — it handles everything automatically:

```
scaffold_yarp_proxy_web_project(
  solutionPath="{solution_path}",
  projectPath="{old_project_path}",
  targetFramework="{tfm}",
  targetProjectName="{new_name}",
  projectType="{MVC|WebAPI}"
)
```

If the tool is not available or fails, proceed with Step 2.

## Step 2: Scaffold Using Script + Templates

This skill includes template files and a PowerShell script that handles the mechanical work.
The LLM handles the parts that need judgment (finding the old app URL, resolving package versions).

### 2.1 Gather Parameters

**All parameters are mandatory.** The new project will not work correctly with the
old project unless every value is accurate. Do not use defaults without verifying them.

Before running the script, determine these values:

| Parameter | How to find it |
|-----------|---------------|
| `OldProjectPath` | Full path to the .NET Framework .csproj |
| `SolutionPath` | Full path to the .sln/.slnx file |
| `TargetFramework` | TFM of the **new proxy project**, not of the app being migrated. **Use `net10.0` or later** — the hardened templates use `ForwardedHeadersOptions.KnownIPNetworks`, which does not exist before ASP.NET Core 10. Below net10.0 the script still scaffolds, but strips the hardening and warns. A .NET Framework moniker (`net48`, `net472`, …) is rejected: the proxy host must be ASP.NET Core. See **Production hardening**. |
| `NewProjectName` | Name for new project (default: `{OldName}.Core`). Must be unique in the solution — check existing project names and folder names |
| `ProjectType` | `MVC` or `WebAPI` — match the old project's type |
| `OldAppUrl` | **Must be the actual URL the old app runs on.** Find it in the old project's `Properties/launchSettings.json` (look for `applicationUrl` in the active profile), or in IIS/IIS Express bindings. Do NOT guess — if the proxy points to the wrong URL, all forwarded requests will fail silently. |
| `SystemWebAdaptersVersion` | Use `get_supported_package_version` for `Microsoft.AspNetCore.SystemWebAdapters.CoreServices` |
| `YarpVersion` | Use `get_supported_package_version` for `Yarp.ReverseProxy` |

**NewProjectName validation:**
- Must not match any existing project name in the solution
- The folder `{parent_of_old_project}/{NewProjectName}` must not already exist
- The script checks both conditions and fails with a clear error if violated
- The new project folder is always created as a **sibling** to the old project's folder

### 2.2 Run the Script

The script copies template files from `tmpl/mvc/` or `tmpl/webapi/`, applies
variable substitutions (`$TargetFramework$`, `$ProjectName$`, `$OldAppUrl$`, etc.),
adds the project to the solution, links the old project via `_MigrateToProjectGuid`,
and verifies the build.

```powershell
{skill_path}/scaffold-project.ps1 `
  -OldProjectPath "{OLD_PROJECT_PATH}" `
  -SolutionPath "{SOLUTION_PATH}" `
  -TargetFramework "{TFM}" `
  -NewProjectName "{NEW_PROJECT_NAME}" `
  -ProjectType "{MVC|WebAPI}" `
  -OldAppUrl "{OLD_APP_URL}" `
  -SystemWebAdaptersVersion "{VERSION}" `
  -YarpVersion "{VERSION}"
```

To trust real proxy addresses at scaffold time (instead of the fail-closed loopback
defaults), also pass `-TrustedProxies` and/or `-TrustedNetworks`. To let the proxy set the
request host, pass `-AllowedForwardedHosts` — without it, `X-Forwarded-Host` is ignored
(see the spoofing footgun under **Production hardening**). These write the
`ForwardedHeaders` section of the generated `appsettings.json`:

```powershell
  -TrustedProxies "10.0.0.5","10.0.0.6" `
  -TrustedNetworks "10.0.0.0/8","::1/128" `
  -AllowedForwardedHosts "www.example.com"
```

When omitted, the template keeps its secure defaults — loopback-only trust, and no
forwarded host honored — and an operator opts in later by editing `appsettings.json`.

### 2.3 If Script Fails or Is Unavailable

If the script cannot be executed (e.g., PowerShell not available, permissions issue),
do the steps manually. The template files in `tmpl/mvc/` and `tmpl/webapi/`
contain the exact file contents — copy them to the new project folder and replace
the `$placeholder$` variables:

| Placeholder | Replace with |
|-------------|-------------|
| `$TargetFramework$` | Target framework — **use `net10.0` or later**; a hand-copy below that does not compile (see below) |
| `$SystemWebAdaptersVersion$` | Package version from `get_supported_package_version` |
| `$YarpVersion$` | Package version from `get_supported_package_version` |
| `$ProjectName$` | New project name |
| `$HttpsPort$` | HTTPS port (pick 7100-7999, avoid old project's ports) |
| `$HttpPort$` | HTTP port (pick 5100-5999, avoid old project's ports) |
| `$NewPort$` | IIS Express HTTP port (pick 60000-65000) |
| `$NewSslPort$` | IIS Express SSL port (pick 44300-44399) — in `launchSettings.json` this placeholder is quoted (`"sslPort": "$NewSslPort$"`) so the template stays valid JSON; after substituting, remove the surrounding quotes so `sslPort` stays a JSON number, e.g. `"sslPort": 44355` |
| `$OldAppUrl$` | Old app's URL (e.g., `https://localhost:44319`) |

Then manually:
1. Delete the `//<hardening>` and `//</hardening>` marker comment lines from `Program.cs` (they delimit the hardening blocks for the script; the code between them is kept)
2. Rename `ProjectName.csproj` to `{NewProjectName}.csproj`
3. Run `dotnet sln "{SOLUTION_PATH}" add "{NEW_PROJECT_PATH}"`
4. Find the new project's GUID in the solution file
5. Add `<_MigrateToProjectGuid>{GUID}</_MigrateToProjectGuid>` to the old project's .csproj
6. Run `dotnet build` to verify

The `appsettings.json` template already contains a valid, fail-closed `ForwardedHeaders`
section (no placeholders), so a manual copy stays valid JSON. To trust real proxies, edit
`ForwardedHeaders:TrustedProxies` / `ForwardedHeaders:TrustedNetworks` directly; to let the
proxy set the host, populate `ForwardedHeaders:AllowedHosts`. See **Production hardening**.

> **Manual path has no automatic TFM check.** `scaffold-project.ps1` strips the hardening
> below net10.0, but a hand-copy has nothing enforcing that. `tmpl/*/Program.cs` uses
> `ForwardedHeadersOptions.KnownIPNetworks`, so copying it into a project targeting
> net8.0/net9.0 compiles to **CS1061**. Before copying, confirm `$TargetFramework$` is
> `net10.0` or later; if it cannot be, follow **Targeting below net10.0** under
> **Production hardening**.
>
> Also strip the `//<hardening>` / `//</hardening>` marker comments — the script removes
> them automatically, but a hand-copy carries them into the generated source.

### Template Files Reference

```
tmpl/
  mvc/                         ← For MVC projects
    ProjectName.csproj         ← SDK-style web project with YARP + SystemWebAdapters packages
    Program.cs                 ← AddControllersWithViews + YARP forwarder + hardening (forwarded headers, Kestrel TLS, response scrubbing, UseAuthentication)
    appsettings.json           ← ProxyTo + fail-closed ForwardedHeaders section
    appsettings.Development.json ← logging overrides (inherits the base ForwardedHeaders section)
    Properties/
      launchSettings.json      ← ProxyTo in environmentVariables
  webapi/                      ← For WebAPI projects
    ProjectName.csproj         ← Same packages, no Swashbuckle
    Program.cs                 ← AddControllers + YARP forwarder + hardening (no UseStaticFiles)
    appsettings.json           ← ProxyTo + fail-closed ForwardedHeaders section
    appsettings.Development.json ← logging overrides (inherits the base ForwardedHeaders section)
    Properties/
      launchSettings.json
```

Both `Program.cs` templates delimit each hardening block with `//<hardening>` /
`//</hardening>` comment markers. `scaffold-project.ps1` removes the marker lines on
net10.0+ and removes the markers *and the enclosed code* below net10.0. Keep the markers
balanced when editing the templates — the script throws on an unbalanced pair rather than
emitting malformed source.

Key things the templates set up:
- `builder.WebHost.ConfigureKestrel(...)` — security policy (server header off, TLS 1.2/1.3)
- `builder.Services.Configure<ForwardedHeadersOptions>(...)` — fail-closed forwarded headers (non-obsolete API)
- `builder.Services.AddAuthentication()` — parameterless seam so `UseAuthentication()` cannot crash at runtime
- `builder.Services.AddSystemWebAdapters()` — System.Web compatibility shims
- `builder.Services.AddHttpForwarder()` — YARP forwarder registration
- `app.UseForwardedHeaders()` — **first** middleware; recovers client scheme/host/IP
- `app.Use(...)` response scrubber — strips the backend's `Server` / `X-Powered-By` / `X-AspNet-Version` / `X-AspNetMvc-Version` headers
- `app.UseAuthentication()` — runs immediately **before** `app.UseAuthorization()`
- `app.UseSystemWebAdapters()` — middleware for adapter support
- `app.MapForwarder("/{**catch-all}", ...)` — catch-all route at lowest priority, forwards unmatched requests to old app

The `appsettings.json` templates also ship a fail-closed `ForwardedHeaders` section
(`TrustedProxies: []`, `TrustedNetworks: [ "127.0.0.1/32", "::1/128" ]`, `AllowedHosts: []`)
that the code above binds. See **Production hardening**.

## Production hardening (required)

The scaffold is not just a forwarder — it is the security boundary between the internet
and the still-running Framework app. The templates emit the following hardening, and it
is a required acceptance criterion (do not remove it):

**1. Forwarded headers (fail-closed).** When the scaffold itself runs behind an edge proxy
or load balancer, it must recover the client's original scheme, host, and IP —
`X-Forwarded-For`, `-Host`, and `-Proto`, and deliberately **not** `X-Forwarded-Prefix`.
`Configure<ForwardedHeadersOptions>` binds the `ForwardedHeaders` config section and trusts
**only** the proxies/networks listed there (loopback-only by default). Operators add their
real proxy addresses via `-TrustedProxies` / `-TrustedNetworks` at scaffold time, or by
editing `appsettings.json`; `-AllowedForwardedHosts` (`ForwardedHeaders:AllowedHosts`)
separately opts in to honoring `X-Forwarded-Host`. This fixes the **Core** side only; the
Framework app behind the forwarder needs the separate module described in
**Framework-side companion** below.

> **Footgun — `ForwardedHeaders.All` includes `X-Forwarded-Prefix`, which cannot be
> allow-listed.** The templates enumerate the three headers they want rather than using
> `All`, because `All` also enables `XForwardedPrefix`. That header overwrites
> `Request.PathBase`, and the middleware has **no `AllowedHosts` equivalent for it** — it
> applies whatever arrives. Verified with the template's own configuration: a request
> carrying `X-Forwarded-Prefix: /evil` moved every generated link from
> `http://host/target` to `http://host/evil/target`, while the same request's spoofed
> `X-Forwarded-Host` was correctly ignored. Since the header is trusted on the basis of the
> *peer's* IP, the real proxy relaying a client's value is enough to trigger it. Only enable
> the flag if the app is genuinely hosted under a sub-path, and strip any client-supplied
> `X-Forwarded-Prefix` at the edge first.

> **Footgun — never leave both trust lists empty.** If `KnownProxies` **and**
> `KnownIPNetworks` both end up empty, `ForwardedHeadersMiddleware` skips its source check
> and honors `X-Forwarded-*` from **any** sender (fail-*open*, an IP-spoofing risk) — the
> opposite of "fail-closed." The template guards against this: after binding config it
> re-adds loopback (`127.0.0.1/32`, `::1/128`) when both lists are empty. Preserve that
> guard, and if you clear the loopback defaults in `appsettings.json` be sure to add at
> least one real `TrustedProxies`/`TrustedNetworks` entry — do not ship both arrays empty.

> **Footgun — `X-Forwarded-Host` is a spoofing vector, and its allow-list defaults to
> "allow everything."** `ForwardedHeadersOptions.AllowedHosts` starts empty, and an empty
> list means the middleware accepts **any** forwarded host — which lets a caller control the
> host in links, redirects, and absolute URLs the app generates. Trusting the proxy's *IP*
> does not help here: most load balancers pass a client-supplied `X-Forwarded-Host` straight
> through, so the header arrives from a trusted sender carrying untrusted content. The
> template is fail-closed instead: it binds `ForwardedHeaders:AllowedHosts`, and when that
> list is empty it **clears the `XForwardedHost` flag** so the host is never taken from an
> unvalidated header. Populate `AllowedHosts` with the public hostname(s) the proxy serves
> (e.g. `[ "www.example.com" ]`) to turn host forwarding on. `*.example.com` is accepted for
> a subdomain wildcard; `"*"` is accepted by the framework but **re-opens the exact spoofing
> hole this guard exists to close** — never ship it. Note this is a **different setting**
> from the top-level `AllowedHosts: "*"` in `appsettings.json`, which configures host
> *filtering* — nesting matters. Narrow that one too: it is the check that rejects a forged
> `Host` with a 400 before the request is ever forwarded.

**2. Kestrel security policy.** `ConfigureKestrel` disables the `Server` response header,
applies a TLS 1.2 floor, and binds `Kestrel:Limits:MaxRequestBodySize` from configuration so the
cap can be sized without editing code.

> **The TLS floor is a default, not a hard-coded pin — it is overridable via
> `Kestrel:SslProtocols`.** Kestrel's own default is `SslProtocols.None`, meaning "use the OS
> default", and Microsoft's guidance is to prefer it *unless you have a specific reason*. This
> scaffold has one: it generates the **internet-facing edge** for a legacy app, and Windows
> Server 2016–2022 still enable TLS 1.0/1.1 in their default SCHANNEL configuration, so `None`
> would leave a modernized deployment accepting protocols the migration was meant to retire.
> The floor only ever **narrows** what the OS permits — a protocol disabled machine-wide in
> SCHANNEL (`Enabled=0`) cannot be re-enabled from application code — so it cannot weaken
> machine policy. Set `Kestrel:SslProtocols` to adopt a newer protocol as it ships (`"Tls13"`),
> to combine values (`"Tls12, Tls13"`), or to defer entirely to the OS (`"None"`) — none of
> which requires editing generated code. Disabling legacy protocols **at the OS level** is
> still preferable where you control the host, since it covers every app on the machine. An
> unrecognized value fails fast at startup rather than silently falling back.

> **`ForwardedHeaders:ForwardLimit` must never be set to a negative number.** The scaffold maps
> negatives to `null` ("unlimited") for exactly this reason. Assigning a negative value directly
> makes `ForwardedHeadersMiddleware` allocate an array of that length and throw
> `OverflowException` on **every** request — including requests carrying no `X-Forwarded-*`
> headers at all — so a single `appsettings.json` typo takes the whole proxy down with a stack
> trace pointing into framework code. `0` is harmless; only negatives are fatal.

> **Kestrel does *not* auto-bind its `Limits` from the `Kestrel` configuration section, so
> the scaffold binds the request-size cap explicitly.** Only endpoints, certificates, and a
> few top-level switches are bound from that section — a bare
> `Kestrel:Limits:MaxRequestBodySize` in `appsettings.json` is otherwise **silently ignored**
> ([dotnet/aspnetcore#37544](https://github.com/dotnet/aspnetcore/issues/37544)). Do not
> "simplify" the explicit binding away: an operator who caps request size and gets no error
> would reasonably believe the cap is in force when it is not. Other `Limits.*` values
> (`MaxRequestBufferSize`, `RequestHeadersTimeout`, the data-rate limits) are **not** bound by
> the scaffold and must be set in `ConfigureKestrel` in code.

> **The scaffold does not remove Kestrel's default request-size cap, and that default is
> itself a limit.** `MaxRequestBodySize` defaults to **30,000,000 bytes (~28.6 MiB)**, so a
> proxy that forwards larger uploads (e.g. a `.nupkg` push) returns **413** until the
> operator raises it. Raise it deliberately via `Kestrel:Limits:MaxRequestBodySize` in
> `appsettings.json` (a **negative** value removes the limit) — do not assume the
> unconfigured default is permissive. On the Framework side the equivalent knob is IIS
> `<requestLimits maxAllowedContentLength>`, which has its own separate default.

> **`AddServerHeader = false` only suppresses the *proxy's own* `Server` header — the scaffold
> adds a response-scrubbing middleware to cover the backend's.** YARP copies forwarded response
> headers through untouched, so without the scrubber a Framework backend keeps advertising
> `Server: Microsoft-IIS/10.0`, `X-Powered-By: ASP.NET`, `X-AspNet-Version`, and
> `X-AspNetMvc-Version` to clients — a free fingerprint of the exact stack you are trying to put
> a boundary in front of. The emitted `app.Use(...)` block strips that set on the way out. Add
> any other header your backend exposes to the list; it is an ordinary allow-by-omission list,
> so unrelated headers pass through untouched. The callback is deliberately `static` and takes
> the response as `OnStarting` state so it is allocated once rather than per request.

> **HSTS is in the MVC template but not the WebAPI one — that asymmetry is inherited, not an
> oversight.** The templates mirror `dotnet new mvc` (which emits
> `if (!app.Environment.IsDevelopment()) { app.UseHsts(); }`) and `dotnet new webapi` (which
> does not). Do not "even them up" reflexively. HSTS is a **browser-only** control, so a
> WebAPI whose callers are services gains nothing from it, and the header is **sticky**:
> ASP.NET Core sends a 30-day `max-age` that browsers cache and honor even after you remove
> it, which can strand an API that still has HTTP callers or plain-HTTP subdomains. Add
> `app.UseHsts()` to the WebAPI proxy when it genuinely serves browsers over a hostname you
> control end-to-end, and treat it as a deployment decision with a rollback cost — not as a
> default.

**3. Backend response-header scrubbing.** An `app.Use(...)` middleware strips the stack
fingerprint the proxied app returns (`Server`, `X-Powered-By`, `X-AspNet-Version`,
`X-AspNetMvc-Version`) so the proxy does not advertise what it fronts. See the blockquote
above for why `AddServerHeader = false` alone is not enough.

**4. Authentication seam before authorization.** `app.UseAuthentication()` runs
immediately before `app.UseAuthorization()`, and `builder.Services.AddAuthentication()`
is registered so `UseAuthentication()` does not throw at the first request. This call is
**intentionally parameterless**: the scaffold cannot know which scheme the app needs, so
it registers the authentication services and leaves the scheme to whoever configures
authentication. `dotnet build` does **not** catch a missing `AddAuthentication()` — the
failure only surfaces at runtime — which is why the seam is baked into the template.

### Configuration check — do NOT use the obsolete forwarded-headers API

On `net10.0`+ (the target this scaffold requires) use the **non-obsolete** pattern only:

| Use (non-obsolete on net10.0+) | Do NOT use (ASPDEPR005 / BC000660) |
|--------------------|------------------------------------|
| `ForwardedHeadersOptions.KnownIPNetworks` | `ForwardedHeadersOptions.KnownNetworks` |
| `System.Net.IPNetwork` | `Microsoft.AspNetCore.HttpOverrides.IPNetwork` |

The plugin's own API catalog flags the obsolete members as **BC000660** at
code-assessment time, so a project that hand-rolls the old pattern will surface the
warning; the templates above already use the correct API.

The right-hand column is obsolete **only on net10.0+** — that is where the deprecation
landed. On net8.0/net9.0 those same members are the correct API and `KnownIPNetworks` does
not exist at all; see **Targeting below net10.0** below.

> **Requires ASP.NET Core 10.0+.** `ForwardedHeadersOptions.KnownIPNetworks` only exists
> in ASP.NET Core 10.0 and later (`System.Net.IPNetwork` is net8.0+, but the property is
> net10.0+). Scaffold the proxy against `net10.0` or newer.

#### Targeting below net10.0

Only the **forwarded-headers** block needs net10. The Kestrel security policy, the response
header scrubber, and the authentication seam compile on net8.0/net9.0 unchanged — but the
script strips all of them together, because a proxy carrying only the low-value items is not a
security boundary and should not look like one. The three scaffold paths behave differently
below net10.0, so know which one you are on:

| Path | Behavior below net10.0 |
|------|------------------------|
| `scaffold-project.ps1` | Scaffolds a working **unhardened** proxy and emits a prominent warning. `appsettings.json` is written *without* the `ForwardedHeaders` section, so no configuration surface implies protection that isn't there. Passing `-TrustedProxies`/`-TrustedNetworks`/`-AllowedForwardedHosts` is a **hard error** — that trust cannot be honored. |
| VS Roslyn transformer | Scaffolds a working **unhardened** proxy and logs a warning. |
| Manual copy (2.3) | **No check** — copying the template verbatim yields **CS1061** at build. |

Preferred fix: raise the target to `net10.0`, which is where the rest of this guidance is
aimed. If the target genuinely cannot move (hosting or policy constraint), scaffold
manually and adapt the forwarded-headers block — `KnownIPNetworks` becomes `KnownNetworks`,
which on net8/net9 takes `Microsoft.AspNetCore.HttpOverrides.IPNetwork`. That type has no
`TryParse`, so parse with `System.Net.IPNetwork` (net8.0+) and convert:

```csharp
// net8.0 / net9.0 equivalent — KnownNetworks is NOT obsolete on these versions.
if (System.Net.IPNetwork.TryParse(network, out var parsed))
{
    options.KnownNetworks.Add(
        new Microsoft.AspNetCore.HttpOverrides.IPNetwork(parsed.BaseAddress, parsed.PrefixLength));
}
```

Apply the same substitution to the loopback fallback. Keep every other hardening item
as-is — including the `AllowedHosts` allow-list and its `XForwardedHost` fail-closed guard,
which need no adaptation (`AllowedHosts` has existed since ASP.NET Core 2.x). Do **not**
carry this variant into a net10.0+ project — there `KnownNetworks` and
`Microsoft.AspNetCore.HttpOverrides.IPNetwork` are the obsolete pair flagged above.

### Framework-side companion (required for correct scheme/host/IP)

`app.UseForwardedHeaders()` fixes the **Core** side. The **Framework** side does not read
`X-Forwarded-*` — `HttpRequest.IsSecureConnection`, `Url.Host`, and `UserHostAddress` are
read-only projections of `Request.ServerVariables`, so a doc snippet cannot simply "trust"
them. Rewrite the underlying server variables in an `IHttpModule`, **gated on the proxy's
IP**, before any application code runs:

> **Requires the IIS *Integrated* pipeline.** `HttpServerVarsCollection.Set` throws
> `PlatformNotSupportedException` unless the request is served by an IIS 7+ integrated-mode
> worker; in Classic mode the collection is read-only. Under Integrated mode the write is
> propagated to IIS and the matching `HTTP_*` request header is kept in sync. Do not reach
> for reflection to force a write in Classic mode — that mutates only ASP.NET's managed copy,
> leaving IIS and the header collection disagreeing with it.

> **Trusting the proxy's IP is not enough for `X-Forwarded-Host`.** The proxy sets that
> header from the client's `Host`, so it arrives from a trusted sender carrying
> attacker-controlled content. The module below therefore applies the **same fail-closed
> allow-list the Core side uses**: an empty `AllowedHosts` means the host is never
> rewritten. Without that check, a request with `Host: evil.example` reaches the Framework
> app as `HTTP_HOST: evil.example`, poisoning password-reset links, absolute redirects, and
> anything else built from the request host. Also narrow the **top-level** `AllowedHosts` in
> the proxy's `appsettings.json` (it ships as `"*"`, which accepts any `Host`); setting it to
> the real public hostname(s) makes the proxy reject a forged `Host` with a 400 before it is
> ever forwarded.

> **`AllowedHosts` in this module takes exact hostnames only — no wildcards, and no ports.**
> The two sides deliberately match the same way on ports: Core's check (`HostString.MatchesAny`)
> ignores the port, so the module strips it before comparing. Keep the entries port-free on both
> sides. The sides do **not** agree on wildcards: Core additionally accepts `*` and subdomain
> patterns like `*.example.com`, which this snippet does not implement — list each hostname
> explicitly here, or the Framework app will silently keep rendering internal-host links while
> the Core app honors the forwarded value.

```csharp
public sealed class ForwardedHeadersModule : IHttpModule
{
    // Populate from configuration; never trust every caller.
    private static readonly string[] TrustedProxies = { "127.0.0.1", "::1" };

    // Public hostname(s) this app is served as. EMPTY = never rewrite the host
    // (fail closed), mirroring ForwardedHeadersOptions.AllowedHosts on the Core side.
    private static readonly string[] AllowedHosts = { };

    public void Init(HttpApplication context) => context.BeginRequest += OnBeginRequest;

    private static void OnBeginRequest(object sender, EventArgs e)
    {
        var request = ((HttpApplication)sender).Context.Request;
        var vars = request.ServerVariables;

        // Only honor forwarded headers when the immediate peer is a trusted proxy.
        if (Array.IndexOf(TrustedProxies, request.UserHostAddress) < 0)
        {
            return;
        }

        var proto = vars["HTTP_X_FORWARDED_PROTO"];
        if (!string.IsNullOrEmpty(proto))
        {
            vars.Set("HTTPS", proto.Equals("https", StringComparison.OrdinalIgnoreCase) ? "on" : "off");
            vars.Set("SERVER_PORT_SECURE", proto.Equals("https", StringComparison.OrdinalIgnoreCase) ? "1" : "0");
        }

        // Fail closed: only rewrite the host when the forwarded value is allow-listed.
        // Match on the host *without* its port. The Core side's AllowedHosts check ignores the
        // port (HostString.MatchesAny), so comparing the raw header here would reject
        // "www.example.com:8443" against an allow-list entry of "www.example.com" and leave the
        // two apps behaving differently from one identical config value.
        var host = vars["HTTP_X_FORWARDED_HOST"];
        if (!string.IsNullOrEmpty(host))
        {
            // Strip the port. Bracketed IPv6 literals ("[::1]:8080") keep their brackets,
            // so only split on the last colon when it is not inside the brackets.
            var portIndex = host.LastIndexOf(':');
            var closingBracket = host.LastIndexOf(']');
            var hostWithoutPort = portIndex > closingBracket ? host.Substring(0, portIndex) : host;

            if (Array.FindIndex(AllowedHosts, h => string.Equals(h, hostWithoutPort, StringComparison.OrdinalIgnoreCase)) >= 0)
            {
                vars.Set("HTTP_HOST", host);
                vars.Set("SERVER_NAME", hostWithoutPort);
            }
        }

        var forwardedFor = vars["HTTP_X_FORWARDED_FOR"];
        if (!string.IsNullOrEmpty(forwardedFor))
        {
            // The proxy *sets* (does not append) this header, so it holds a single address:
            // the client as the proxy resolved it. If you ever put another hop in front that
            // appends, the left-most entry becomes caller-controlled — take the right-most
            // entry contributed by a trusted hop instead.
            vars.Set("REMOTE_ADDR", forwardedFor.Split(',')[0].Trim());
        }
    }

    public void Dispose() { }
}
```

Register it in `web.config` under `<system.webServer><modules>`. Note: this only affects
the server variables above; cookie `Secure` behavior is unaffected because the ASP.NET
runtime derives it from the (now corrected) `HTTPS` variable.


## Success Criteria

- [ ] New project folder created as sibling to old project folder
- [ ] .csproj TFM is `net10.0` or later, with correct package references (latest versions)
- [ ] Program.cs has YARP forwarder and SystemWebAdapters registration
- [ ] Program.cs configures forwarded headers via the TFM-appropriate API (`KnownIPNetworks` + `System.Net.IPNetwork` on net10.0+), with `UseForwardedHeaders()` as the first middleware
- [ ] Program.cs calls `AddAuthentication()` and runs `UseAuthentication()` immediately before `UseAuthorization()`
- [ ] Program.cs sets the Kestrel security policy (server header off, TLS 1.2/1.3)
- [ ] Program.cs strips the backend's stack-fingerprint response headers (`Server`, `X-Powered-By`, `X-AspNet-Version`, `X-AspNetMvc-Version`)
- [ ] appsettings.json has `ProxyTo` key and a fail-closed `ForwardedHeaders` section (empty `TrustedProxies`, loopback `TrustedNetworks`, empty `AllowedHosts`)
- [ ] launchSettings.json has `ProxyTo` pointing to the **verified** old app URL
- [ ] Framework-side `X-Forwarded-*` companion (IHttpModule rewriting server variables, gated on trusted proxy IPs) is in place when the Framework app relies on scheme/host/IP
- [ ] New project added to solution
- [ ] Old project has `_MigrateToProjectGuid` property pointing to new project
- [ ] New project builds with 0 errors

## Troubleshooting

If the scaffolded project doesn't work, tell the user to check:

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| Proxy returns 502/connection refused | `ProxyTo` URL is wrong or old app isn't running | Verify URL in `launchSettings.json` matches old app's actual URL; start old app first |
| New project won't build | Wrong TFM or package versions | Check `TargetFramework` matches installed SDK; verify package versions are compatible |
| `CS1061 'ForwardedHeadersOptions' does not contain 'KnownIPNetworks'` | Scaffolded below net10.0 | Re-scaffold with `-TargetFramework net10.0` or newer — `KnownIPNetworks` requires ASP.NET Core 10+ |
| Requests not forwarded | YARP middleware not registered | Check `Program.cs` has `AddHttpForwarder()` and `MapForwarder()` |
| Controllers return 404 | Routes not configured | Ensure `MapDefaultControllerRoute()` (MVC) or `MapControllers()` (WebAPI) is in `Program.cs` |
| Framework app sees `http`/proxy IP instead of client scheme/IP | Forwarded headers not honored on one side | Confirm `UseForwardedHeaders()` is the first middleware on the Core side **and** the Framework-side IHttpModule rewrites server variables (see **Production hardening**); verify the proxy's IP is in `TrustedProxies`/`TrustedNetworks` |
| Redirect loop or wrong scheme | Real proxy IP not trusted, so headers are ignored | Add the proxy address to `ForwardedHeaders:TrustedProxies`/`TrustedNetworks` in `appsettings.json` |
| Links/redirects use the internal host instead of the public one | `X-Forwarded-Host` is ignored because `ForwardedHeaders:AllowedHosts` is empty (fail-closed by design) | Add the public hostname(s) to `ForwardedHeaders:AllowedHosts`, or re-scaffold with `-AllowedForwardedHosts` |
| `_MigrateToProjectGuid` missing | Script couldn't find GUID in solution | Manually find the project GUID in .sln/.slnx and add the property to old .csproj |
