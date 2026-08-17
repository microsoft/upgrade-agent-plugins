
//<hardening>
using Microsoft.AspNetCore.HttpOverrides;

//</hardening>
var builder = WebApplication.CreateBuilder(args);

//<hardening>
// Kestrel security policy (hardening). Suppresses the Server banner, pins TLS to 1.2/1.3, and
// binds the request-size cap from configuration. Timeout and data-rate limits are not bound —
// set those directly in this delegate if you need them.
builder.WebHost.ConfigureKestrel(options =>
{
    options.AddServerHeader = false;

    // TLS floor. Defaults to 1.2/1.3 rather than Kestrel's SslProtocols.None ("use the OS
    // default") because Windows Server 2016-2022 still enable TLS 1.0/1.1 by default, and this
    // proxy is the internet-facing edge for the legacy app. The pin can only narrow what the OS
    // permits -- a protocol disabled in SCHANNEL cannot be re-enabled from code -- so it never
    // weakens machine policy. Override with Kestrel:SslProtocols to adopt a newer protocol
    // (e.g. "Tls13") or to defer entirely to the OS ("None"), without editing code.
    var sslProtocols = builder.Configuration.GetValue<System.Security.Authentication.SslProtocols?>("Kestrel:SslProtocols")
        ?? (System.Security.Authentication.SslProtocols.Tls12 | System.Security.Authentication.SslProtocols.Tls13);
    options.ConfigureHttpsDefaults(https => https.SslProtocols = sslProtocols);

    // Kestrel does NOT bind its Limits from the "Kestrel" configuration section (only
    // endpoints, certificates, and a few top-level switches are bound), so a
    // Kestrel:Limits:MaxRequestBodySize entry in appsettings.json is otherwise ignored
    // silently. Bind it here so operators can size the cap without editing code.
    // MaxRequestBodySize defaults to 30,000,000 bytes (~28.6 MB); use a negative value to
    // remove the limit entirely (Kestrel models "no limit" as null).
    if (builder.Configuration.GetValue<long?>("Kestrel:Limits:MaxRequestBodySize") is long maxRequestBodySize)
    {
        options.Limits.MaxRequestBodySize = maxRequestBodySize < 0 ? null : maxRequestBodySize;
    }
});

//</hardening>
//<hardening>
// Forwarded headers (hardening). Behind the reverse proxy the app must recover the client's
// original scheme, host, and IP. Trust is fail-closed: only the proxies and networks listed
// in the "ForwardedHeaders" configuration section are honored (defaults to loopback only).
builder.Services.Configure<ForwardedHeadersOptions>(options =>
{
    // X-Forwarded-For/-Host/-Proto only. X-Forwarded-Prefix (included in ForwardedHeaders.All)
    // is deliberately excluded: it overwrites Request.PathBase and, unlike the host, the
    // middleware has no allow-list to validate it against — whatever arrives is applied as-is,
    // so a forwarded "/evil" relocates every generated link and redirect under that prefix.
    // This proxy fronts the app at the root, so it has nothing to gain from the header. Only add
    // the flag if the app is genuinely hosted under a sub-path, and strip any client-supplied
    // X-Forwarded-Prefix at the edge before doing so.
    options.ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedHost | ForwardedHeaders.XForwardedProto;
    options.KnownProxies.Clear();
    options.KnownIPNetworks.Clear();

    foreach (var proxy in builder.Configuration.GetSection("ForwardedHeaders:TrustedProxies").Get<string[]>() ?? [])
    {
        if (System.Net.IPAddress.TryParse(proxy, out var address))
        {
            options.KnownProxies.Add(address);
        }
    }

    foreach (var network in builder.Configuration.GetSection("ForwardedHeaders:TrustedNetworks").Get<string[]>() ?? [])
    {
        if (System.Net.IPNetwork.TryParse(network, out var ipNetwork))
        {
            options.KnownIPNetworks.Add(ipNetwork);
        }
    }

    // Fail-closed: an empty KnownProxies AND KnownIPNetworks makes the middleware honor
    // forwarded headers from ANY sender. If configuration trusts neither a proxy nor a
    // network, fall back to loopback so an untrusted origin is never believed.
    if (options.KnownProxies.Count == 0 && options.KnownIPNetworks.Count == 0)
    {
        options.KnownIPNetworks.Add(new System.Net.IPNetwork(System.Net.IPAddress.Loopback, 32));
        options.KnownIPNetworks.Add(new System.Net.IPNetwork(System.Net.IPAddress.IPv6Loopback, 128));
    }

    foreach (var host in builder.Configuration.GetSection("ForwardedHeaders:AllowedHosts").Get<string[]>() ?? [])
    {
        options.AllowedHosts.Add(host);
    }

    // Fail-closed: an empty AllowedHosts makes the middleware accept ANY X-Forwarded-Host, letting
    // a caller spoof the links this app generates. With no allow-list configured, stop honoring the
    // header rather than believing it.
    if (options.AllowedHosts.Count == 0)
    {
        options.ForwardedHeaders &= ~ForwardedHeaders.XForwardedHost;
    }

    // A negative value means "unlimited" (Kestrel and the forwarded-headers middleware both
    // model "no limit" as null), matching the MaxRequestBodySize convention above. The guard is
    // load-bearing: assigning a negative ForwardLimit makes ForwardedHeadersMiddleware allocate
    // an array of that length and throw OverflowException on EVERY request, including requests
    // carrying no X-Forwarded-* headers at all.
    if (builder.Configuration.GetValue<int?>("ForwardedHeaders:ForwardLimit") is int forwardLimit)
    {
        options.ForwardLimit = forwardLimit < 0 ? null : forwardLimit;
    }
});

//</hardening>
builder.Services.AddSystemWebAdapters();
builder.Services.AddHttpForwarder();

//<hardening>
// Authentication placeholder seam: registers the authentication services (scheme provider)
// so app.UseAuthentication() below does not throw at the first request. Configure the
// concrete scheme(s) here; this call is intentionally parameterless.
builder.Services.AddAuthentication();

//</hardening>
// Add services to the container.
builder.Services.AddControllersWithViews();

var app = builder.Build();

//<hardening>
// Recover the client's original scheme/host/IP from the proxy before any middleware inspects them.
app.UseForwardedHeaders();

// Response header scrubbing (hardening). AddServerHeader = false only suppresses this proxy's own
// Server banner -- YARP copies the backend's response headers through verbatim, so the app behind
// this proxy keeps advertising its stack (for example Server: Microsoft-IIS/10.0,
// X-Powered-By: ASP.NET). Strip those on the way out so the proxy does not leak what it fronts.
// Add any other header your backend exposes to this list.
app.Use(async (context, next) =>
{
    context.Response.OnStarting(static state =>
    {
        var headers = ((HttpResponse)state).Headers;
        headers.Remove("Server");
        headers.Remove("X-Powered-By");
        headers.Remove("X-AspNet-Version");
        headers.Remove("X-AspNetMvc-Version");
        return Task.CompletedTask;
    }, context.Response);

    await next(context);
});

//</hardening>
if (!app.Environment.IsDevelopment())
{
    app.UseHsts();
}

app.UseHttpsRedirection();
app.UseStaticFiles();

app.UseRouting();
//<hardening>
app.UseAuthentication();
//</hardening>
app.UseAuthorization();
app.UseSystemWebAdapters();

app.MapDefaultControllerRoute();
app.MapForwarder("/{**catch-all}", app.Configuration["ProxyTo"]!).Add(static builder => ((RouteEndpointBuilder)builder).Order = int.MaxValue);

app.Run();
