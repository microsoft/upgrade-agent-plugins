# Remote authentication — the .NET Framework half

This project was scaffolded with `-EnableRemoteAuth`, so the **ASP.NET Core side is already
wired**: instead of validating credentials itself, it asks your .NET Framework app to authenticate
each request and adopts the principal it returns.

The Framework side is **not** done, and until it is, every authenticated request from this app
fails.

> **Why this README inlines code instead of pointing at a skill.** The companion skill,
> `migrating-mvc-system-web-adapters`, covers the Core half well but has no reference
> implementation for the server half. Rather than send you to a document that cannot finish the
> job, the snippet you need is reproduced below. Read that skill for the surrounding migration
> story; use this file for the wiring.

## What is already configured here

`Program.cs` chains `.AddRemoteAppClient(...)` and `.AddAuthenticationClient(isDefaultScheme:
false)` onto `AddSystemWebAdapters()`. `appsettings.json` carries:

| Setting | Meaning |
|---|---|
| `RemoteApp:Url` | Base URL of the .NET Framework app this proxy sits in front of. |
| `RemoteApp:ApiKey` | Shared secret. Must be the **same value** on both sides, and must parse as a GUID. |

The Framework app reads that same secret from a *differently named* setting
(`ConfigurationManager.AppSettings["RemoteAppApiKey"]`). That is not a mistake to fix — the two
hosts use different configuration systems, so the key names are independent by design. **Only the
value has to match.**

> **Do not leave the API key in `appsettings.json` for anything but local development.** On this
> side use `dotnet user-secrets set "RemoteApp:ApiKey" "<guid>"`, and on the Framework side use a
> protected configuration section or your deployment's secret store.

## What you still have to do on the .NET Framework app

**1. Add the package.** Reference `Microsoft.AspNetCore.SystemWebAdapters.FrameworkServices`.

**2. Register the host.** In `Global.asax.cs` `Application_Start` (or wherever your startup lives):

```csharp
HttpApplicationHost.RegisterHost(b => b.AddSystemWebAdapters()
    .AddProxySupport(o => o.UseForwardedHeaders = true)
    .AddRemoteAppServer(o => o.ApiKey = ConfigurationManager.AppSettings["RemoteAppApiKey"])
    .AddAuthenticationServer());
```

**3. Register the module** in `Web.config`:

```xml
<system.webServer>
  <modules>
    <add name="SystemWebAdapterModule"
         type="Microsoft.AspNetCore.SystemWebAdapters.SystemWebAdapterModule, Microsoft.AspNetCore.SystemWebAdapters.FrameworkServices"
         preCondition="managedHandler" />
  </modules>
</system.webServer>
```

**4. Add the API key** to `<appSettings>`:

```xml
<appSettings>
  <add key="RemoteAppApiKey" value="<the same GUID as RemoteApp:ApiKey>" />
</appSettings>
```

The value **must parse as a GUID**. A non-GUID key is rejected on the first request the proxy
authenticates — not at startup. `AddRemoteAppServer` registers its options with
`.ValidateDataAnnotations()` and no `.ValidateOnStart()`, and the only code that reads them is the
per-request module, so the Framework host starts clean and looks healthy until the first sign-in.
Do not read a successful startup as proof the key is valid.

## The footgun: `[Authorize]` alone is not enough

This is the single most common way this feature is misconfigured. It fails **closed** — the
request is rejected rather than served, but with a confusing 500 rather than a 401.

The Core side deliberately registers remote auth as a **non-default** scheme
(`isDefaultScheme: false`). That is a security control: this app fronts a catch-all
`MapForwarder` route, and if remote auth were the default scheme, *every* forwarded request would
make a remote authentication call to the Framework app — which is about to authenticate that
request itself. That double-authenticates each request and can put the two apps in a redirect loop.

The cost of that choice is that a migrated endpoint must **name the scheme explicitly**:

```csharp
[Authorize(AuthenticationSchemes = RemoteAppAuthenticationDefaults.AuthenticationScheme)]
public IActionResult Secret() => View();
```

A plain `[Authorize]` falls back to the default scheme — and there is no default scheme, so it
sees an anonymous user and denies. The denial then tries to issue a challenge, finds no default
challenge scheme either, and throws:

```
System.InvalidOperationException: No authenticationScheme was specified,
and there was no DefaultChallengeScheme found.
```

So the symptom is an **HTTP 500 on every endpoint carrying a plain `[Authorize]`**, not a 401 and
not a silent anonymous success. Nobody is let through — but if you are chasing that 500, the cause
is a missing `AuthenticationSchemes`, not a broken remote-auth connection.

> **Why there is no default scheme at all.** `isDefaultScheme: false` leaves `DefaultScheme`
> unset, and nothing puts it back. That second half is not free: ASP.NET Core 7 and later promote a
> lone registered scheme to be the default automatically, which would quietly undo the flag. The
> adapters currently prevent that by also registering an internal empty scheme, so two schemes are
> always present and the promotion never triggers. Read the guarantee as *no default scheme
> exists*, not as *there are two schemes* — the mechanism belongs to the adapters and may change;
> the fail-closed behavior is the contract. Either way, do not "tidy up" by pinning a default
> scheme here — its absence is what keeps forwarded requests from being re-authenticated.

> **Do not let this project's adapters package drift below `2.3.0`.** The empty scheme described
> above is not registered by every release: on CoreServices `2.0.0` only `Remote` exists, ASP.NET
> Core promotes it to the default, and every forwarded request begins making a remote authentication
> call — with no error, no warning and no log line. The scaffold refuses to wire remote auth below
> `2.3.0` for that reason, but a later pin (a central `Directory.Packages.props`, a downgrade to
> match another project) can still move it. If you need to confirm the control is on, add this after
> `builder.Build()` and check it once:
>
> ```csharp
> var schemes = app.Services
>     .GetRequiredService<Microsoft.AspNetCore.Authentication.IAuthenticationSchemeProvider>();
> Console.WriteLine(await schemes.GetDefaultAuthenticateSchemeAsync() is null
>     ? "OK - no default scheme"
>     : "BROKEN - remote auth is the default scheme; every forwarded request is authenticated");
> ```

The alternative is to make remote auth the default scheme and call `.ShortCircuit()` on the
forwarder route so forwarded requests bypass the authentication middleware entirely. Both work.
Naming the scheme on migrated endpoints is the less surprising of the two, and is what this
scaffold sets you up for.

## Checklist

- [ ] `FrameworkServices` package referenced by the Framework app
- [ ] `HttpApplicationHost.RegisterHost(...)` called at startup
- [ ] `SystemWebAdapterModule` registered in `Web.config`
- [ ] `RemoteAppApiKey` present, a valid GUID, identical to `RemoteApp:ApiKey`
- [ ] `RemoteApp:Url` points at the Framework app and is reachable from this host
- [ ] Every migrated `[Authorize]` endpoint names `RemoteAppAuthenticationDefaults.AuthenticationScheme`
- [ ] SystemWebAdapters CoreServices stays at `2.3.0` or newer — older releases silently make remote auth the default scheme
