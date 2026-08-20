---
name: migrating-mvc-authentication
description: >
  Migrates ASP.NET MVC and Web API authentication and authorization to ASP.NET Core, covering
  Forms Authentication, Membership providers, Windows Authentication, token-based auth, authorization
  rules, and anti-forgery tokens. Use when upgrading projects that use FormsAuthentication,
  SqlMembershipProvider, SimpleMembership, Windows auth, OWIN OAuth, custom IPrincipal, role
  providers, ClaimsPrincipal.Current, machineKey, or web.config authorization rules. Also triggers
  for auth migration, login migration, cookie ticket conversion, password rehash strategy, and
  Authorize attribute differences.
metadata:
  traits: .NET|CSharp|VisualBasic|DotNetCore
  discovery: lazy
---

# ASP.NET MVC Authentication and Authorization Migration

## Overview

Migrate authentication and authorization from ASP.NET MVC/Web API to ASP.NET Core. This is the highest-risk area of any ASP.NET migration because wrong decisions produce security vulnerabilities, not compiler errors. Multiple migration paths exist depending on the authentication mechanism used — assess first, then apply the correct path.

> **Related skills:** For side-by-side Katana/ASP.NET Core shared cookies, see `sharing-authentication-cookies-katana-interop`. For ASP.NET Identity (UserManager, SignInManager, IdentityDbContext), see `migrating-aspnet-identity`. For OWIN cookie auth, see `migrating-owin-cookie-auth`. For OWIN OAuth/JWT, see `migrating-owin-oauth-to-jwt`. For OWIN OpenID Connect, see `migrating-owin-openid-connect`. For ADAL to MSAL, see `migrating-adal-to-msal`.

## Workflow

```
Migration Progress:
- [ ] Step 1: Assess authentication mechanisms
- [ ] Step 2: Migrate authentication configuration
- [ ] Step 3: Migrate sign-in and sign-out calls
- [ ] Step 4: Migrate membership and user stores
- [ ] Step 5: Migrate authorization rules
- [ ] Step 6: Migrate anti-forgery tokens
- [ ] Step 7: Remove legacy references
- [ ] Step 8: Build and verify
```

### Step 1: Assess Authentication Mechanisms

Scan the project to determine which authentication mechanisms are in use. Check these locations:

- `web.config`: `<authentication mode="...">`, `<membership>`, `<roleManager>`, `<machineKey>`, `<authorization>`
- `Global.asax` / `Startup.cs` / `Startup.Auth.cs`: OWIN middleware registration
- Controllers and views: `FormsAuthentication.*`, `Membership.*`, `Roles.*`, `User.Identity.*`
- Custom classes: `IPrincipal`, `IIdentity`, `MembershipProvider`, `RoleProvider` implementations

Determine the deployment model before choosing a migration path:

- **Full cutover:** the Framework host stops serving requests when the Core host starts. Continue with the replacement paths below.
- **Side-by-side:** both hosts serve the same users during an incremental migration. Establish cross-app identity before migrating authenticated routes. The **Cross-App Cookie Authentication** upgrade option chooses the mechanism: `sharing-authentication-cookies-katana-interop` when it is **Shared Cookie (Data Protection interop)**, and `migrating-mvc-system-web-adapters` for **Remote Authentication** — the latter only while the **System.Web Adapters** option is **Use System.Web Adapters**, which is what loads that skill. Do not load the adapters skill for remote authentication when System.Web Adapters is **Direct Migration to ASP.NET Core APIs**; that would impose the whole shim overlay on a user who declined it. The interop skill takes precedence over the full-cutover cookie replacement guidance below.

This gate applies whenever the deployment model is side-by-side **and** a .NET Framework host in
the solution still authenticates browser requests with a cookie. Do not condition it on a
**Cross-App Cookie Authentication** value appearing in the confirmed selections. Under either
confirmed value the Core host takes its identity from the Framework host, and under *no*
confirmed value the Framework host is still the one issuing the cookie — with
`migrating-mvc-system-web-adapters` wiring remote authentication as its side-by-side default
wherever that skill actually establishes the remote app connection. All of those states want
the same thing from this skill: the
Core host must not mint a competing cookie of its own. Gating on the confirmed set instead
would leave the commonest absence case registering a Core cookie *and* receiving a remote
authentication client — authenticating every request twice, with the redirect-loop risk the
**Interactions** rules exist to prevent.

A side-by-side migration whose Framework host does not authenticate browser requests with a
cookie — a Windows-authenticated app, an API-only host, an anonymous one — is not covered by
this gate and continues through the paths below normally.

If the Core host turns out to have no way to obtain identity from the Framework host at all,
that is a gap to report, not a reason to lift this gate. Registering a Core-issued cookie does
not give the Core host the user's existing session; it gives it a second, unrelated one.

There is exactly one release. If the operator, answering a conflict this migration reported,
states that a session reset is acceptable — signed-in users signing in again at the host
boundary — the gate lifts and the Core host registers its own cookie through the normal paths
below. That has to be an explicit answer to a question that was actually put to them. Do not
read it out of a missing **Cross-App Cookie Authentication** value, out of no mechanism being
available, or out of risk prose written for a human reader: silence is not consent to sign every
user out, which is the whole reason absence maps to a default instead. Say in the migration
notes that the reset was accepted and that the resulting Core cookie is a second, unrelated
session, so the decision is visible to whoever reads the change later.

When the gate applies, the Framework host keeps issuing the authentication cookie. Skip:

- **Step 2A** and `migrating-owin-cookie-auth`, which register a Core-issued cookie scheme.
- **Step 3**, which rewrites `FormsAuthentication.SetAuthCookie` into `HttpContext.SignInAsync`
  on that scheme. With Step 2A skipped the scheme does not exist, and adding it back produces
  exactly the session reset the option exists to avoid. Sign-in and sign-out stay on the
  Framework host with the rest of the identity endpoints.
- The **cookie registration** inside `migrating-aspnet-identity`. `AddIdentity()` registers the
  Identity cookie schemes; use `AddIdentityCore()` where the Core host needs the user store
  without them.
- The **cookie and external-sign-in conversions** inside `migrating-owin-to-aspnet-core`. That
  skill rewrites `app.UseCookieAuthentication(...)` into `AddAuthentication().AddCookie(...)`
  and `app.UseExternalSignInCookie()` into `AddCookie()` plus an external provider. Both mint a
  Core-issued cookie. Its non-authentication work — the OWIN pipeline, middleware and startup
  conversion — is unaffected.
- The **sign-in cookie** in `migrating-owin-openid-connect`. That route pairs
  `.AddOpenIdConnect()` with `.AddCookie()` and makes the cookie the default scheme, which is a
  Core-issued cookie by another name. An external-provider handshake is an identity endpoint:
  leave the OpenID Connect challenge and its callback on the Framework host, to migrate later
  with the rest of the identity endpoints.
- The cookie-related removals in **Step 7** — see the note in that step. The Framework host is
  still issuing the cookie, so the code and configuration that issue it are still in use.

Then apply the rule for the mechanism in play:

- **Shared Cookie (Data Protection interop)** — `sharing-authentication-cookies-katana-interop`
  owns the cookie wiring and takes precedence over the full-cutover guidance below.
- **Remote Authentication**, where `migrating-mvc-system-web-adapters` actually establishes the
  remote app connection — that skill loads, it applies to this host, and the host clears the .NET
  Framework 4.7.2 floor its remote-app package requires. The Framework host stays the identity
  authority. Do not introduce a Core-issued cookie scheme by any route; a Core host that mints
  its own cookie has not implemented remote authentication.
- **Remote Authentication**, where nothing actually establishes it — no skill delivers that
  wiring step by step. Three cases land here: System.Web Adapters set to **Direct Migration to
  ASP.NET Core APIs**, which never loads that skill; a host that skill does not wire, such as an
  OWIN self-host with no System.Web application to shim; and a host pinned below the 4.7.2
  floor, where that skill reports a blocking conflict instead of wiring. The remote-auth packages
  are separable from the shim overlay, but this product delivers their setup only through
  `migrating-mvc-system-web-adapters`. Stop at that boundary: hold the authenticated routes on
  the Framework host, migrate the anonymous ones, and say plainly that the remote-auth wiring is
  not covered step by step here. Still do not substitute a Core cookie scheme. The pairing is
  valid, so do not resolve it by changing either option's value on your own — report it, and name
  what would actually unblock it: the operator can re-plan with **Use System.Web Adapters** where
  the host can use it, lift the pin, qualify the host for **Shared Cookie (Data Protection
  interop)**, wire the remote-app packages by hand, or state that a session reset is acceptable
  and take the release above.
- **No confirmed value** — treat it exactly as the two Remote Authentication cases above, and
  pick between them the same way: by asking whether `migrating-mvc-system-web-adapters` actually
  establishes the remote app connection, never by reading an option value. Where it does, its
  side-by-side default wires remote authentication and the two agree. Where it does not, the
  boundary rule applies unchanged. In both cases say plainly that no cross-app mechanism was
  confirmed, so the reader can see this followed a default rather than a choice. Do not read a
  session reset into the silence — but if the operator, once told that identity has no route
  across, states that a reset is acceptable, take the release above.

Unaffected by the gate: the membership, role-provider and password-hashing paths (Step 4),
Negotiate (Step 2B), and the authorization-policy work — they concern the user store and
access rules, not the cookie.

The **Success Criteria** at the end of this skill assume a full cutover; the bullets marked
*(full cutover only)* there do not apply under this gate. The Framework host keeps issuing
the cookie until the identity endpoints migrate as a unit.

Categorize findings into one or more paths:

| Signal | Migration Path |
|--------|---------------|
| `<authentication mode="Forms">`, `FormsAuthentication.*` | → Cookie Authentication (Step 2A) |
| `SqlMembershipProvider`, `SimpleMembership`, custom `MembershipProvider` | → ASP.NET Core Identity (Step 4) |
| `<authentication mode="Windows">` | → Negotiate Authentication (Step 2B) |
| OWIN OAuth/JWT middleware | → See `migrating-owin-oauth-to-jwt` |
| OWIN cookie middleware | → See `migrating-owin-cookie-auth` |
| OWIN OpenID Connect | → See `migrating-owin-openid-connect` |
| ASP.NET Identity (IdentityDbContext, UserManager) | → See `migrating-aspnet-identity` |

Projects often combine multiple mechanisms (e.g., Forms Auth + Membership + Role Provider). Apply each relevant path.

Under the side-by-side gate above, no route may leave the Core host issuing its own authentication cookie. Cookie Authentication (Step 2A) and the OWIN cookie route do not apply at all — the Framework host keeps issuing the cookie. Two routes in the table apply only in part, and the skip list above says which part: **Identity** migrates the user store and model only (`AddIdentityCore()`), never the cookie schemes or the Framework login controllers and `SignInManager` sign-in calls; **OpenID Connect** leaves the challenge, the callback and the session cookie on the Framework host. The remaining table routes — OAuth/JWT, Negotiate and Membership — are fully unchanged, since they concern bearer tokens, the user store or access rules rather than the browser cookie. The gate is not limited to this table: `migrating-owin-to-aspnet-core` is reached from the OWIN pipeline work rather than from a signal here, and the same rule applies to it — its pipeline conversion is fine, its cookie and external-sign-in conversions are not.

### Step 2: Migrate Authentication Configuration

#### Step 2A: Forms Authentication → Cookie Authentication

Replace Forms Authentication with ASP.NET Core cookie authentication. Register the service in `Program.cs`:

```csharp
// Old: web.config
// <authentication mode="Forms">
//   <forms loginUrl="~/Account/Login" timeout="30" slidingExpiration="true" />
// </authentication>

// New: Program.cs
builder.Services.AddAuthentication(CookieAuthenticationDefaults.AuthenticationScheme)
    .AddCookie(options =>
    {
        options.LoginPath = "/Account/Login";
        options.LogoutPath = "/Account/Logout";
        options.AccessDeniedPath = "/Account/AccessDenied";
        options.ExpireTimeSpan = TimeSpan.FromMinutes(30);
        options.SlidingExpiration = true;
    });
```

Add authentication middleware in the correct order:

```csharp
app.UseAuthentication();
app.UseAuthorization();
```

**Security note:** In a full cutover, old Forms Authentication cookie tickets are not compatible with ASP.NET Core cookies, so users are logged out unless a separate transition is implemented. Do not apply that session-reset assumption to a side-by-side migration under either interop mechanism: under **Shared Cookie (Data Protection interop)** use `sharing-authentication-cookies-katana-interop` to rewrite legacy cookies instead, and under **Remote Authentication** the Core host is not issuing its own cookie at all, so the reset does not apply there either.

**⚠️ machineKey migration:** `<machineKey>` in web.config is replaced by the Data Protection API. Key management is completely different. If the old app shared machine keys across servers for cookie decryption, configure Data Protection with a shared key ring:

```csharp
builder.Services.AddDataProtection()
    .PersistKeysToFileSystem(new DirectoryInfo(@"\\server\share\keys"))
    .ProtectKeysWithCertificate(keyEncryptionCertificate)
    .SetApplicationName("SharedAppName");
```

Use a certificate, Key Vault, or a shared DPAPI-NG descriptor for at-rest protection. Default per-machine/per-user DPAPI cannot protect a ring consumed by different hosts.

#### Step 2B: Windows Authentication → Negotiate Authentication

Replace web.config Windows auth with the Negotiate authentication handler:

```csharp
// Old: web.config
// <authentication mode="Windows" />

// New: Program.cs
builder.Services.AddAuthentication(NegotiateDefaults.AuthenticationScheme)
    .AddNegotiate();

builder.Services.AddAuthorization(options =>
{
    options.FallbackPolicy = options.DefaultPolicy;
});
```

Add the NuGet package `Microsoft.AspNetCore.Authentication.Negotiate`.

**Hosting differences:** Windows Authentication setup varies by host:
- **IIS (in-process):** Enable Windows Authentication in IIS site settings; no code changes beyond the service registration.
- **Kestrel:** Requires Negotiate handler configuration and may need SPN registration for domain environments.

`WindowsIdentity` is still accessible via `HttpContext.User.Identity as WindowsIdentity`, but access paths through `Thread.CurrentPrincipal` or `ClaimsPrincipal.Current` no longer work.

### Step 3: Migrate Sign-In and Sign-Out Calls

Replace `FormsAuthentication` static method calls with `HttpContext` extension methods. All ASP.NET Core equivalents are async.

```csharp
// OLD: FormsAuthentication.SetAuthCookie(username, isPersistent);
// NEW:
var claims = new List<Claim>
{
    new Claim(ClaimTypes.Name, username)
};
var identity = new ClaimsIdentity(claims, CookieAuthenticationDefaults.AuthenticationScheme);
var principal = new ClaimsPrincipal(identity);
await HttpContext.SignInAsync(
    CookieAuthenticationDefaults.AuthenticationScheme,
    principal,
    new AuthenticationProperties { IsPersistent = isPersistent });
```

```csharp
// OLD: FormsAuthentication.SignOut();
// NEW:
await HttpContext.SignOutAsync(CookieAuthenticationDefaults.AuthenticationScheme);
```

```csharp
// OLD: FormsAuthentication.RedirectToLoginPage();
// NEW (in a controller):
return Challenge();
// Or explicit redirect:
return Redirect("/Account/Login");
```

**⚠️ Async requirement:** All sign-in/sign-out calls are async in ASP.NET Core. Update controller action signatures to return `Task<IActionResult>`.

Replace `FormsAuthenticationTicket` custom data with additional claims on the `ClaimsIdentity`. Do not attempt to replicate the ticket format.

### Step 4: Migrate Membership and User Stores

#### SqlMembershipProvider / SimpleMembership → ASP.NET Core Identity

If the project uses `SqlMembershipProvider` or `SimpleMembership`, migrate to ASP.NET Core Identity. For detailed Identity migration (DbContext, UserManager, SignInManager), see `migrating-aspnet-identity`.

**Password hashing change:** ASP.NET Membership uses SHA-1 or SHA-256 hashed passwords. ASP.NET Core Identity uses PBKDF2 with HMAC-SHA256. Existing password hashes are incompatible. Implement a compatibility hasher that verifies old hashes and re-hashes on successful login:

```csharp
public class MembershipPasswordHasher : IPasswordHasher<ApplicationUser>
{
    private readonly PasswordHasher<ApplicationUser> _coreHasher = new();

    public string HashPassword(ApplicationUser user, string password)
    {
        return _coreHasher.HashPassword(user, password);
    }

    public PasswordVerificationResult VerifyHashedPassword(
        ApplicationUser user, string hashedPassword, string providedPassword)
    {
        // Try ASP.NET Core format first
        var result = _coreHasher.VerifyHashedPassword(user, hashedPassword, providedPassword);
        if (result != PasswordVerificationResult.Failed)
            return result;

        // Fall back to legacy Membership hash verification
        if (VerifyLegacyHash(hashedPassword, providedPassword))
            return PasswordVerificationResult.SuccessRehashNeeded;

        return PasswordVerificationResult.Failed;
    }

    private bool VerifyLegacyHash(string hashedPassword, string providedPassword)
    {
        // Implement legacy hash verification matching the old provider's algorithm
        // (SHA-1, SHA-256, or custom — check the old <membership> config for hashAlgorithmType)
        throw new NotImplementedException("Match the old provider's hash algorithm");
    }
}
```

Register the custom hasher:

```csharp
builder.Services.AddScoped<IPasswordHasher<ApplicationUser>, MembershipPasswordHasher>();
```

**⚠️ Security note:** The `VerifyLegacyHash` implementation must match the exact algorithm from the old `<membership>` configuration, including salt handling. Get this wrong and either all logins fail or password verification is insecure.

#### Custom MembershipProvider → Custom UserStore

If the project uses a custom `MembershipProvider`, implement `IUserStore<TUser>` and optionally `IUserPasswordStore<TUser>`:

```csharp
public class LegacyUserStore : IUserStore<ApplicationUser>, IUserPasswordStore<ApplicationUser>
{
    // Map old MembershipProvider methods to UserStore interface
    // GetUser → FindByIdAsync / FindByNameAsync
    // ValidateUser → handled by IPasswordHasher
    // CreateUser → CreateAsync
}
```

Replace `Roles.IsUserInRole(username, role)` with:

```csharp
// In a controller (synchronous check via ClaimsPrincipal):
User.IsInRole("Admin")

// Via UserManager (async):
await userManager.IsInRoleAsync(user, "Admin")
```

### Step 5: Migrate Authorization Rules

#### Web.config Authorization → Policy-Based Authorization

Replace `<authorization>` rules in web.config with ASP.NET Core authorization policies:

```xml
<!-- Old: web.config -->
<authorization>
  <allow roles="Admin,Manager" />
  <deny users="*" />
</authorization>
```

```csharp
// New: Program.cs
builder.Services.AddAuthorization(options =>
{
    options.FallbackPolicy = new AuthorizationPolicyBuilder()
        .RequireAuthenticatedUser()
        .Build();
});
```

#### Authorize Attribute Changes

`[Authorize(Roles = "Admin")]` works in both frameworks but resolves roles from different sources. Verify the role claim type matches:

```csharp
// If roles come from a custom claim type, configure it:
builder.Services.AddAuthentication()
    .AddCookie(options =>
    {
        options.ClaimsIssuer = "LegacyApp";
    });

// Or map during claims transformation:
builder.Services.AddTransient<IClaimsTransformation, LegacyRoleClaimsTransformation>();
```

**`[Authorize(Users = "...")]` is removed** in ASP.NET Core. Replace with a policy:

```csharp
// Old: [Authorize(Users = "admin,john")]
// New:
builder.Services.AddAuthorization(options =>
{
    options.AddPolicy("SpecificUsers", policy =>
        policy.RequireAssertion(context =>
            new[] { "admin", "john" }.Contains(
                context.User.Identity?.Name,
                StringComparer.OrdinalIgnoreCase)));
});

// On the controller or action:
[Authorize(Policy = "SpecificUsers")]
```

#### ClaimsPrincipal.Current Removal

`ClaimsPrincipal.Current` and `Thread.CurrentPrincipal` do not work in ASP.NET Core. Replace all usages:

```csharp
// Old (anywhere in code):
var user = ClaimsPrincipal.Current;

// New (in controllers):
var user = HttpContext.User;
// Or User property directly:
var user = User;

// New (in services — inject IHttpContextAccessor):
public class MyService
{
    private readonly IHttpContextAccessor _httpContextAccessor;
    public MyService(IHttpContextAccessor httpContextAccessor)
    {
        _httpContextAccessor = httpContextAccessor;
    }
    public ClaimsPrincipal GetCurrentUser() =>
        _httpContextAccessor.HttpContext?.User;
}
```

Register the accessor:

```csharp
builder.Services.AddHttpContextAccessor();
```

**⚠️ Security note:** `IHttpContextAccessor` returns null outside an HTTP request context (e.g., background tasks). Guard against null to avoid security bypass.

### Step 6: Migrate Anti-Forgery Tokens

ASP.NET Core uses a different anti-forgery token format. In a full cutover, old tokens are invalid after migration. In a side-by-side migration, shared authentication cookies do not make Framework and Core anti-forgery tokens interchangeable; keep each form's GET and POST on the same host.

**Razor views:**

```cshtml
@* Old (still works but tag helpers are preferred): *@
@Html.AntiForgeryToken()

@* New (automatic with form tag helper): *@
<form asp-action="Submit" asp-controller="Home" method="post">
    @* Anti-forgery token is auto-generated *@
</form>
```

**Validation attribute:** `[ValidateAntiForgeryToken]` works in both frameworks but the underlying token mechanism differs. No code change needed for the attribute, but existing tokens in user browsers will be rejected after deployment.

**Global anti-forgery (AutoValidateAntiforgeryToken):**

```csharp
// Apply to all POST actions globally:
builder.Services.AddControllersWithViews(options =>
{
    options.Filters.Add(new AutoValidateAntiforgeryTokenAttribute());
});
```

**SPA / AJAX scenarios:** Inject `IAntiforgery` to generate tokens for non-form requests:

```csharp
app.MapGet("/antiforgery/token", (IAntiforgery antiforgery, HttpContext context) =>
{
    var tokens = antiforgery.GetAndStoreTokens(context);
    return Results.Ok(new { token = tokens.RequestToken });
});
```

**Cookie name change:** Configure a custom cookie name if client code depends on it:

```csharp
builder.Services.AddAntiforgery(options =>
{
    options.Cookie.Name = "X-CSRF-TOKEN";
    options.HeaderName = "X-CSRF-TOKEN";
});
```

### Step 7: Remove Legacy References

Remove all legacy authentication references:

- Delete `<authentication>`, `<membership>`, `<roleManager>`, `<machineKey>`, and `<authorization>` sections from web.config (if web.config is retained for IIS configuration, keep only IIS-relevant sections)
- Remove `FormsAuthentication` namespace usages (`System.Web.Security`)
- Remove `Membership` and `Roles` static class usages
- Remove OWIN authentication startup code (`Startup.Auth.cs`) if fully migrated
- Remove NuGet packages: `Microsoft.AspNet.Membership.OpenAuth`, `Microsoft.AspNet.Identity.Owin`, `Microsoft.Owin.Security`

**Under the side-by-side gate near the top of this skill, this cleanup is limited to the
Core host.** The Framework host is still the cookie issuer, so on that host keep
`<authentication>`, `<machineKey>`, the `FormsAuthentication` / `System.Web.Security` usages
that Step 3 was skipped to preserve, the OWIN authentication startup, and `Microsoft.Owin.Security`.
Removing any of them breaks the mechanism the user confirmed: under **Shared Cookie (Data
Protection interop)** the `<machineKey>` and Katana middleware are what the shared key ring is
aligned against, and under **Remote Authentication** the Framework host has to keep
authenticating in order to answer the remote-app call. The membership, role-provider and
authorization cleanup is unaffected. Revisit this step when the identity endpoints migrate.

### Step 8: Build and Verify

1. Build the project and resolve all compilation errors
2. **Security-critical verifications:**
   - Unauthenticated requests to protected endpoints return 401/redirect to login
   - Authentication succeeds with valid credentials
   - For a full cutover, old session cookies are rejected rather than trusted accidentally
   - For side-by-side **Shared Cookie (Data Protection interop)**, legacy cookies are accepted only by the transition reader and rewritten in the shared format
   - For side-by-side **Remote Authentication**, the Framework host is still the only issuer: the Core host authenticates through the remote-app call and mints no cookie of its own, so there is no transition reader and no shared format to verify
   - Role-based and policy-based authorization enforces correctly
   - Anti-forgery validation rejects cross-site requests
   - `[AllowAnonymous]` endpoints remain accessible
3. If using Membership password rehashing, verify that a user with a legacy password hash can log in and that the hash is upgraded on success

## Troubleshooting

### "No authenticationScheme was specified"

Ensure `AddAuthentication(scheme)` is called with a default scheme. If multiple schemes are registered, set `DefaultAuthenticateScheme` and `DefaultChallengeScheme` explicitly.

### Users Logged Out After Deployment

For a full cutover without a transition reader, this is expected because ASP.NET Core cookie tickets are incompatible with Forms Authentication tickets. For a side-by-side Katana migration using **Shared Cookie (Data Protection interop)**, do not accept the logout as expected behavior; use `sharing-authentication-cookies-katana-interop` and validate that legacy cookies are rewritten. For side-by-side **Remote Authentication**, a logout at cutover means the Core host is authenticating locally instead of calling the Framework host — check the remote-app client wiring, not the cookie format.

### Legacy Passwords All Fail

The custom `IPasswordHasher` must match the exact hash algorithm, salt format, and encoding from the old Membership configuration. Check `<membership><providers><add passwordFormat="..." hashAlgorithmType="..." />` in the old web.config.

### Authorization Rules Not Applied

Web.config `<authorization>` rules are ignored by ASP.NET Core. All authorization must be configured through `AddAuthorization()` policies, `[Authorize]` attributes, or `RequireAuthorization()` on endpoints.

## Success Criteria

These assume a full cutover. Under the side-by-side gate near the top of this skill, the
bullets marked *(full cutover only)* do not apply at all — the Framework host remains the
cookie issuer until the identity endpoints migrate as a unit, so there is no Core-side
equivalent of them to satisfy.

- Authentication middleware registered in `Program.cs` with correct scheme and options *(full cutover only)*
- All `FormsAuthentication.*` calls replaced with `HttpContext.SignInAsync/SignOutAsync` *(full cutover only)*
- Membership provider replaced with ASP.NET Core Identity or custom `IUserStore` with password rehash support
- Authorization rules migrated from web.config to policy-based authorization
- `ClaimsPrincipal.Current` replaced with `HttpContext.User` or `IHttpContextAccessor`
- Anti-forgery tokens configured for the new middleware. This applies under the gate too: any host that serves a form needs its own anti-forgery configuration. Separately, in **any** side-by-side deployment a form's rendering GET and its POST must stay on the *same* host, because the token formats are not interoperable across hosts even with a shared key ring
- No legacy authentication namespaces (`System.Web.Security`) remain *(full cutover only)*
- Project builds without errors
- Protected endpoints reject unauthenticated requests
