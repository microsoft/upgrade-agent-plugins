# Targeting below net10.0

Read this only when a hosting or policy constraint forces the proxy onto net8.0 or net9.0.
`net10.0` or later is required for the unadapted templates; on a lower target the
forwarded-headers block must be adapted by hand as described here, and the script strips the
whole hardening set rather than ship a proxy that looks like a security boundary and is not.
Everything else in [Production hardening](../SKILL.md#production-hardening-required) applies unchanged.
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
aimed. If the target genuinely cannot move (hosting or policy constraint), use
[Manual scaffolding](manual-scaffold.md) for the copy steps and marker/configuration rules.
During its adaptation step, before building, change `KnownIPNetworks` to `KnownNetworks`,
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
`Microsoft.AspNetCore.HttpOverrides.IPNetwork` are the obsolete pair flagged in the main skill's [Configuration check](../SKILL.md#configuration-check--do-not-use-the-obsolete-forwarded-headers-api).
