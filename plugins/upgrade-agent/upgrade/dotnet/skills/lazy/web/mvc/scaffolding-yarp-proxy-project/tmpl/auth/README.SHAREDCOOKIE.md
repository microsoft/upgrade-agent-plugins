# Shared cookie authentication — the .NET Framework half

This project was scaffolded with `-EnableSharedCookieAuth`, so the **ASP.NET Core side is already
wired**: it registers a shared Data Protection key ring and a cookie handler that reads the same
cookie your .NET Framework app writes.

The Framework side is **not** done, and until it is, nothing works — the two apps will simply not
recognise each other's cookies.

## Two things this scaffold assumed

Neither was checked when the project was generated. If either is wrong, the proxy still compiles and
starts, and users simply appear signed out — with nothing in the logs at the level this project
configures by default (see *Why this fails silently* below for how to change that).

1. **Your Framework app authenticates with Katana/OWIN cookie middleware**, hosted under
   `Microsoft.Owin.Host.SystemWeb`. If it uses **classic Forms authentication** — a `<forms>`
   element in `Web.config`, typically an `.ASPXAUTH` cookie — this path cannot work. That ticket is
   encrypted with `machineKey` in a format ASP.NET Core does not read, and sharing the key ring does
   not change that. Either move the Framework app to Katana cookie middleware first, or re-scaffold
   with remote authentication (`-EnableRemoteAuth`) instead.
2. **Your Data Protection key ring is one of the two topologies this scaffold emits, and you passed
   the matching `-SharedKeyRingProvider`.** The generated `Program.cs` calls either
   `PersistKeysToFileSystem(...).ProtectKeysWithCertificate(...)` (`filesystem`, the default) or
   `PersistKeysToAzureBlobStorage(...).ProtectKeysWithAzureKeyVault(...)` (`azureblob`). Look at your
   generated `Program.cs` to see which one you got — the rest of this note applies to whichever it
   is. If your keys live somewhere else — **a database (`PersistKeysToDbContext`), Redis, or
   DPAPI-NG** — replace those two calls by hand with the matching persistence and protection APIs,
   keeping the application name and cookie settings identical on both sides.

## What is already configured here

`Program.cs` registers the Data Protection ring and the cookie scheme. `appsettings.json` carries
the values you passed on the command line. Three settings are always present:

| Setting | Meaning |
|---|---|
| `SharedDP:ApplicationName` | Pins the Data Protection purpose string. Must be identical on both sides. |
| `SharedCookie:Name` | The cookie name on the wire. Must match the Framework app exactly. |
| `SharedCookie:Scheme` | Must equal the Framework app's `AuthenticationType`. |

The remaining two describe where the ring lives, and depend on which provider you scaffolded with.

**`filesystem`:**

| Setting | Meaning |
|---|---|
| `SharedDP:KeyRingPath` | Directory holding the shared key ring. Both apps must read the same one. |
| `SharedDP:CertificateThumbprint` | X.509 certificate protecting the ring at rest. Both apps need the private key. |

**`azureblob`:**

| Setting | Meaning |
|---|---|
| `SharedDP:KeyRingUri` | Absolute URI of the blob holding the shared key ring. Both apps must point at the same blob. |
| `SharedDP:KeyVaultKeyId` | Absolute URI of the Key Vault key protecting the ring at rest. Both apps must use the same key. |

The Azure variant authenticates with `DefaultAzureCredential`, so it carries no secrets in
configuration — but that means each host needs an identity with **Storage Blob Data Contributor** on
the blob and **Key Vault Crypto User** on the key. Grant them before first run. A missing role does
**not** stop the host: Data Protection preloads the key ring from a hosted service at startup, and
when that load fails it swallows the exception, logs it, and lets startup continue anyway. The
symptom is the same silent sign-out as every other mismatch below. That startup log entry is the
single best diagnostic on this path — and this project's own log filter hides it by default. See
[Why this fails silently](#why-this-fails-silently) for the one setting that turns it on.

## What you still have to do

Follow the **`sharing-authentication-cookies-katana-interop`** skill. It carries the full
Framework-side procedure plus a reference implementation in its `ref/legacy.cs`, including the
`ChunkingCookieManager` and the exact ticket-format shim — details this README deliberately does
not duplicate, because getting them subtly wrong is worse than not starting.

At a high level the Framework app must:

1. Reference `Microsoft.Owin.Security.Interop`. On the `azureblob` topology it also needs
   `Azure.Extensions.AspNetCore.DataProtection.Blobs` and
   `Azure.Extensions.AspNetCore.DataProtection.Keys` — the same two packages this project now
   references — or it cannot call the persistence and key-protection methods step 2 asks for.
2. Persist its Data Protection ring to the **same** place this app reads — the same
   `SharedDP:KeyRingPath` and certificate, or the same `SharedDP:KeyRingUri` and
   `SharedDP:KeyVaultKeyId` — using the **same** application name.
3. Configure its cookie middleware with the `AspNetTicketDataFormat` interop shim so the ticket is
   written in the format ASP.NET Core reads.
4. Use the same cookie name, domain, and path.

## Why this fails silently

Almost every mismatch in this feature produces the same symptom — **the user just appears signed
out** — and nothing surfaces in the HTTP response. Two separate mechanisms swallow the error, which
is why it is so quiet:

- **At startup**, Data Protection preloads the key ring from a hosted service. If the ring cannot be
  reached it logs `Key ring failed to load during application startup.`, with the underlying
  exception attached, and lets the host start regardless.
- **On every request**, `SecureDataFormat.Unprotect` catches *all* exceptions and returns no ticket,
  so the cookie handler reports `FailedUnprotectingTicket` and the request simply runs anonymous.
  (Writing a ticket is not swallowed this way, but in this topology the .NET Framework app owns
  sign-in and this app only ever reads.)

**"Only ever reads" is enforced, not assumed.** The generated `AddCookie` block sets
`options.SlidingExpiration = false`, and that line is load-bearing rather than a preference. Left at
its default of `true`, the cookie handler re-issues the cookie as soon as a ticket passes the halfway
point of its window — turning this app into a writer without anyone asking it to. That matters
because a browser sends back only `name=value`: it never returns `Domain`, `Path`, `SameSite`, or
`Secure`, so a re-issue can only use the options configured *here*, and the only one configured here
is `Cookie.Name`. The Framework app's cookie would be quietly rewritten with ASP.NET Core's defaults
— host-only (`Domain` unset), `SameSite=Lax`, `Secure=SameAsRequest`.

Nothing breaks loudly when that happens. The ticket still decrypts and the user stays signed in on
this host, so the symptom shows up somewhere else entirely: a cookie your Framework app scoped to
`.example.com` for subdomain SSO stops reaching its siblings, and `SameSite=None` becomes `Lax`, so
it stops flowing on cross-site requests. If you are running the proxy below `net10.0`, add HTTPS to
the list — without `UseForwardedHeaders` the app cannot see the original scheme behind a
TLS-terminating load balancer, so `SameAsRequest` resolves to a cookie with no `Secure` flag.

Leave the line in place. If you genuinely want this app to renew the cookie, set the scope
explicitly — `options.Cookie.Domain`, `.Path`, `.SameSite`, and `.SecurePolicy` — to match whatever
the Framework app issues, and only then turn sliding expiration back on.

**"Reads" describes the cookie, not the key ring.** The two are separate, and conflating them will
mislead whoever reviews this app's permissions. This app never writes the *cookie*. It is, however,
a full participant in the shared Data Protection *key ring*: `AutoGenerateKeys` defaults to `true`,
so if the ring has no usable unexpired key when this host loads it, this host may generate the
successor and store it — which is exactly why the Azure variant above asks for **Storage Blob Data
Contributor** rather than a read-only role. That is normal web-farm behaviour: the new key is
wrapped with the same certificate or Key Vault key and uses the shared default algorithm, so the
.NET Framework app reads it too.

You can run this host with read-only access to the ring if your security review requires it, and
that is why the `filesystem` guidance below asks only for read. Nothing breaks: a failed key
generation is logged and falls back, and the .NET Framework app — which owns sign-in, and therefore
has to be able to write — generates the successor instead. Do not grant read-only to *both* hosts.

**The one exception, and it is the good kind.** On the `filesystem` topology, a
`SharedDP:CertificateThumbprint` that is **not installed in the store at all** — a typo, or a
certificate not yet deployed to this host — does *not* fail quietly. `ProtectKeysWithCertificate`
resolves the certificate eagerly, in the call itself, before the host is built:

```text
A certificate with the thumbprint '<value>' could not be found.
For more information go to https://aka.ms/aspnet/dataprotectionwarning
```

The host does not start and serves no request, so you find this immediately and do not need the
log-level change below. Do not confuse it with the case where the certificate **is** in the store
but the app-pool identity cannot read its **private key** — that resolves fine at startup and then
fails later at ring load, which *is* silent and is the case step 4 below is about.

**Make the startup entries visible before you debug anything else.** There are two of them and they
sit at *different* levels — the failure at `Information`, the success at `Debug` — both under
`Microsoft.AspNetCore.DataProtection`. The `appsettings.json` generated with this project sets
`"Microsoft.AspNetCore": "Warning"`, so by default neither survives the filter and you genuinely do
see nothing. Add this and restart:

```json
"Logging": {
  "LogLevel": {
    "Microsoft.AspNetCore.DataProtection": "Debug"
  }
}
```

`Debug` rather than `Information` on purpose: `Information` shows only the failure entry, and the
absence of a line is exactly what you cannot interpret here. With `Debug` you always get one of the
two, and that splits the problem in half:

- `Key ring failed to load during application startup.` — the app cannot reach the ring at all. The
  attached `Azure.Identity` or `Azure.RequestFailedException` names the reason; go to step 4.
- `Key ring with default key … was loaded during application startup.` — the ring loaded fine, so
  the fault is above it: the ring is the wrong one (step 5), or the ticket's purpose string does not
  match (steps 1-3). Nothing further is logged for either of those, at any level — a wrong ring is
  indistinguishable from the right one from inside this app, which is why the remaining steps are
  comparisons against the .NET Framework app rather than log reading.

When debugging, check in this order:

1. **Cookie name.** Is the browser actually sending the cookie to both hosts? Check the domain and
   path, not just the name.
2. **Scheme name vs `AuthenticationType`.** ASP.NET Core derives the ticket's purpose string from
   the scheme name. A different scheme name means a different purpose, which means the ticket
   cannot be decrypted even though the key ring is shared.
3. **Application name.** Same story: it is part of the purpose.
4. **Key ring access.** On `filesystem`, both app pool identities need read access to the ring
   directory *and* the certificate's private key. On `azureblob`, both identities need the two role
   assignments named above. The startup entry tells you directly whether this is your problem —
   do not try to infer it from request behaviour, which looks identical either way. Note this step
   is about a certificate the host **can** find: if the thumbprint is not in the store at all, the
   host never starts and tells you so by name, as described above.
5. **Ring contents.** The ring loaded, but is it the one the Framework app actually writes? On
   `azureblob`, confirm the blob URI matches; on `filesystem`, the directory. A target that is
   absent or empty is populated with a brand-new ring instead of failing, and a new ring decrypts
   nothing the other app wrote — which logs a *successful* load and still signs nobody in.
