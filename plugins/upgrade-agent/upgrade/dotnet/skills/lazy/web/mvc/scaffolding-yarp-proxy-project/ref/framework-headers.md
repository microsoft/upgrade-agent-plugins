# Framework-side companion (X-Forwarded-* module)

Read this when the .NET Framework app relies on the client's scheme, host, or IP —
`Request.IsSecureConnection`, `Url.Host`, `UserHostAddress`, redirects, or absolute links.
`app.UseForwardedHeaders()` only fixes the Core side; without this module the Framework backend
still reads the proxy's own scheme/host/IP off `Request.ServerVariables`. Installing it is a
required companion whenever the legacy app reads those values, not a troubleshooting-only step.

## Contents

- [When the Framework side needs this](#when-the-framework-side-needs-this)
- [The IHttpModule and registration](#the-ihttpmodule-and-registration)
## When the Framework side needs this

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

## The IHttpModule and registration

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
