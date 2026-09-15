# Manual scaffolding

Read this whenever you hand-copy the templates: if `scaffold-project.ps1` cannot run or fails
(PowerShell unavailable, permissions, or a shell-mangled invocation that exited 0 having created
nothing), or a hosting or policy constraint forces manual scaffolding for net8.0/net9.0.
It carries the manual copy steps, the Template Files Reference, and the eight marker keep-rules
the script otherwise applies for you. On the normal script path you do not need this file.

## Contents

- [2.3 Manual Scaffolding](#23-manual-scaffolding)
- [Template Files Reference](#template-files-reference)
- [Marker comments in the templates](#marker-comments-in-the-templates)
### 2.3 Manual Scaffolding

For either hand-copy path, follow these steps. The template files in `tmpl/mvc/` and `tmpl/webapi/`
contain the exact file contents — copy them to the new project folder and replace
the `$placeholder$` variables:

For a **manual adaptation** to net8.0/net9.0, keep the `hardening` blocks and the
`ForwardedHeaders` configuration section. Keep `authpipeline`, and keep `authseam` only when
neither auth path is selected. Unlike the script's unadapted lower-target output, this path
retains the hardening and adapts its forwarded-headers API before building, as described below.

| Placeholder | Replace with |
|-------------|-------------|
| `$TargetFramework$` | Target framework — prefer `net10.0` or later; net8.0/net9.0 requires the manual adaptation before building |
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
2. For net8.0/net9.0, adapt the retained forwarded-headers code using [Targeting below net10.0](older-targets.md). Do not strip the other hardening items.
3. Rename `ProjectName.csproj` to `{NewProjectName}.csproj`
4. Run `dotnet sln "{SOLUTION_PATH}" add "{NEW_PROJECT_PATH}"`
5. Find the new project's GUID in the solution file
6. Add `<_MigrateToProjectGuid>{GUID}</_MigrateToProjectGuid>` to the old project's .csproj
7. Run `dotnet build` to verify

The `appsettings.json` template ships configuration sections for **every** optional feature.
A hand-copy must delete the sections whose code it did not keep, or the generated app carries
configuration nothing reads — an operator will populate `SharedDP:KeyRingPath` and reasonably
believe authentication is configured:

| Keep the section | Only if you kept |
|---|---|
| `ForwardedHeaders` | the `hardening` blocks, including manual adaptation on net8.0/net9.0 |
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
`ForwardedHeaders:AllowedHosts`. See [Production hardening](../SKILL.md#production-hardening-required).

> **Manual path has no automatic TFM check.** `scaffold-project.ps1` strips the hardening
> below net10.0, but a hand-copy has nothing enforcing that. `tmpl/*/Program.cs` uses
> `ForwardedHeadersOptions.KnownIPNetworks`, so copying it into a project targeting
> net8.0/net9.0 compiles to **CS1061** without adaptation. On those targets, complete step 2
> before building; keep the hardening and matching configuration rather than applying the
> script's below-net10 stripping behavior.
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
| `hardening` | TFM is net10.0 or later **or** this is a manual adaptation to net8.0/net9.0 |
| `authseam` | (TFM is net10.0+ **or** this is a manual adaptation) **and neither** auth switch is on (the parameterless placeholder) |
| `authpipeline` | TFM is net10.0+ **or** this is a manual adaptation **or** either auth switch is on |
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
- `builder.Services.AddAuthentication()` — parameterless seam so `UseAuthentication()` cannot crash at runtime. **Replaced** by a configured scheme when `-EnableSharedCookieAuth` or `-EnableRemoteAuth` is used; see [Authentication interop](../SKILL.md#authentication-interop).
- `builder.Services.AddSystemWebAdapters()` — System.Web compatibility shims
- `builder.Services.AddHttpForwarder()` — YARP forwarder registration
- `app.UseForwardedHeaders()` — **first** middleware; recovers client scheme/host/IP
- `app.Use(...)` response scrubber — strips the backend's `Server` / `X-Powered-By` / `X-AspNet-Version` / `X-AspNetMvc-Version` headers
- `app.UseAuthentication()` — runs immediately **before** `app.UseAuthorization()`
- `app.UseSystemWebAdapters()` — middleware for adapter support
- `app.MapForwarder("/{**catch-all}", ...)` — catch-all route at lowest priority, forwards unmatched requests to old app

The `appsettings.json` templates also ship a fail-closed `ForwardedHeaders` section
(`TrustedProxies: []`, `TrustedNetworks: [ "127.0.0.1/32", "::1/128" ]`, `AllowedHosts: []`)
that the code above binds. See [Production hardening](../SKILL.md#production-hardening-required).
