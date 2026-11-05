# Troubleshooting

Read this when a scaffolded proxy misbehaves at build or runtime — 502s, a project that will
not build, requests that are not forwarded, or an auth-interop path that appears to sign nobody
in. Each row pairs a symptom with its likely cause and fix.
If the scaffolded project doesn't work, tell the user to check:

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| Proxy returns 502/connection refused | `ProxyTo` URL is wrong or old app isn't running | Verify URL in `launchSettings.json` matches old app's actual URL; start old app first |
| New project won't build | Wrong TFM or package versions | Check `TargetFramework` matches installed SDK; verify package versions are compatible |
| `CS1061 'ForwardedHeadersOptions' does not contain 'KnownIPNetworks'` | Unadapted forwarded-headers code below net10.0 | Prefer `-TargetFramework net10.0` or newer; if a hosting/policy constraint forces net8.0/net9.0, complete the [manual adaptation](older-targets.md) before building |
| Requests not forwarded | YARP middleware not registered | Check `Program.cs` has `AddHttpForwarder()` and `MapForwarder()` |
| Controllers return 404 | Routes not configured | Ensure `MapDefaultControllerRoute()` (MVC) or `MapControllers()` (WebAPI) is in `Program.cs` |
| Framework app sees `http`/proxy IP instead of client scheme/IP | Forwarded headers not honored on one side | Confirm `UseForwardedHeaders()` is the first middleware on the Core side **and** the Framework-side IHttpModule rewrites server variables (see [Production hardening](../SKILL.md#production-hardening-required)); verify the proxy's IP is in `TrustedProxies`/`TrustedNetworks` |
| Redirect loop or wrong scheme | Real proxy IP not trusted, so headers are ignored | Add the proxy address to `ForwardedHeaders:TrustedProxies`/`TrustedNetworks` in `appsettings.json` |
| Links/redirects use the internal host instead of the public one | `X-Forwarded-Host` is ignored because `ForwardedHeaders:AllowedHosts` is empty (fail-closed by design) | Add the public hostname(s) to `ForwardedHeaders:AllowedHosts`, or re-scaffold with `-AllowedForwardedHosts` |
| `_MigrateToProjectGuid` missing | Script couldn't find GUID in solution | Manually find the project GUID in .sln/.slnx and add the property to old .csproj |
| Shared cookie: user signs in on the old app but the new app shows them signed out | Only the ASP.NET Core half of the interop is wired | Complete the .NET Framework half — see `README.SHAREDCOOKIE.md` in the new project (script path only; the tool path writes none) and [Authentication interop](../SKILL.md#authentication-interop) |
| Shared cookie: still signed out after both halves are wired | One of the four values does not match | Check in order: cookie name (is the browser sending it to both hosts?), scheme name vs the Framework `AuthenticationType`, Data Protection application name, then key ring/certificate access. Every mismatch produces this same symptom with no error |
| Remote auth: `[Authorize]` endpoint returns 500 with "No authenticationScheme was specified, and there was no DefaultChallengeScheme found" | The remote scheme is not the default, by design, and a plain `[Authorize]` has nothing to fall back to | Add `[Authorize(AuthenticationSchemes = RemoteAppAuthenticationDefaults.AuthenticationScheme)]` — see the [remote-auth footgun](auth-setup.md). Do not "fix" it by pinning a default scheme |
| Remote auth: the authenticated request fails or times out reaching the old app | The .NET Framework half is not wired, or `RemoteApp:Url` is unreachable from the new app | Complete the .NET Framework half — on the script path see `README.REMOTEAUTH.md` in the new project, which inlines the server-side registration; on the tool path there is no README, so follow `migrating-mvc-system-web-adapters` |
| Remote auth: Framework app rejects the key at the first sign-in (not at startup) | `RemoteAppApiKey` is not a GUID, or differs between the two apps | Both sides must carry the identical GUID; the script rejects a non-GUID `-RemoteAppApiKey`. A clean Framework startup does not mean the key is valid — it is only read per request |
| App starts then crashes reading configuration | `appsettings.json` is not valid JSON — usually an unescaped `\` in a Windows path | Escape backslashes (`"C:\\keys\\app"`). `dotnet build` never parses `appsettings.json`, so a successful build proves nothing here |
