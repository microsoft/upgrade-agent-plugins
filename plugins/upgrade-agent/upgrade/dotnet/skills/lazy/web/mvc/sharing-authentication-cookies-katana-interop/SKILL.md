---
name: sharing-authentication-cookies-katana-interop
description: >
  Shares authentication cookies between Katana/OWIN applications on ASP.NET Framework and ASP.NET
  Core applications during side-by-side migrations. Use when both hosts must accept the same cookie,
  when AspNetTicketDataFormat, DataProtectorShim, or Microsoft.Owin.Security.Interop is needed, or
  when users must remain signed in while routes move behind YARP or System.Web Adapters.
metadata:
  discovery: lazy
  traits: .NET|CSharp|VisualBasic|DotNetCore
---

# Share Authentication Cookies Between Katana and ASP.NET Core

## Overview

Configure a Katana/OWIN Framework host and an ASP.NET Core host to read and write one authentication cookie during an incremental migration. This is a direct-cookie alternative to System.Web Adapters Remote Authentication: it avoids a per-request call to the Framework host, but requires exact agreement on keys, purposes, scheme, ticket format, cookie name, and chunking.

Every snippet here and the whole of [`ref/legacy.cs`](ref/legacy.cs) are C#. A Visual Basic application must translate the reference file; the cookie wire contract is language-independent and unchanged.

> **Related skills:** Use `scaffolding-yarp-proxy-project` to create the ASP.NET Core host this skill assumes already exists. Use `migrating-mvc-system-web-adapters` when the Core host should ask the Framework host to authenticate each request. Use `migrating-owin-cookie-auth` for a full cutover where the Framework host will stop serving traffic. Use `migrating-mvc-filters` to translate custom `AuthorizeAttribute` subclasses and authorization filters; shared-cookie decryption does not migrate those gates.

## Prerequisites

Check every item before editing either host. If one does not hold, stop and tell the user what must change first. Do not start the workflow and do not attempt to repair a failure that these checks predict.

- **The Framework project targets .NET Framework 4.6.2 or later.** `Microsoft.Owin.Security.Interop` 2.3.11 ships only a `net462` assembly, so an earlier target fails restore with NU1202 rather than degrading gracefully. Stop and ask the user to retarget before continuing.
- **An ASP.NET Core host already exists.** This skill configures one; it does not create one. If there is none, run `scaffolding-yarp-proxy-project` first.
- **Katana runs under `Microsoft.Owin.Host.SystemWeb`.** The reference implementation rejects a missing host data-protection provider instead of silently accepting Katana's machine-local DPAPI fallback. Adding the package does not convert an OWIN self-host: if the application self-hosts, stop and inform the user that shared cookies require the System.Web host.
- **`CookieAuthenticationOptions.SessionStore`/`ITicketStore` is not configured.** Server-side ticket stores are incompatible because the other host receives only an opaque session key. Stop and inform the user that the store must be removed before cookies can be shared.
- **The existing cookie name can be preserved.** Renaming it makes every outstanding cookie invisible to the fallback and forces re-login. If a rename is unavoidable, stop and confirm that forced re-login is acceptable.

## Workflow

```text
Migration progress:
- [ ] Step 1: Inventory the existing cookie and authorization contract
- [ ] Step 2: Configure a protected shared key ring
- [ ] Step 3: Align the Framework and Core cookie formats
- [ ] Step 4: Upgrade existing cookies before opening Core routes
- [ ] Step 5: Preserve cross-host route invariants
- [ ] Step 6: Validate both directions and retire the fallback
```

### Step 1: Inventory the Contract

Record these values before editing either host:

| Contract | Framework source | Required Core match |
|---|---|---|
| Cookie name/domain/path | `CookieAuthenticationOptions` and deployed response | `Cookie.Name`, `Domain`, and `Path` |
| Scheme | Katana `AuthenticationType` and every identity-creation call | `AddAuthentication`/`AddCookie` scheme |
| Lifetime/sliding behavior | `ExpireTimeSpan`, `SlidingExpiration` | Corresponding Core cookie options |
| Claims | Identity creation and validation callbacks | Claim types consumed by Core policies |
| Authorization | `AuthorizeAttribute` subclasses, roles, filters | Equivalent policies, handlers, and response behavior |
| Cookie response writer | OWIN headers, `HttpResponse.Cookies`, or both | One wire-compatible write path per response |
| Ticket data format | `CookieAuthenticationOptions.TicketDataFormat` and any custom `ISecureDataFormat` | If customized, the default `"v1"` fallback reader in `ref/legacy.cs` will not read existing cookies — substitute the application's real legacy format before deploying. A mismatch presents as a silent mass sign-out: no exception, no fallback-hit telemetry, and no `Set-Cookie` |

For each host, enumerate every consumed claim type and authorization gate. Confirm role, subject/name identifier, tenant, MFA, and application-specific claim URIs retain identical meaning. A decryptable cookie is not sufficient if policies interpret its claims differently. For custom authorization filters, follow `migrating-mvc-filters` and compare each migrated policy's challenge, forbid, redirect, status-code, and header behavior.

### Step 2: Configure the Shared Key Ring

Add these packages to the Framework host only. Match the project's existing package-management format before writing anything:

- **Central Package Management** (a `Directory.Packages.props` exists): add a `<PackageVersion>` entry for each package and a versionless `<PackageReference>` in the project. A bare `Version` attribute on a `PackageReference` is NU1008 under CPM and fails restore. Where raising a central version would move unrelated projects, use a project-local `VersionOverride` instead. See `converting-to-cpm`.
- **`packages.config`**: follow `managing-legacy-dotnet-packages`. Katana/OWIN net472 applications are the population most likely to still use this format.
- **Plain `PackageReference`**: use the block below as written. See `managing-package-references`.

```xml
<PackageReference Include="Microsoft.AspNetCore.DataProtection.Extensions" Version="2.3.10" />
<PackageReference Include="Microsoft.Owin.Host.SystemWeb" Version="4.2.2" />
<PackageReference Include="Microsoft.Owin.Security.Interop" Version="2.3.11" />
<PackageReference Include="System.Security.Cryptography.Xml" Version="10.0.11" />
```

`Microsoft.AspNetCore.DataProtection` 2.3.9 declares `System.Security.Cryptography.Xml` 8.0.2, which has known high-severity vulnerabilities. Override that transitive minimum with a currently supported secure version compatible with the Framework target; 10.0.11 supports .NET Framework 4.6.2 and later. Run NuGet vulnerability auditing when implementing the skill rather than copying these versions without rechecking. Use the ASP.NET Core host's current Data Protection packages. The hosts share the persisted key-ring format, not package versions.

Choose storage and key encryption together:

| Topology | Persist the ring with | Protect keys at rest with |
|---|---|---|
| Azure | `PersistKeysToAzureBlobStorage` | `ProtectKeysWithAzureKeyVault` |
| Shared database | `PersistKeysToDbContext` or an `IXmlRepository` | Certificate or Key Vault |
| Shared filesystem | `PersistKeysToFileSystem` | Certificate or shared DPAPI-NG descriptor |

Do not rely on default per-user/per-machine DPAPI for a shared ring; another host identity or machine cannot decrypt it. Key Vault encryption is not persistence by itself.

Set the same application name on both hosts:

```csharp
services.AddDataProtection()
    .PersistKeysToFileSystem(sharedKeyDirectory)
    .ProtectKeysWithCertificate(keyEncryptionCertificate)
    .SetApplicationName(sharedApplicationName);
```

### Step 3: Align Cookie Formats

All six elements below are required:

1. One shared, encrypted-at-rest Data Protection key ring.
2. The same `SetApplicationName` value.
3. Framework `AspNetTicketDataFormat` wrapping a `DataProtectorShim`.
4. The purpose triple `("Microsoft.AspNetCore.Authentication.Cookies.CookieAuthenticationMiddleware", scheme, "v2")`.
5. The same explicit cookie name and Core-compatible `chunks-N` chunking.
6. `UseAuthentication()` before `UseAuthorization()` in the Core pipeline.

The `"v2"` purpose selects the ASP.NET Core authentication-ticket format. Katana's default `"v1"` purpose and ticket serializer are not interchangeable.

Microsoft's canonical recipe uses the fully qualified Interop manager:

```csharp
// Standalone alternative to ref/legacy.cs. Do not combine the two: LegacyCookieTransition.Configure
// rejects this manager at runtime because it owns chunk parsing and cleanup itself.
options.CookieManager = new Microsoft.Owin.Security.Interop.ChunkingCookieManager();
```

Keep the namespace qualified. `Microsoft.Owin.Infrastructure.ChunkingCookieManager` has the same class name and compiles cleanly, but writes Katana's `chunks:N` marker, which ASP.NET Core does not read.

Use that direct manager only when OWIN owns every response-cookie write. In a System.Web application where MVC or another component also modifies `HttpResponse.Cookies`, use [`ref/legacy.cs`](ref/legacy.cs) instead. Its wrapper preserves the same `chunks-N` wire format while delegating each write to `SystemWebCookieManager`, preventing the OWIN-header and System.Web cookie collections from overwriting one another. This is a host-write-path hardening choice, not a different cookie-sharing protocol.

On the Framework host, copy [`ref/legacy.cs`](ref/legacy.cs) into the application and configure the existing cookie options before `UseCookieAuthentication`:

```csharp
var sharedProvider = DataProtectionProvider.Create(
    sharedKeyDirectory,
    builder => builder
        .ProtectKeysWithCertificate(keyEncryptionCertificate)
        .SetApplicationName(sharedApplicationName));

// Refactor the existing registration to expose its fully configured options.
// Do not replace it with a partial options object.
CookieAuthenticationOptions options = existingCookieOptions;
CookieAuthenticationProvider provider = options.Provider as CookieAuthenticationProvider;
if (provider == null)
{
    throw new InvalidOperationException(
        "Merge the transition callback into the application's custom provider.");
}

LegacyCookieTransition.Configure(
    app,
    sharedProvider,
    options,
    provider,
    onLegacyCookieRead);

app.UseCookieAuthentication(options);
app.SetDefaultSignInAsAuthenticationType(sharedScheme);
```

Pass the existing `CookieAuthenticationOptions` and `CookieAuthenticationProvider` instances. `Configure` replaces only the ticket format, wraps the existing non-chunking cookie writer (or a `SystemWebCookieManager` when none was set), and composes the existing validation callback. Do not pass a Katana, Interop, or System.Web chunking manager into the reference wrapper; nested chunk parsing can reintroduce unbounded cleanup from a client marker. Call `Configure` exactly once per options instance: a duplicate registration in an existing OWIN startup would otherwise double-wrap the cookie manager and compose the validation callback onto itself, so the reference implementation rejects the second call with an `ArgumentException` rather than silently degrading. It preserves cookie domain/path, `Secure`, `HttpOnly`, `SameSite`, lifetime/sliding behavior, login/logout paths, return-url parameter, and all other provider callbacks. Its monitoring callback is isolated so telemetry failure cannot reject a valid cookie. If the application uses a different `ICookieAuthenticationProvider` implementation, merge the reference validation callback into that provider rather than replacing it. `ValidateAndRewriteAsync` is private in the reference file; because the file is copied into the application, change its accessibility or lift its body as needed.

`onLegacyCookieRead` is an `Action` invoked once per legacy-format cookie read. Implement it rather than passing `null`: it is the only source of the fallback-hit metric that gates the transition window and fallback retirement in Step 4, and neither gate can be evaluated without it.

The reference cookie manager also exposes `ThrowForPartialCookies`, which defaults to `false` so a truncated chunk set is treated as a missing cookie and the client simply re-authenticates. Set it to `true` in staging to surface truncation as a `FormatException` instead of a silent sign-out; leave it `false` in production unless a partial-cookie fault is under active investigation.

On the Core host:

```csharp
builder.Services.AddDataProtection()
    .PersistKeysToFileSystem(sharedKeyDirectory)
    .ProtectKeysWithCertificate(keyEncryptionCertificate)
    .SetApplicationName(sharedApplicationName);

builder.Services.AddAuthentication(sharedScheme)
    .AddCookie(sharedScheme, options =>
    {
        options.Cookie.Name = existingCookieName;
        options.ExpireTimeSpan = existingLifetime;
        options.SlidingExpiration = true;
        options.Events.OnValidatePrincipal = ValidateSharedPrincipalAsync;
    });

// After routing and before authorization/endpoints:
app.UseAuthentication();
app.UseAuthorization();
```

Match deployed cookie domain, path, `Secure`, `HttpOnly`, and `SameSite` behavior as well as the values shown above. The Katana `AuthenticationType`, Core scheme, purpose-string middle value, default sign-in type, and every `ClaimsIdentity` authentication type must match exactly. The reference normalizes a mismatched legacy identity during forced rewrite, but all identity-creation call sites still need correction. Port every Katana `OnValidateIdentity` security check to Core's `OnValidatePrincipal`, including principal rejection and renewal behavior. Core's default callback is a no-op, so omitting this mapping can accept accounts that Framework would reject.

### Step 4: Upgrade Existing Cookies

Switching Katana directly to the new format silently treats every legacy cookie as anonymous: Katana's secure data format catches the decryption exception and returns `null`. The reference implementation therefore:

- Writes only the new shared format.
- Reads the new format first.
- On a `null` result, reads the legacy Katana format using `IAppBuilder.CreateDataProtector`. This deliberately rebuilds Katana's default `"v1"` purpose triple; it is the only place `"v1"` is legitimate, and changing it to `"v2"` silently disables the fallback.
- Reads both Katana's legacy `chunks:N` cookie layout and the Interop/Core `chunks-N` layout while writing only the new layout through the existing System.Web-aware cookie writer.
- Treats chunk markers as untrusted input: it accepts at most 50 chunks, rejects writes above that bound, and stops deletion at the first missing chunk. The write-side bound is a deliberate behavior change from stock Katana, which never throws here: a ticket that needs more than 50 chunks (roughly 200 KB, reachable with large role sets, and ASP.NET Core does not compress authentication cookies) throws from inside the response grant and surfaces as a 500 on sign-in. Verify the largest real claim set against the bound before deploying, and reduce claim volume rather than raising the cap.
- Marks a successful legacy read.
- Calls `SignIn(context.Properties, context.Identity)` during validation to force a new-format cookie. `ReplaceIdentity` alone does not request a rewrite.

The agent cannot perform the following sequence: it requires deployments, elapsed time, and production telemetry. Write the fallback reader, then surface these as required operator steps in the pull request description and stop. Do not mark the migration complete because the code landed, and do not skip ahead to opening Core routes.

1. **Framework fallback:** deploy the dual-format reader while all traffic still reaches Framework.
2. **Transition window:** wait at least one complete cookie lifetime and monitor fallback hits.
3. **Open Core routes:** route authenticated endpoints to Core only after active legacy cookies have been rewritten or expired.
4. **Retire fallback:** remove the legacy ticket reader and the transition validation callback after fallback hits remain at zero for another cookie lifetime. Remove only the transition wrapper: the application's own `OnValidateIdentity` callback (for example `SecurityStampValidator.OnValidateIdentity`) was composed into it and must remain, or the application silently loses security-stamp, revocation, disabled-account, and renewal checks. Set the reference manager's `AcceptLegacyChunks` to `false`. `Configure` constructs the manager internally, so reach it by casting `options.CookieManager` to `TransitionChunkingCookieManager` after the call, or change the constructor default in your copy of the file. Keep its System.Web-aware writer when MVC and OWIN both emit cookies; use the direct Interop manager only after proving the response never mixes those write paths.

A deployment slot does not replace this ordering because the browser sends the same legacy cookie to every slot. Create a dated cleanup task when deploying the fallback so the legacy reader is not left in place indefinitely.

### Step 5: Preserve Route Invariants

- Keep each form-rendering GET and its POST on one host. Framework and Core anti-forgery token serializers are incompatible even with a shared key ring.
- Keep login, logout, registration, MFA, external-provider challenges, callbacks, and the temporary external cookie on Framework until identity endpoints migrate as one unit.
- Do not assume shared cookie keys also unify TempData, confirmation tokens, anti-forgery, or ViewState. Their purposes and wire formats differ.
- Test large claim sets. Katana's default chunk marker (`chunks:N`) differs from the Interop/Core marker (`chunks-N`), and ASP.NET Core does not compress authentication cookies.
- Keep authorization outcomes equivalent, including redirects, challenges, 401/403 status codes, and required headers.
- Do not open production Core routes until the YARP front door trusts only configured forwarded-header sources and has equivalent TLS, upload, request-size, timeout, and streaming behavior.

#### Optional MachineKey Replacement

`Microsoft.AspNetCore.DataProtection.SystemWeb` reroutes Framework `MachineKey.Protect/Unprotect` callers through Data Protection, but is not required for shared authentication cookies. Do not present it as a cookie-sharing prerequisite.

When the application separately chooses MachineKey replacement, install `Microsoft.AspNetCore.DataProtection.SystemWeb` 2.3.11 and configure both required `machineKey` attributes plus a Data Protection startup type:

```xml
<system.web>
  <machineKey
    compatibilityMode="Framework45"
    dataProtectorType="Microsoft.AspNetCore.DataProtection.SystemWeb.CompatibilityDataProtector, Microsoft.AspNetCore.DataProtection.SystemWeb" />
</system.web>
<appSettings>
  <add key="aspnet:dataProtectionStartupType"
       value="Application.SharedDataProtectionStartup, Application" />
</appSettings>
```

The startup type must persist to the same shared ring and configure explicit at-rest encryption. MachineKey replacement and cookie sharing can coexist because the cookie configuration explicitly replaces Katana's ticket format.

If selected for other reasons, plan for pre-deployment artifacts to become unreadable: temporary external-login cookies, open anti-forgery forms, TempData, confirmation links, and WebForms ViewState. It still does not make Framework and Core TempData or anti-forgery formats mutually readable.

### Step 6: Validate and Retire

Most of this needs two running hosts and a browser session, so the agent cannot execute it. Write it into the pull request description as a pre-cutover checklist the operator completes before each route family moves.

One subset does not need a running host and should be written as unit tests against the copied reference file: legacy and new ticket round-tripping, chunk assembly for both the `chunks:N` and `chunks-N` markers, and malformed or oversized marker handling are all pure functions of the cookie value.

Operator checklist, before moving a route:

- Sign in on Framework and authenticate on Core with the same cookie and claims.
- Sign in or renew on Core and authenticate on Framework.
- Present a pre-transition Katana cookie to Framework, confirm it is accepted, and confirm the response rewrites it in the shared format.
- Exercise that rewrite through the real Katana cookie middleware; direct `TicketDataFormat` and callback calls do not prove the response grant emits a cookie.
- Exercise normal cookies, legacy `chunks:N` cookies, and new `chunks-N` oversized cookies.
- Present malformed and oversized chunk-count markers; confirm reads and deletes perform bounded work.
- Exercise a response that writes both an MVC/System.Web cookie and the shared OWIN cookie; confirm neither write is lost.
- Reject or renew the same stale principal on both hosts.
- Compare every authorization policy and custom failure response on both hosts.
- Confirm GET/POST and external-login route ownership.
- Confirm the key ring is shared, encrypted at rest, and readable by both runtime identities.
- Keep route-level rollback available until parity tests pass.

## Success Criteria

Verifiable when this skill completes:

- The Framework reference compiles with C# 7.3 against the resolved Framework package versions.
- Both hosts declare the same cookie name, scheme, purpose triple, application name, and shared key-ring configuration.
- The Framework host writes only the new shared format and reads new format first, legacy second.
- `UseAuthentication()` runs before `UseAuthorization()` in the Core pipeline.
- No form-rendering GET is separated from its POST across hosts, and login, logout, registration, MFA, and external-provider callbacks remain on Framework.
- Unit tests cover ticket round-tripping, both chunk markers, and malformed markers.
- A dated follow-up task exists to retire the legacy fallback after the monitored transition window. The fallback is still present and active when this skill completes.

Confirmed by the operator after deployment, not by the agent:

- Both hosts accept cookies issued by either host without a per-request authentication call.
- Existing active Katana sessions transition without forced re-login.
- Authorization outcomes, including redirects, challenges, and status codes, match on both hosts.
