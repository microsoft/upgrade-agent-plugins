//<hardening>
using Microsoft.AspNetCore.HttpOverrides;

//</hardening>
//<sharedcookie>
// A using directive must precede every top-level statement, so the shared-cookie block's one
// non-implicit namespace is declared here rather than beside the code that needs it. It sits in
// its own 'sharedcookie' region -- deliberately NOT in 'hardening' -- because a sub-net10
// shared-cookie scaffold strips the hardening, and taking this using with it would fail the
// build with CS0103 in precisely the configuration shared cookies exist to support.
using Microsoft.AspNetCore.DataProtection;

//</sharedcookie>
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
//<swadefault>
builder.Services.AddSystemWebAdapters();
//</swadefault>
//<remoteauth>
// Remote authentication (Stage 1 interop). Instead of validating credentials itself, this app
// asks the .NET Framework app to authenticate each request and returns the resulting principal,
// so both apps agree on who the user is during the migration.
//
// This REPLACES the plain AddSystemWebAdapters() call above rather than adding to it: the
// registration is a fluent chain, and a marker region can only insert lines, never extend a
// statement that sits outside it. Exactly one AddSystemWebAdapters() is emitted either way.
//
// See README.REMOTEAUTH.md next to this project for the .NET Framework half; the API key must be
// the same GUID on both sides.
// Validated before the options delegate below, which is evaluated lazily: an unfilled placeholder
// would otherwise not surface until the first request this proxy tries to route, so the app binds
// its port, reports healthy, and then throws UriFormatException mid-flight. Failing here stops the
// host at startup, where the operator is still watching.
ArgumentException.ThrowIfNullOrWhiteSpace(builder.Configuration["RemoteApp:Url"], "RemoteApp:Url");
ArgumentException.ThrowIfNullOrWhiteSpace(builder.Configuration["RemoteApp:ApiKey"], "RemoteApp:ApiKey");

builder.Services.AddSystemWebAdapters()
    .AddRemoteAppClient(options =>
    {
        options.RemoteAppUrl = new Uri(builder.Configuration["RemoteApp:Url"]!);
        options.ApiKey = builder.Configuration["RemoteApp:ApiKey"]!;
    })
    // isDefaultScheme: false is a security control, not a performance tweak. As the default
    // scheme, remote auth would fire on EVERY request -- including the catch-all forwarded ones
    // below, which the Framework app is about to authenticate anyway. That double-authenticates
    // each request and can produce a redirect loop between the two apps. Migrated endpoints opt
    // in explicitly instead; see the note on MapForwarder near the end of this file.
    .AddAuthenticationClient(isDefaultScheme: false);
//</remoteauth>
builder.Services.AddHttpForwarder();

//<authseam>
// Authentication placeholder seam: registers the authentication services (scheme provider)
// so app.UseAuthentication() below does not throw at the first request. Configure the
// concrete scheme(s) here; this call is intentionally parameterless.
builder.Services.AddAuthentication();

//</authseam>
//<sharedcookie>
// Shared cookie authentication (Stage 2 interop). This app and the .NET Framework app read and
// write the SAME authentication cookie, so a user who signs in on either side is signed in on
// both, with no redirect and no second login.
//
// Two things must line up, and each one fails SILENTLY if it does not:
//
//   1. A shared Data Protection key ring. The ticket is encrypted, so this app can only read a
//      Framework-issued cookie if both apps use the same keys and the same application name.
//      SetApplicationName is what pins the purpose string; change it on one side only and every
//      ticket stops decrypting.
//   2. The same cookie NAME and the same SCHEME name. ASP.NET Core derives the ticket's purpose
//      from the scheme name, so the scheme registered here must equal the Framework app's
//      AuthenticationType. Cookie.Name must equal the Framework app's cookie name -- Core's
//      default is ".AspNetCore." followed by the scheme name, which matches nothing a Katana app
//      has ever written, and the symptom is simply that the user appears signed out.
//
// See README.SHAREDCOOKIE.md next to this project for the .NET Framework half.
//</sharedcookie>
//<dpfilesystem>
// Key ring topology: a directory both hosts can read, protected by an X.509 certificate whose
// private key both hosts hold. Point this at the ring the .NET Framework app already uses -- a
// path that does not exist yet is silently created and populated with a NEW ring, which decrypts
// nothing the other app wrote and reports no error.
// Validated up front so every unfilled placeholder fails the same way. Left alone the failure modes
// are inconsistent: an empty key-ring path or thumbprint throws from deep inside the framework, but
// a blank application name is accepted and silently pins a purpose string the .NET Framework half
// does not share -- every ticket then fails to decrypt, with nothing logged.
ArgumentException.ThrowIfNullOrWhiteSpace(builder.Configuration["SharedDP:KeyRingPath"], "SharedDP:KeyRingPath");
ArgumentException.ThrowIfNullOrWhiteSpace(builder.Configuration["SharedDP:CertificateThumbprint"], "SharedDP:CertificateThumbprint");
ArgumentException.ThrowIfNullOrWhiteSpace(builder.Configuration["SharedDP:ApplicationName"], "SharedDP:ApplicationName");

builder.Services.AddDataProtection()
    .PersistKeysToFileSystem(new DirectoryInfo(builder.Configuration["SharedDP:KeyRingPath"]!))
    .ProtectKeysWithCertificate(builder.Configuration["SharedDP:CertificateThumbprint"]!)
    .SetApplicationName(builder.Configuration["SharedDP:ApplicationName"]!);

//</dpfilesystem>
//<dpazureblob>
// Key ring topology: an Azure Storage blob, protected by a key in Azure Key Vault. This is the
// shape a multi-instance or multi-slot deployment needs, because instances share the blob rather
// than a local disk. Both hosts authenticate with DefaultAzureCredential, so each needs an
// identity granted "Storage Blob Data Contributor" on the blob and "Key Vault Crypto User" on the
// key. Point this at the blob the .NET Framework app already populates: the container must exist,
// and a blob that is absent or empty is silently populated with a NEW ring, which decrypts nothing
// the other app wrote and reports no error.
// Validated up front for the same reason as the filesystem topology above: an empty ring URI or key
// identifier throws from deep inside the framework, but a blank application name is accepted and
// produces a ring the .NET Framework half cannot share.
ArgumentException.ThrowIfNullOrWhiteSpace(builder.Configuration["SharedDP:KeyRingUri"], "SharedDP:KeyRingUri");
ArgumentException.ThrowIfNullOrWhiteSpace(builder.Configuration["SharedDP:KeyVaultKeyId"], "SharedDP:KeyVaultKeyId");
ArgumentException.ThrowIfNullOrWhiteSpace(builder.Configuration["SharedDP:ApplicationName"], "SharedDP:ApplicationName");

builder.Services.AddDataProtection()
    .PersistKeysToAzureBlobStorage(
        new Uri(builder.Configuration["SharedDP:KeyRingUri"]!),
        new Azure.Identity.DefaultAzureCredential())
    .ProtectKeysWithAzureKeyVault(
        new Uri(builder.Configuration["SharedDP:KeyVaultKeyId"]!),
        new Azure.Identity.DefaultAzureCredential())
    .SetApplicationName(builder.Configuration["SharedDP:ApplicationName"]!);

//</dpazureblob>
//<sharedcookie>
// Neither AddAuthentication nor AddCookie rejects an empty scheme, and an empty cookie name is
// accepted too -- so an unfilled placeholder produces a host that starts, serves traffic and
// authenticates nobody, with nothing in any log. That is the single most likely way this feature
// is mis-deployed, so it fails loudly at startup instead.
ArgumentException.ThrowIfNullOrWhiteSpace(builder.Configuration["SharedCookie:Scheme"], "SharedCookie:Scheme");
ArgumentException.ThrowIfNullOrWhiteSpace(builder.Configuration["SharedCookie:Name"], "SharedCookie:Name");

builder.Services.AddAuthentication(builder.Configuration["SharedCookie:Scheme"]!)
    .AddCookie(builder.Configuration["SharedCookie:Scheme"]!, options =>
    {
        options.Cookie.Name = builder.Configuration["SharedCookie:Name"]!;

        // This app only reads the shared cookie -- the .NET Framework app issues and renews it.
        // SlidingExpiration defaults to true, which would let this app re-issue the cookie once a
        // ticket passes the halfway point of its window. A browser never sends Domain, Path,
        // SameSite or Secure back, so a re-issue can only use the values configured here: with
        // only Name set, the Framework app's cookie would be silently rewritten to host-only,
        // SameSite=Lax, Secure=SameAsRequest. A cookie scoped to ".example.com" for subdomain SSO
        // would stop reaching its siblings and sign the user out of them, with nothing logged.
        options.SlidingExpiration = false;
    });

//</sharedcookie>
// Add services to the container.
builder.Services.AddControllers();

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
if (app.Environment.IsDevelopment())
{
    // Swagger can be added later if needed
}

app.UseHttpsRedirection();
//<authpipeline>
app.UseAuthentication();
//</authpipeline>
app.UseAuthorization();
app.UseSystemWebAdapters();

app.MapControllers();
//<remoteauth>
// Remote-auth interplay with the catch-all forwarder below. Requests that fall through to the
// Framework app must NOT trigger a remote-auth call from here: the Framework app authenticates
// them itself, so doing it first double-authenticates every forwarded request and can bounce the
// two apps between each other in a redirect loop.
//
// AddAuthenticationClient(isDefaultScheme: false) above is what prevents that, and it has a
// consequence worth stating plainly: because the remote scheme is NOT the default, an endpoint
// migrated onto this app authenticates only if it names the scheme explicitly --
//
//     [Authorize(AuthenticationSchemes = RemoteAppAuthenticationDefaults.AuthenticationScheme)]
//
// A plain [Authorize] does NOT fall through as an anonymous success. It denies, then tries to
// challenge, finds no default challenge scheme either, and throws -- so the endpoint returns 500
// ("No authenticationScheme was specified, and there was no DefaultChallengeScheme found").
// That is fail-closed: nobody gets in. The misleading part is only the status code.
//
// There is no default scheme at all: isDefaultScheme: false leaves DefaultScheme unset, and the
// adapters currently keep it that way by also registering an internal empty scheme, which stops
// .NET 7+ from auto-promoting a lone scheme to the default. The mechanism is theirs and may
// change; the absence of a default scheme is the contract. Do not pin one here to "fix" the 500.
//
// The alternative is to keep remote auth as the default scheme and call .ShortCircuit() on the
// forwarder route below so forwarded requests bypass the auth middleware; naming the scheme on
// migrated endpoints is the less surprising of the two.
//</remoteauth>
app.MapForwarder("/{**catch-all}", app.Configuration["ProxyTo"]!).Add(static builder => ((RouteEndpointBuilder)builder).Order = int.MaxValue);

app.Run();
