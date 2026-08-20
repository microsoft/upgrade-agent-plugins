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
| 2.3 | If Script Fails | Manual fallback — copy templates, replace placeholders |
| - | Authentication interop | Keeping users signed in across both apps while they run side by side |
| - | Production hardening | **Required** — forwarded headers, TLS, `UseAuthentication`, Framework-side companion |
| - | Template Files Reference | What each template contains, and the marker-kind matrix |
| - | Success Criteria | Final checklist |

**Do not stop reading after Step 1.** Step 1 only selects the host-appropriate mechanism;
the parameters, the marker rules, and the hardening all live in Step 2 and below.

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
| `SystemWebAdaptersVersion` | Use `get_supported_package_version` for `Microsoft.AspNetCore.SystemWebAdapters.CoreServices`. **With `-EnableRemoteAuth`, this must be `2.3.0` or newer** — see below. |
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

**Authentication interop parameters (optional, off by default).** Ask the user whether
signed-in users must stay signed in across both apps while the migration runs. If they do,
pick one path — the two are mutually exclusive and the script rejects both together:

| Parameter | Path | How to find it |
|-----------|------|---------------|
| `-EnableSharedCookieAuth` | Shared cookie | Both apps read the same encrypted cookie. Choose **only** when the old app authenticates with **Katana/OWIN cookie middleware** under `Microsoft.Owin.Host.SystemWeb`, and both apps can reach one shared Data Protection key ring. See the two preconditions below — neither is checked, and violating either produces a proxy that builds and signs nobody in. |
| `-SharedKeyRingProvider` | Shared cookie | Where the shared key ring lives: `filesystem` (default) or `azureblob`. **This must match how the old app already persists its keys** — ask, do not assume. It selects which of the two companion pairs below is required, and the wrong choice produces an app that starts and never decrypts. |
| `-SharedKeyRingPath` | Shared cookie, `filesystem` | Directory both apps can read (often a UNC share). **No default** — ask the user. |
| `-SharedCertificateThumbprint` | Shared cookie, `filesystem` | Thumbprint of the X.509 cert protecting the key ring. Both hosts need the private key. |
| `-SharedKeyRingUri` | Shared cookie, `azureblob` | Absolute `https` URI of the Azure Storage blob holding the ring, e.g. `https://acct.blob.core.windows.net/dp/keys.xml`. The container must exist; the blob need not. |
| `-SharedKeyVaultKeyId` | Shared cookie, `azureblob` | Absolute `https` URI of the Key Vault key protecting the ring, e.g. `https://vault.vault.azure.net/keys/dp/<version>`. |
| `-AzureDataProtectionBlobsVersion` | Shared cookie, `azureblob` | Optional. Version of `Azure.Extensions.AspNetCore.DataProtection.Blobs` to add to the generated project. Omit to take the script's verified default; pass `get_supported_package_version` for that package only if the default is unavailable to this customer. |
| `-AzureDataProtectionKeysVersion` | Shared cookie, `azureblob` | Optional. Same, for `Azure.Extensions.AspNetCore.DataProtection.Keys`. |
| `-SharedApplicationName` | Shared cookie | The old app's Data Protection application name. Must be identical on both sides. |
| `-SharedCookieName` | Shared cookie | The old app's Katana cookie name (`CookieAuthenticationOptions.CookieName`, often `.AspNet.ApplicationCookie`). Read it from the OWIN startup class or browser dev tools. **Never guess** — a wrong name means the user silently appears signed out. A `.ASPXAUTH` cookie means classic Forms authentication, which this path does **not** support; see the preconditions below. |
| `-SharedCookieScheme` | Shared cookie | The old app's `AuthenticationType` (Katana `CookieAuthenticationOptions.AuthenticationType`). |
| `-EnableRemoteAuth` | Remote auth | The new app asks the old app to authenticate each request. Choose when the old app uses **classic Forms authentication (`<forms>` in `Web.config`, `.ASPXAUTH`), Windows auth, a custom identity provider, or anything not Katana cookie-based**, or when the two apps cannot share a Data Protection key ring at all. |
| `-RemoteAppUrl` | Remote auth | Optional. Defaults to `-OldAppUrl`. Pass it only when the old app is reachable at a different address from the server. |
| `-RemoteAppApiKey` | Remote auth | A **GUID** shared with the old app. Generate with `[guid]::NewGuid()`. The script rejects a non-GUID. |

Every companion above is **required** when its switch is on and **rejected** when it is off, with
three exceptions, all marked *Optional* in the table: `-RemoteAppUrl` falls back to `-OldAppUrl`, and
the two `-AzureDataProtection*Version` parameters fall back to versions the script has verified
against the feed. Nothing else has a default, deliberately: a wrong cookie name, scheme, or key ring
produces an app that starts and serves traffic while authenticating nobody, with no error anywhere.
The same rule applies one level down — a `filesystem` companion passed with
`-SharedKeyRingProvider azureblob` is rejected, not ignored, and so is either version parameter
passed with the `filesystem` provider.

**Two preconditions on `-EnableSharedCookieAuth`. Neither is validated by the script, and each one
produces a proxy that compiles, starts, and silently signs nobody in.** Check both with the user
before choosing this path; if either fails, use `-EnableRemoteAuth` instead.

1. **The old app must authenticate with Katana/OWIN cookie middleware**, hosted under
   `Microsoft.Owin.Host.SystemWeb`. The emitted code reads a Data Protection ticket, and the
   Framework half is completed by the `sharing-authentication-cookies-katana-interop` skill, which
   requires `Microsoft.Owin.Security.Interop` and the `AspNetTicketDataFormat` shim. **Classic
   ASP.NET Forms authentication is not supported** — a `<forms>` element in `Web.config` and an
   `.ASPXAUTH` cookie mean a `machineKey`-encrypted `FormsAuthenticationTicket`, which ASP.NET Core
   cannot read no matter how the key ring is shared. Such an app must either move to Katana cookie
   middleware first, or use remote auth.
2. **The key ring topology must be one the scaffold emits, and `-SharedKeyRingProvider` must name
   the right one.** Two are supported:
   - `filesystem` — `PersistKeysToFileSystem(...).ProtectKeysWithCertificate(...)`. Both hosts need
     the directory and the certificate's private key.
   - `azureblob` — `PersistKeysToAzureBlobStorage(...).ProtectKeysWithAzureKeyVault(...)`, both
     authenticating with `DefaultAzureCredential`. Each host needs an identity granted **Storage
     Blob Data Contributor** on the blob and **Key Vault Crypto User** on the key. This is the shape
     a multi-instance or multi-slot deployment needs, because instances share the blob rather than a
     local disk.

   An app whose keys live somewhere else — **a database (`PersistKeysToDbContext`), Redis, or
   DPAPI-NG** — has no supported path through this scaffold: the generated `Program.cs` must be
   hand-edited to swap the persistence and protection calls. Confirm the topology before choosing
   this path.

Neither switch completes the job on its own — each configures only the ASP.NET Core half.
The script drops a `README.SHAREDCOOKIE.md` or `README.REMOTEAUTH.md` into the new project
with the .NET Framework half. See **Authentication interop** below.

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

To pre-wire authentication interop, add **one** of the following groups. Passing both
groups, or any companion without its switch, is rejected.

```powershell
  # Shared cookie: both apps read the same encrypted cookie.
  # Filesystem key ring (the default) -- a directory both hosts can read.
  -EnableSharedCookieAuth `
  -SharedKeyRingPath "\\fileserver\keyring" `
  -SharedCertificateThumbprint "A1B2C3..." `
  -SharedApplicationName "MyLegacyApp" `
  -SharedCookieName ".AspNet.ApplicationCookie" `
  -SharedCookieScheme "ApplicationCookie"
```

```powershell
  # Shared cookie, Azure key ring -- when the old app already persists its keys to blob
  # storage, or the two hosts share no filesystem. Adds two Azure NuGet packages.
  -EnableSharedCookieAuth `
  -SharedKeyRingProvider azureblob `
  -SharedKeyRingUri "https://acct.blob.core.windows.net/dataprotection/keys.xml" `
  -SharedKeyVaultKeyId "https://myvault.vault.azure.net/keys/dp-key/abc123" `
  -SharedApplicationName "MyLegacyApp" `
  -SharedCookieName ".AspNet.ApplicationCookie" `
  -SharedCookieScheme "ApplicationCookie"
```

```powershell
  # Remote auth: the new app asks the old app who the user is.
  -EnableRemoteAuth `
  -RemoteAppApiKey "11111111-2222-3333-4444-555555555555"
```

Add `-SkipBuild` to generate files without running `dotnet build`.

After either group, **tell the user the scaffold is only half the work** and point them at
the `README.SHAREDCOOKIE.md` / `README.REMOTEAUTH.md` the script wrote into the new project.
Until the .NET Framework half is wired, shared-cookie users simply appear signed out with no
error message to notice; remote auth instead fails the round trip, and a plain `[Authorize]`
endpoint returns a 500 regardless — see the footgun under **Authentication interop**.

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
1. Process the marker comments in `Program.cs` — see **Marker comments in the templates** below. This is not a blanket delete: which blocks you keep depends on the TFM and on whether the user wants authentication interop, and keeping the wrong combination emits code that does not compile or that authenticates nobody.
2. Rename `ProjectName.csproj` to `{NewProjectName}.csproj`
3. Run `dotnet sln "{SOLUTION_PATH}" add "{NEW_PROJECT_PATH}"`
4. Find the new project's GUID in the solution file
5. Add `<_MigrateToProjectGuid>{GUID}</_MigrateToProjectGuid>` to the old project's .csproj
6. Run `dotnet build` to verify

The `appsettings.json` template ships configuration sections for **every** optional feature.
A hand-copy must delete the sections whose code it did not keep, or the generated app carries
configuration nothing reads — an operator will populate `SharedDP:KeyRingPath` and reasonably
believe authentication is configured:

| Keep the section | Only if you kept |
|---|---|
| `ForwardedHeaders` | the `hardening` blocks (net10.0+) |
| `SharedCookie`, and `SharedDP:ApplicationName` | the `sharedcookie` blocks |
| `SharedDP:KeyRingPath`, `SharedDP:CertificateThumbprint` | the `dpfilesystem` block |
| `SharedDP:KeyRingUri`, `SharedDP:KeyVaultKeyId` | the `dpazureblob` block |
| `RemoteApp` | the `remoteauth` blocks |

The two `SharedDP` key pairs are alternatives, exactly like the blocks that read them: keep the pair
belonging to the key ring block you kept and delete the other. Leaving both means an operator sees a
blank `KeyRingPath` beside a filled-in `KeyRingUri` and fills it in, which does nothing.

If you kept `dpazureblob`, the project also needs two `PackageReference` entries the template does
**not** ship, because the far more common filesystem scaffold must not carry an Azure dependency:

```xml
<PackageReference Include="Azure.Extensions.AspNetCore.DataProtection.Blobs" Version="1.5.3" />
<PackageReference Include="Azure.Extensions.AspNetCore.DataProtection.Keys" Version="1.6.3" />
```

`Azure.Identity` is **not** added: it arrives transitively through both, and the emitted code names
`Azure.Identity.DefaultAzureCredential` fully qualified, so it needs no `using` either.

Fill in the values by hand; unlike the script, a hand-copy has nothing escaping them. A
Windows path must be written with escaped backslashes (`"C:\\keys\\app"`), or the file is not
valid JSON and the app fails at startup — `dotnet build` will not catch it, because it never
parses `appsettings.json`.

To trust real proxies, edit `ForwardedHeaders:TrustedProxies` /
`ForwardedHeaders:TrustedNetworks` directly; to let the proxy set the host, populate
`ForwardedHeaders:AllowedHosts`. See **Production hardening**.

> **Manual path has no automatic TFM check.** `scaffold-project.ps1` strips the hardening
> below net10.0, but a hand-copy has nothing enforcing that. `tmpl/*/Program.cs` uses
> `ForwardedHeadersOptions.KnownIPNetworks`, so copying it into a project targeting
> net8.0/net9.0 compiles to **CS1061**. Before copying, confirm `$TargetFramework$` is
> `net10.0` or later; if it cannot be, follow **Targeting below net10.0** under
> **Production hardening**.
>
> **Mutual exclusion is enforced only by the script.** The templates carry the shared-cookie
> and remote-auth blocks side by side, so a hand-copy that deletes every marker line without
> deleting the blocks emits both paths at once, plus the placeholder seam — three competing
> `AddAuthentication` registrations and two `AddSystemWebAdapters()` calls. Follow the table
> below instead of deleting markers wholesale.

### Template Files Reference

```
tmpl/
  mvc/                         ← For MVC projects
    ProjectName.csproj         ← SDK-style web project with YARP + SystemWebAdapters packages
    Program.cs                 ← AddControllersWithViews + YARP forwarder + hardening + auth interop blocks
    appsettings.json           ← ProxyTo + ForwardedHeaders + SharedDP/SharedCookie/RemoteApp sections
    appsettings.Development.json ← logging overrides (inherits the base ForwardedHeaders section)
    Properties/
      launchSettings.json      ← ProxyTo in environmentVariables
  webapi/                      ← For WebAPI projects
    ProjectName.csproj         ← Same packages, no Swashbuckle
    Program.cs                 ← AddControllers + YARP forwarder + hardening + auth interop blocks (no UseStaticFiles)
    appsettings.json           ← ProxyTo + ForwardedHeaders + SharedDP/SharedCookie/RemoteApp sections
    appsettings.Development.json ← logging overrides (inherits the base ForwardedHeaders section)
    Properties/
      launchSettings.json
  auth/                        ← Handoff notes. NOT a project template — copied into the new
                                 project only when an auth switch is on, one file, at the root.
    README.SHAREDCOOKIE.md     ← .NET Framework half for -EnableSharedCookieAuth
    README.REMOTEAUTH.md       ← .NET Framework half for -EnableRemoteAuth
marker-processor.ps1           ← Shared marker parser, dot-sourced by scaffold-project.ps1
```

### Marker comments in the templates

Both `Program.cs` templates delimit optional blocks with `//<kind>` / `//</kind>` comment
markers. `scaffold-project.ps1` always removes the marker lines themselves, and removes the
enclosed code when that kind is not selected. Regions are **sequential, never nested**; the
script throws on an unbalanced, mismatched, or unknown marker rather than emitting malformed
source.

| Marker kind | Keep the enclosed code when |
|---|---|
| `hardening` | TFM is net10.0 or later |
| `authseam` | TFM is net10.0+ **and neither** auth switch is on (the parameterless placeholder) |
| `authpipeline` | TFM is net10.0+ **or** either auth switch is on |
| `swadefault` | `-EnableRemoteAuth` is **off** |
| `sharedcookie` | `-EnableSharedCookieAuth` is on |
| `dpfilesystem` | `-EnableSharedCookieAuth` is on **and** `-SharedKeyRingProvider filesystem` (the default) |
| `dpazureblob` | `-EnableSharedCookieAuth` is on **and** `-SharedKeyRingProvider azureblob` |
| `remoteauth` | `-EnableRemoteAuth` is on |

Four of these are easy to get wrong by hand, and each fails silently:

- **`authpipeline` is separate from `hardening` on purpose.** It holds
  `app.UseAuthentication()`, which an auth path needs even below net10.0. Strip it with the
  hardening and you get an app that registers a cookie scheme with no middleware to run it —
  it authenticates nobody, in exactly the configuration shared cookies exist to support.
- **`authseam` and the two auth paths are alternatives.** Each auth path registers its own
  scheme, so keeping the parameterless `AddAuthentication()` as well emits two competing
  registrations.
- **`swadefault` is dropped when remote auth is on.** The remote-auth block re-issues
  `AddSystemWebAdapters()` as the head of a fluent chain rather than extending the plain call,
  because a marker region can only insert lines. Keep both and the call appears twice.
- **`dpfilesystem` and `dpazureblob` are alternatives, and exactly one must survive** whenever
  `sharedcookie` does. Each opens its own `AddDataProtection()` chain, so keeping both means the
  second registration silently wins — and it is the one whose `appsettings.json` keys you were told
  to delete. Keeping neither leaves an `AddCookie` with no shared key ring, which decrypts nothing
  the other app wrote.

There are three `sharedcookie` regions in each template, and that is intentional. The first holds
`using Microsoft.AspNetCore.DataProtection;`: a C# `using` must precede all top-level statements, so
it sits in its own region at the top of the file, far from the code that needs it. It is deliberately
**not** inside `hardening` — that would strip it on a sub-net10 shared-cookie scaffold and
fail the build with CS0103. It also serves **both** key ring topologies, which is why it is
`sharedcookie` rather than duplicated into `dpfilesystem` and `dpazureblob`. The remaining two
bracket the key ring regions: the explanatory comment before them, and the `AddAuthentication` /
`AddCookie` registration after. Regions cannot nest, so a shared block that spans the two
alternatives has to be split around them rather than wrapped about them.

Key things the templates set up:
- `builder.WebHost.ConfigureKestrel(...)` — security policy (server header off, TLS 1.2/1.3)
- `builder.Services.Configure<ForwardedHeadersOptions>(...)` — fail-closed forwarded headers (non-obsolete API)
- `builder.Services.AddAuthentication()` — parameterless seam so `UseAuthentication()` cannot crash at runtime. **Replaced** by a configured scheme when `-EnableSharedCookieAuth` or `-EnableRemoteAuth` is used; see **Authentication interop**.
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

## Authentication interop

While both apps run side by side, a user who signs in on the .NET Framework app must be
recognised by the new ASP.NET Core proxy, or they appear signed out the moment a request is
handled by the new app. By default the scaffold emits only a **parameterless seam** —
`AddAuthentication()` with no scheme — which compiles and does not throw but authenticates
nobody. That is the right default: the correct interop depends on how the old app
authenticates, and guessing produces a silent failure.

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
returns a 500 (see the footgun below) whether or not the Framework half is wired.

For the Framework half, load the matching skill above. The script's `README.REMOTEAUTH.md`
additionally inlines the server-side registration snippet, because the remote-auth skill covers
the Core side only; on the tool path, hand that snippet over from the skill yourself.

> **Footgun — with remote auth, plain `[Authorize]` is not enough.** The scaffold registers
> remote authentication as a **non-default** scheme
> (`AddAuthenticationClient(isDefaultScheme: false)`), because this app fronts a catch-all
> `MapForwarder` route: as the default scheme, every forwarded request would make a remote
> authentication call to the Framework app that is about to authenticate it anyway,
> double-authenticating each request and risking a redirect loop between the two apps.
>
> The consequence is that a migrated endpoint must name the scheme explicitly —
> `[Authorize(AuthenticationSchemes = RemoteAppAuthenticationDefaults.AuthenticationScheme)]`.
> A plain `[Authorize]` falls back to a default scheme that does not exist, so it denies and then
> throws `InvalidOperationException: No authenticationScheme was specified, and there was no
> DefaultChallengeScheme found` — the endpoint returns **500**, not 401 and not an anonymous
> success. It fails closed; the confusion is the status code, not a hole. The alternative is to
> make remote auth the default and call `.ShortCircuit()` on the forwarder route; naming the
> scheme is the less surprising option and is what the generated `Program.cs` documents inline.

> **Remote auth requires SystemWebAdapters CoreServices `2.3.0` or newer.** The non-default-scheme
> registration above holds only because the adapters *also* register an internal sentinel scheme,
> which stops ASP.NET Core auto-promoting a lone registered scheme to the default. Older releases do
> not: on `2.0.0` the `isDefaultScheme: false` argument is accepted and `Remote` becomes the default
> anyway, so every forwarded request makes the remote authentication call the argument exists to
> prevent — and nothing reports it, because the project restores, builds and starts normally. The
> script therefore **rejects** `-EnableRemoteAuth` together with an older `-SystemWebAdaptersVersion`.
>
> If `get_supported_package_version` returns something older, **do not drop `-EnableRemoteAuth` to
> get past the error**, and do not add the flag back by hand-editing the generated project. Either
> scaffold without auth interop and tell the user that remote auth needs CoreServices `2.3.0` or
> newer, or use `-EnableSharedCookieAuth`, which does not depend on this behaviour.
>
> **If `Remote Authentication` was the confirmed `Cross-App Cookie Authentication` value**, the
> second of those is not yours to take unilaterally. The floor is a constraint the user never
> saw when they chose, and the option is never reopened, so switching mechanism here settles a
> decision behind them. Report that the floor blocks the confirmed path and let them choose
> between raising CoreServices to `2.3.0` and changing mechanism. Scaffolding without auth
> interop meanwhile is fine — it leaves the seam and forecloses nothing.

> **Footgun — the shared-cookie contract has four separate ways to fail silently.** The
> cookie name, the scheme name (which must equal the Framework app's `AuthenticationType`),
> the Data Protection application name, and the key ring itself must all match. Any mismatch
> produces the same symptom: the user appears signed out. This is why none of these parameters
> has a default. The script path writes the debugging order into `README.SHAREDCOOKIE.md`; the
> tool path writes no README, so walk the user through that order yourself — it is the
> shared-cookie row of the troubleshooting table below.

**Visual Studio note.** The `scaffold_yarp_proxy_web_project` tool wires the same two paths
via `authInterop`, with three differences from the script (all covered in Step 1): it requires
`targetFramework` net10.0 or later, it writes the configuration keys **blank** for the user to
fill in rather than taking the values as arguments, and it writes **no README** — the
`tmpl/auth/` notes ship inside this skill, which the tool cannot reach. The keys are the same
ones listed above. Blank values fail loudly rather than silently, but not at the same moment:
the shared-cookie keys throw at **startup** (`DirectoryInfo("")` is an eager argument), while
`RemoteApp:Url` throws on **first use of the remote scheme**, because its options are validated
lazily. Either way an unfinished configuration cannot be mistaken for a working one. After the
tool returns, point the user at the comments in the generated `Program.cs` and at the matching
Framework-side skill (`sharing-authentication-cookies-katana-interop` for shared cookie,
`migrating-mvc-system-web-adapters` for remote auth — subject to the same gate as the table
above: skip that load when `Remote Authentication` and `Direct Migration to ASP.NET Core APIs`
are both confirmed, and hand over this skill's `tmpl/auth/README.REMOTEAUTH.md` yourself, since
this path writes none). When you have the values and
the host allows it, `scaffold-project.ps1` is the better path.

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
| Shared cookie: user signs in on the old app but the new app shows them signed out | Only the ASP.NET Core half of the interop is wired | Complete the .NET Framework half — see `README.SHAREDCOOKIE.md` in the new project (script path only; the tool path writes none) and **Authentication interop** |
| Shared cookie: still signed out after both halves are wired | One of the four values does not match | Check in order: cookie name (is the browser sending it to both hosts?), scheme name vs the Framework `AuthenticationType`, Data Protection application name, then key ring/certificate access. Every mismatch produces this same symptom with no error |
| Remote auth: `[Authorize]` endpoint returns 500 with "No authenticationScheme was specified, and there was no DefaultChallengeScheme found" | The remote scheme is not the default, by design, and a plain `[Authorize]` has nothing to fall back to | Add `[Authorize(AuthenticationSchemes = RemoteAppAuthenticationDefaults.AuthenticationScheme)]` — see the footgun under **Authentication interop**. Do not "fix" it by pinning a default scheme |
| Remote auth: the authenticated request fails or times out reaching the old app | The .NET Framework half is not wired, or `RemoteApp:Url` is unreachable from the new app | Complete the .NET Framework half — on the script path see `README.REMOTEAUTH.md` in the new project, which inlines the server-side registration; on the tool path there is no README, so follow `migrating-mvc-system-web-adapters` |
| Remote auth: Framework app rejects the key at the first sign-in (not at startup) | `RemoteAppApiKey` is not a GUID, or differs between the two apps | Both sides must carry the identical GUID; the script rejects a non-GUID `-RemoteAppApiKey`. A clean Framework startup does not mean the key is valid — it is only read per request |
| App starts then crashes reading configuration | `appsettings.json` is not valid JSON — usually an unescaped `\` in a Windows path | Escape backslashes (`"C:\\keys\\app"`). `dotnet build` never parses `appsettings.json`, so a successful build proves nothing here |
