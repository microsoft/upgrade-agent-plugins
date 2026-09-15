---
name: scaffolding-yarp-proxy-project
description: >
  Scaffolds a new ASP.NET Core project with YARP reverse proxy alongside an existing
  .NET Framework MVC or WebAPI project for incremental side-by-side migration. Use when
  a migration task requires creating a new Core project that proxies to the old Framework
  app, when the side-by-side migration approach is selected, or when scaffold/YARP/proxy
  setup is needed. Also handles authentication interop between the two apps (shared cookie
  or remote authentication) so users stay signed in across both. Also triggers for "create
  new Core project", "set up YARP proxy", "side-by-side project setup", "share login between
  old and new app", "user appears signed out after migration".
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
| 1 | Choose the scaffolding path | VS uses the tool; every other host uses the script |
| 2 | Scaffold Using Script + Templates | Primary path — script + template files |
| 2.1 | Gather Parameters | Paths, TFM, URLs, package versions, auth interop switches |
| 2.2 | Run the Script | Script copies templates, adds to solution, links projects |
| 2.3 | Manual Scaffolding | Script fallback or older targets — copy templates, replace placeholders (**[ref/manual-scaffold.md](ref/manual-scaffold.md)**) |
| - | Authentication interop | Keeping users signed in across both apps; parameters and footguns in **[ref/auth-setup.md](ref/auth-setup.md)** |
| - | Production hardening | **Required** — forwarded headers, TLS, `UseAuthentication`; Framework-side companion in **[ref/framework-headers.md](ref/framework-headers.md)** |
| - | Success Criteria | Final checklist |

**Do not stop reading after Step 1.** Step 1 only selects the host-appropriate mechanism; the parameters,
the auth and hardening detail, and the manual fallback live in Step 2, the sections below, and the linked
`ref/` files.

## Prerequisites

Before using this skill, you need:
- Path to the **old .NET Framework web project** (.csproj)
- Path to the **solution file** (.sln or .slnx) containing it
- **Target framework** for the new project (e.g., `net10.0`)
- **Project type**: MVC or WebAPI
- **New project name** (default: `{OldProjectName}.Core`)

## Step 1: Choose the scaffolding path for this host

Which mechanism is available depends on **where you are running**, and the split is
structural rather than a fallback:

- **Visual Studio.** The `scaffold_yarp_proxy_web_project` tool is available. It handles
  the mechanical work automatically:

  ```
  scaffold_yarp_proxy_web_project(
    solutionPath="{solution_path}",
    projectPath="{old_project_path}",
    targetFramework="{tfm}",
    targetProjectName="{new_name}",
    projectType="{MVC|WebAPI}",
    authInterop="{none|sharedcookie|remoteauth}",
    sharedKeyRingProvider="{filesystem|azureblob}"
  )
  ```

  `authInterop` selects which authentication interop path to pre-wire, and defaults to
  `none`. Ask the user which they need before calling — see **Authentication interop**
  below for how to choose. `sharedKeyRingProvider` applies only to `sharedcookie`, and is
  rejected with any other mode; it selects where the shared Data Protection key ring lives
  and therefore which `SharedDP:*` keys are emitted. Two limits are specific to this path:

  - **`sharedcookie` and `remoteauth` require `targetFramework` net10.0 or later.** The
  tool rejects the combination up front rather than scaffolding a project with the
    parameter silently dropped. Below net10.0, scaffold with `none` and wire the interop by
    hand per **Authentication interop**.
  - **The tool writes the configuration keys blank.** It has no way to ask for the cookie
    name, key ring location, certificate thumbprint, or API key, so it emits the keys in
    `appsettings.json` for the user to fill in. Every blank value fails loudly rather than
    appearing to work, but *when* it fails differs by mode: `sharedcookie` values are read
    eagerly while the host is built, so a blank one throws at startup; `remoteauth` values sit
    inside a deferred options callback, so a blank one throws on the first request the proxy
    authenticates and the host starts clean until then. Tell the user which keys they must fill
    in — for `sharedcookie` that set depends on `sharedKeyRingProvider`.
    `scaffold-project.ps1` takes the values directly and is the better path when you have
    them.

- **Everywhere else (CLI, Copilot Chat outside VS).** The tool is not registered in this
  host, so **go to Step 2** and use `scaffold-project.ps1`. Do not probe for the tool
  first: it depends on Visual Studio services that only exist inside the VS process, so
  calling it here cannot succeed. If it is somehow reachable, its failure message names the
  host as the likely cause and points back here.

`scaffold-project.ps1` is the more capable path — it takes the interop values directly, it
validates them, and it is not limited to net10.0.

## Step 2: Scaffold Using Script + Templates

This skill includes template files and a PowerShell script that handles the mechanical work.
The LLM handles the parts that need judgment (finding the old app URL, resolving package versions).

### 2.1 Gather Parameters

**Every parameter in the table below is mandatory.** The new project will not work correctly
with the old project unless every value is accurate. Do not use defaults without verifying
them. (The authentication interop parameters described after the table are optional as a
group — but once you turn one on, all of its companions are required.)

Before running the script, determine these values:

| Parameter | How to find it |
|-----------|---------------|
| `OldProjectPath` | Full path to the .NET Framework .csproj |
| `SolutionPath` | Full path to the .sln/.slnx file |
| `TargetFramework` | TFM of the **new proxy project**, not of the app being migrated. **Use `net10.0` or later** — the hardened templates use `ForwardedHeadersOptions.KnownIPNetworks`, which does not exist before ASP.NET Core 10. Below net10.0 the script still scaffolds, but strips the hardening and warns. A .NET Framework moniker (`net48`, `net472`, …) is rejected: the proxy host must be ASP.NET Core. See **Production hardening**. |
| `NewProjectName` | Name for new project (default: `{OldName}.Core`). Must be unique in the solution — check existing project names and folder names |
| `ProjectType` | `MVC` or `WebAPI` — match the old project's type |
| `OldAppUrl` | **Must be the actual URL the old app runs on.** Find it in the old project's `Properties/launchSettings.json` (look for `applicationUrl` in the active profile), or in IIS/IIS Express bindings. Do NOT guess — if the proxy points to the wrong URL, all forwarded requests will fail silently. |
| `SystemWebAdaptersVersion` | Use `get_supported_package_version` for `Microsoft.AspNetCore.SystemWebAdapters.CoreServices`. **With `-EnableRemoteAuth`, this must be `2.3.0` or newer** — see **[ref/auth-setup.md](ref/auth-setup.md)**. |
| `YarpVersion` | Use `get_supported_package_version` for `Yarp.ReverseProxy` |

**NewProjectName validation:**
- Must not match any existing project name in the solution
- The folder `{parent_of_old_project}/{NewProjectName}` must not already exist
- The script checks both conditions and fails with a clear error if violated
- The new project folder is always created as a **sibling** to the old project's folder

**Forwarded-headers parameters (optional, and net10.0+ only).** The templates ship fail-closed —
`TrustedProxies` and `AllowedHosts` empty, `TrustedNetworks` loopback-only — so the scaffold is safe
before anyone configures it and useless behind a real proxy until someone does. These set that trust
at scaffold time instead of by hand-editing `appsettings.json` afterwards. Below net10.0 the
hardening is stripped, so passing any of them is a **hard error** rather than a silent no-op: the
trust could not be honoured. See **Production hardening** for the full picture.

| Parameter | How to find it |
|-----------|---------------|
| `-TrustedProxies` | Addresses of the real reverse proxies/load balancers in front of this app. Ship at least one of this or `-TrustedNetworks` in production — both empty means forwarded headers are ignored and the app sees the proxy's IP as the client. |
| `-TrustedNetworks` | CIDR ranges to trust instead of individual addresses, e.g. `10.0.0.0/8`. |
| `-AllowedForwardedHosts` | Public hostname(s) the proxy may set via `X-Forwarded-Host`. Empty means the header is ignored, which shows up as links and redirects using the internal host. |

`-SkipBuild` generates the files without running `dotnet build`. It is not TFM-gated.

**Authentication interop parameters (optional, off by default).** To keep users signed in across both
apps, pre-wire exactly one mutually-exclusive path — `-EnableSharedCookieAuth` or `-EnableRemoteAuth`.
Every companion parameter, its preconditions, the supported key-ring topologies, and the ready-to-paste
invocation groups are in **[ref/auth-setup.md](ref/auth-setup.md)** — read it before passing any
auth-interop parameter. Which path suits the app is decided in **Authentication interop** below.

### 2.2 Run the Script

The script copies template files from `tmpl/mvc/` or `tmpl/webapi/`, applies
variable substitutions (`$TargetFramework$`, `$ProjectName$`, `$OldAppUrl$`, etc.),
adds the project to the solution, links the old project via `_MigrateToProjectGuid`,
and verifies the build.

> **Invoke PowerShell explicitly, on one line, with `-Command` and the call operator.** The
> `execute` tool runs in the *user's* shell, which is often Git Bash or WSL rather than
> PowerShell. Running the `.ps1` by bare path only works if the shell happens to be
> PowerShell, and a PowerShell backtick continuation is **command substitution** in bash: an
> odd number of trailing backticks aborts with `unexpected EOF while looking for matching`,
> and an even number pairs up so the parameters run as commands, the script never runs, and
> the shell still **exits 0**. Never split this command across lines with backticks. Use
> `pwsh` instead of `powershell` on non-Windows hosts.
>
> **Use `-Command "& '<script>' …"`, not `-File`.** `-File` passes arguments as native
> strings, so an array parameter never receives more than one element: `-TrustedProxies
> "10.0.0.5","10.0.0.6"` binds as the single value `10.0.0.5,10.0.0.6`, the script writes one
> invalid address, and the generated `Program.cs` silently falls back to loopback **while the
> command reports success**. `-Command` makes PowerShell parse the arguments, so arrays bind
> correctly. Measured from PowerShell, cmd and Git Bash.

```text
powershell -NoProfile -ExecutionPolicy Bypass -Command "& 'C:\path\to\scaffold-project.ps1' -OldProjectPath '{OLD_PROJECT_PATH}' -SolutionPath '{SOLUTION_PATH}' -TargetFramework '{TFM}' -NewProjectName '{NEW_PROJECT_NAME}' -ProjectType '{MVC|WebAPI}' -OldAppUrl '{OLD_APP_URL}' -SystemWebAdaptersVersion '{VERSION}' -YarpVersion '{VERSION}'"
```

Use a **Windows** path for the script even from Git Bash (`C:\…`, not `/c/…`) — Windows
PowerShell cannot resolve a POSIX path.

To trust real proxy addresses at scaffold time (instead of the fail-closed loopback
defaults), also pass `-TrustedProxies` and/or `-TrustedNetworks`. To let the proxy set the
request host, pass `-AllowedForwardedHosts` — without it, `X-Forwarded-Host` is ignored
(see the spoofing footgun under **Production hardening**). These write the
`ForwardedHeaders` section of the generated `appsettings.json`.

Append to the same single-line command (single-quoted, comma-separated — `-Command` parses
these as a real array):

```text
-TrustedProxies '10.0.0.5','10.0.0.6' -TrustedNetworks '10.0.0.0/8','::1/128' -AllowedForwardedHosts 'www.example.com'
```

When omitted, the template keeps its secure defaults — loopback-only trust, and no
forwarded host honored — and an operator opts in later by editing `appsettings.json`.

To pre-wire authentication interop, append **one** invocation group to the same single-line command.
The shared-cookie (filesystem and Azure) and remote-auth groups, and the UNC-path footgun, are in
**[ref/auth-setup.md](ref/auth-setup.md)** — read it before adding a group. Passing both groups, or
any companion without its switch, is rejected.

Add `-SkipBuild` to generate files without running `dotnet build`.

**Verify the script actually ran** before trusting the result: confirm the new project
directory and `Program.cs` exist. A shell-mangled invocation can exit 0 having created
nothing.

After either group, **tell the user the scaffold is only half the work** and point them at
the `README.SHAREDCOOKIE.md` / `README.REMOTEAUTH.md` the script wrote into the new project.
Until the .NET Framework half is wired, shared-cookie users simply appear signed out with no
error message to notice; remote auth instead fails the round trip, and a plain `[Authorize]`
endpoint returns a 500 regardless — see the footgun in **[ref/auth-setup.md](ref/auth-setup.md)**.

### 2.3 Manual Scaffolding

Read **[ref/manual-scaffold.md](ref/manual-scaffold.md)** whenever you hand-copy the templates:
if the script cannot run (PowerShell unavailable, permissions), a shell-mangled invocation exits 0
having created nothing, or a hosting or policy constraint forces manual scaffolding for net8.0/net9.0.
It covers copying `tmpl/mvc/` or `tmpl/webapi/`, replacing `$placeholder$` variables, the Template Files
Reference, and the eight marker keep-rules with the `appsettings.json` section-stripping table.
Those rules stop a hand-copy from emitting both auth paths at once, dropping the parameterless seam,
or failing to compile. They are not needed when the script performs the copy.

## Authentication interop

While both apps run side by side, a user who signs in on the .NET Framework app must be
recognised by the new ASP.NET Core proxy, or they appear signed out the moment a request is
handled by the new app. By default the scaffold emits only a **parameterless seam** —
`AddAuthentication()` with no scheme — which compiles and does not throw but authenticates
nobody. That is the right default: the correct interop depends on how the old app
authenticates, and guessing produces a silent failure. Before choosing between them, read
**[ref/auth-setup.md](ref/auth-setup.md)** for each path's full preconditions and companion
parameters — the wrong path, or the right path with a mismatched precondition, builds a proxy
that signs nobody in.

Two paths are supported, and they are mutually exclusive:

| | Shared cookie | Remote authentication |
|---|---|---|
| **How it works** | Both apps read and write the same encrypted cookie | The Core app asks the Framework app to authenticate each request |
| **Script switch** | `-EnableSharedCookieAuth` | `-EnableRemoteAuth` |
| **Tool argument** | `authInterop="sharedcookie"` | `authInterop="remoteauth"` |
| **Confirmed option value** | `Shared Cookie (Data Protection interop)` | `Remote Authentication` |
| **Choose when** | The old app uses Katana cookie auth **and** both apps can reach a shared Data Protection key ring — a filesystem directory or an Azure blob | The old app uses Windows auth, a custom identity provider, or the two apps can share no key ring at all |
| **Requires** | A shared Data Protection ring in one of the two supported topologies (`filesystem` + X.509 certificate, or `azureblob` + Key Vault), plus identical cookie name, scheme, and application name | A shared GUID API key, network reachability from Core to Framework |
| **Framework-side skill** | `sharing-authentication-cookies-katana-interop` | `migrating-mvc-system-web-adapters` |

Neither is on by default; `authInterop` defaults to `none`, which keeps the seam.

**A confirmed `Cross-App Cookie Authentication` value outranks "Choose when".** When that
upgrade option is among the confirmed selections, the path is already settled: take the
**Confirmed option value** row and use the switch in the same column. The option is agreed
with the user during planning and recorded in the compact block, and it is never reopened —
so re-deriving the path here can silently contradict a decision the user already made, with
nothing downstream positioned to notice.

Apply "Choose when" only when the option is **absent** from the confirmed selections. That is
the normal case whenever the scaffold is reached outside the .NET version upgrade scenario, or
when the option did not trigger for this app. Absence carries no information about which path
suits the app; it only means nobody has chosen yet.

**The Framework-side skill row has one gate.** When `Cross-App Cookie Authentication` is
confirmed as `Remote Authentication` **and** `System.Web Adapters` is confirmed as `Direct
Migration to ASP.NET Core APIs`, do not load `migrating-mvc-system-web-adapters` — that skill
carries the shim overlay the user declined. Give them the Framework-half handoff note instead
and say it is not walked through step by step: on the script path that is the
`README.REMOTEAUTH.md` copied into the project, and on the tool path, which writes none, hand
over this skill's `tmpl/auth/README.REMOTEAUTH.md` yourself. With either value absent, use the
row as written.

**The scaffold configures the ASP.NET Core half only.** Neither path works until the .NET
Framework app is changed too. When a switch is used, the script copies a handoff note into the
new project (`README.SHAREDCOOKIE.md` or `README.REMOTEAUTH.md`) describing that half. Tell
the user it exists — with **shared cookie** there is no error state, so an unfinished setup
looks exactly like a user who is not signed in. **Remote auth** is noisier: an unreachable or
unwired Framework host surfaces as a failed round trip, and a plain `[Authorize]` endpoint
returns a 500 (see the footgun in **[ref/auth-setup.md](ref/auth-setup.md)**) whether or not the Framework half is wired.

For the Framework half, load the matching skill above. The script's `README.REMOTEAUTH.md`
additionally inlines the server-side registration snippet, because the remote-auth skill covers
the Core side only; on the tool path, hand that snippet over from the skill yourself.

**Before wiring either path, read [ref/auth-setup.md](ref/auth-setup.md)** — it carries the footguns that
decide whether a configured proxy signs anyone in. The ones you cannot skip:

- **Remote auth requires SystemWebAdapters CoreServices `2.3.0` or newer**, and a migrated endpoint must name the scheme `[Authorize(AuthenticationSchemes = RemoteAppAuthenticationDefaults.AuthenticationScheme)]`; a plain `[Authorize]` returns **500**, not 401.
- **Shared cookie fails silently four ways** — cookie name, scheme (the Framework `AuthenticationType`), Data Protection application name, and key ring must all match, or the user just looks signed out.
- **Never silently substitute a different confirmed mechanism.** If a confirmed `Cross-App Cookie Authentication` value is blocked (for example by the CoreServices floor), report it and let the user choose.
- **Both halves must be wired.** The Visual Studio tool wires the same paths via `authInterop`, requires `targetFramework` net10.0 or later, and writes the keys blank with no README — see Step 1.

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
**[ref/framework-headers.md](ref/framework-headers.md)**.

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

On `net10.0`+ (required by the unadapted templates) use the **non-obsolete** pattern only:

| Use (non-obsolete on net10.0+) | Do NOT use (ASPDEPR005 / BC000660) |
|--------------------|------------------------------------|
| `ForwardedHeadersOptions.KnownIPNetworks` | `ForwardedHeadersOptions.KnownNetworks` |
| `System.Net.IPNetwork` | `Microsoft.AspNetCore.HttpOverrides.IPNetwork` |

The plugin's own API catalog flags the obsolete members as **BC000660** at
code-assessment time, so a project that hand-rolls the old pattern will surface the
warning; the templates above already use the correct API.

The right-hand column is obsolete **only on net10.0+** — that is where the deprecation
landed. On net8.0/net9.0 those same members are the correct API and `KnownIPNetworks` does
not exist at all; see **[ref/older-targets.md](ref/older-targets.md)**.

> **Requires ASP.NET Core 10.0+.** `ForwardedHeadersOptions.KnownIPNetworks` only exists
> in ASP.NET Core 10.0 and later (`System.Net.IPNetwork` is net8.0+, but the property is
> net10.0+). Use `net10.0` or newer for the unadapted templates.

#### Targeting below net10.0

The unadapted templates require `net10.0` or later. Only the forwarded-headers block needs it, but the script strips
the whole hardening set below net10.0 rather than ship a proxy that looks like a security boundary and is not.
Prefer raising the target; if a hosting or policy constraint forces net8.0/net9.0, use
**[ref/manual-scaffold.md](ref/manual-scaffold.md)** for the copy/marker rules and **[ref/older-targets.md](ref/older-targets.md)**
to adapt the forwarded-headers block (`KnownIPNetworks` becomes `KnownNetworks`) before building.

### Framework-side companion (required for correct scheme/host/IP)

`app.UseForwardedHeaders()` fixes only the **Core** side. When the .NET Framework app relies on the client's
scheme, host, or IP (`Request.IsSecureConnection`, `Url.Host`, `UserHostAddress`, redirects, absolute links),
you **must** also install the Framework-side `IHttpModule` that rewrites the server variables — **gated on the
proxy's IP**, with the **same fail-closed host allow-list** the Core side uses. This is a required companion
whenever the legacy app reads those values, not a troubleshooting-only step. The full module, its trusted-proxy
and host-allow-list guardrails, and the `web.config` registration are in **[ref/framework-headers.md](ref/framework-headers.md)**.

## Success Criteria

- [ ] New project folder created as sibling to old project folder
- [ ] .csproj TFM is `net10.0` or later (or net8.0/net9.0 forced by a hosting/policy constraint, with the manual adaptation applied), with correct package references (latest versions)
- [ ] Program.cs has YARP forwarder and SystemWebAdapters registration
- [ ] Program.cs configures forwarded headers via the TFM-appropriate API (`KnownIPNetworks` + `System.Net.IPNetwork` on net10.0+), with `UseForwardedHeaders()` as the first middleware
- [ ] Program.cs calls `AddAuthentication()` and runs `UseAuthentication()` immediately before `UseAuthorization()`. With an auth switch, the parameterless call is replaced by the configured scheme, and `UseAuthentication()` is present even below net10.0
- [ ] No `//<marker>` / `//</marker>` comment lines survive in any generated file
- [ ] If an auth switch was used: exactly **one** auth path is present, `appsettings.json` carries only that path's sections, and the user has been told the .NET Framework half is still outstanding. On the **script** path `README.SHAREDCOOKIE.md` or `README.REMOTEAUTH.md` is also in the project root; the **tool** path writes no README, so that handoff has to be spoken instead
- [ ] Program.cs sets the Kestrel security policy (server header off, TLS 1.2/1.3)
- [ ] Program.cs strips the backend's stack-fingerprint response headers (`Server`, `X-Powered-By`, `X-AspNet-Version`, `X-AspNetMvc-Version`)
- [ ] appsettings.json has `ProxyTo` key and a fail-closed `ForwardedHeaders` section (empty `TrustedProxies`, loopback `TrustedNetworks`, empty `AllowedHosts`), and **no** configuration section whose code was not emitted
- [ ] appsettings.json parses as valid JSON (`dotnet build` does not check this — backslashes in a Windows path must be escaped)
- [ ] launchSettings.json has `ProxyTo` pointing to the **verified** old app URL
- [ ] Framework-side `X-Forwarded-*` companion (IHttpModule rewriting server variables, gated on trusted proxy IPs) is in place when the Framework app relies on scheme/host/IP
- [ ] New project added to solution
- [ ] Old project has `_MigrateToProjectGuid` property pointing to new project
- [ ] New project builds with 0 errors

## Troubleshooting

If a scaffolded proxy misbehaves at build or runtime — 502s, a build failure, requests that are not
forwarded, or an auth-interop path that appears to sign nobody in — see the symptom/cause/fix table in
**[ref/troubleshooting.md](ref/troubleshooting.md)**.
