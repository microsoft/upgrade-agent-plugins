# Authentication interop setup

Read this before configuring either authentication-interop path — `-EnableSharedCookieAuth`
(shared cookie) or `-EnableRemoteAuth` (remote auth), or the tool's `authInterop`. The main
skill's **Authentication interop** section holds the decision table and the confirmed-option
gates; this file holds the parameter reference, the ready-to-paste invocation groups, and the
footguns that decide whether a wired-up proxy actually signs anyone in.

## Contents

- [Authentication interop parameters](#authentication-interop-parameters)
- [Invocation groups](#invocation-groups)
- [Footguns and Visual Studio notes](#footguns-and-visual-studio-notes)
## Authentication interop parameters

**Authentication interop parameters (optional, off by default).** Ask the user whether
signed-in users must stay signed in across both apps while the migration runs. If they do,
pick one path — the two are mutually exclusive and the script rejects both together:

| Parameter | Path | How to find it |
|-----------|------|---------------|
| `-EnableSharedCookieAuth` | Shared cookie | Both apps read the same encrypted cookie. Choose **only** when the old app authenticates with **Katana/OWIN cookie middleware** under `Microsoft.Owin.Host.SystemWeb`, and both apps can reach one shared Data Protection key ring. See the two preconditions below — neither is checked, and violating either produces a proxy that builds and signs nobody in. |
| `-SharedKeyRingProvider` | Shared cookie | Where the shared key ring lives: `filesystem` (default) or `azureblob`. **This must match how the old app already persists its keys** — ask, do not assume. It selects which of the two companion pairs below is required, and the wrong choice produces an app that starts and never decrypts. |
| `-SharedKeyRingPath` | Shared cookie, `filesystem` | Directory both apps can read (often a UNC share). **No default** — ask the user. |
| `-SharedCertificateThumbprint` | Shared cookie, `filesystem` | Thumbprint of the X.509 cert protecting the key ring. Both hosts need the private key. |
| `-SharedKeyRingUri` | Shared cookie, `azureblob` | Absolute `https` URI of the Azure Storage blob holding the ring, e.g. `https://acct.blob.core.windows.net/dp/keys.xml`. The container must exist; the blob need not. |
| `-SharedKeyVaultKeyId` | Shared cookie, `azureblob` | Absolute `https` URI of the Key Vault key protecting the ring, e.g. `https://vault.vault.azure.net/keys/dp/<version>`. |
| `-AzureDataProtectionBlobsVersion` | Shared cookie, `azureblob` | Optional. Version of `Azure.Extensions.AspNetCore.DataProtection.Blobs` to add to the generated project. Omit to take the script's verified default; pass `get_supported_package_version` for that package only if the default is unavailable to this customer. |
| `-AzureDataProtectionKeysVersion` | Shared cookie, `azureblob` | Optional. Same, for `Azure.Extensions.AspNetCore.DataProtection.Keys`. |
| `-SharedApplicationName` | Shared cookie | The old app's Data Protection application name. Must be identical on both sides. |
| `-SharedCookieName` | Shared cookie | The old app's Katana cookie name (`CookieAuthenticationOptions.CookieName`, often `.AspNet.ApplicationCookie`). Read it from the OWIN startup class or browser dev tools. **Never guess** — a wrong name means the user silently appears signed out. A `.ASPXAUTH` cookie means classic Forms authentication, which this path does **not** support; see the preconditions below. |
| `-SharedCookieScheme` | Shared cookie | The old app's `AuthenticationType` (Katana `CookieAuthenticationOptions.AuthenticationType`). |
| `-EnableRemoteAuth` | Remote auth | The new app asks the old app to authenticate each request. Choose when the old app uses **classic Forms authentication (`<forms>` in `Web.config`, `.ASPXAUTH`), Windows auth, a custom identity provider, or anything not Katana cookie-based**, or when the two apps cannot share a Data Protection key ring at all. |
| `-RemoteAppUrl` | Remote auth | Optional. Defaults to `-OldAppUrl`. Pass it only when the old app is reachable at a different address from the server. |
| `-RemoteAppApiKey` | Remote auth | A **GUID** shared with the old app. Generate with `[guid]::NewGuid()`. The script rejects a non-GUID. |

Every companion above is **required** when its switch is on and **rejected** when it is off, with
three exceptions, all marked *Optional* in the table: `-RemoteAppUrl` falls back to `-OldAppUrl`, and
the two `-AzureDataProtection*Version` parameters fall back to versions the script has verified
against the feed. Nothing else has a default, deliberately: a wrong cookie name, scheme, or key ring
produces an app that starts and serves traffic while authenticating nobody, with no error anywhere.
The same rule applies one level down — a `filesystem` companion passed with
`-SharedKeyRingProvider azureblob` is rejected, not ignored, and so is either version parameter
passed with the `filesystem` provider.

**Two preconditions on `-EnableSharedCookieAuth`. Neither is validated by the script, and each one
produces a proxy that compiles, starts, and silently signs nobody in.** Check both with the user
before choosing this path; if either fails, use `-EnableRemoteAuth` instead.

1. **The old app must authenticate with Katana/OWIN cookie middleware**, hosted under
   `Microsoft.Owin.Host.SystemWeb`. The emitted code reads a Data Protection ticket, and the
   Framework half is completed by the `sharing-authentication-cookies-katana-interop` skill, which
   requires `Microsoft.Owin.Security.Interop` and the `AspNetTicketDataFormat` shim. **Classic
   ASP.NET Forms authentication is not supported** — a `<forms>` element in `Web.config` and an
   `.ASPXAUTH` cookie mean a `machineKey`-encrypted `FormsAuthenticationTicket`, which ASP.NET Core
   cannot read no matter how the key ring is shared. Such an app must either move to Katana cookie
   middleware first, or use remote auth.
2. **The key ring topology must be one the scaffold emits, and `-SharedKeyRingProvider` must name
   the right one.** Two are supported:
   - `filesystem` — `PersistKeysToFileSystem(...).ProtectKeysWithCertificate(...)`. Both hosts need
     the directory and the certificate's private key.
   - `azureblob` — `PersistKeysToAzureBlobStorage(...).ProtectKeysWithAzureKeyVault(...)`, both
     authenticating with `DefaultAzureCredential`. Each host needs an identity granted **Storage
     Blob Data Contributor** on the blob and **Key Vault Crypto User** on the key. This is the shape
     a multi-instance or multi-slot deployment needs, because instances share the blob rather than a
     local disk.

   An app whose keys live somewhere else — **a database (`PersistKeysToDbContext`), Redis, or
   DPAPI-NG** — has no supported path through this scaffold: the generated `Program.cs` must be
   hand-edited to swap the persistence and protection calls. Confirm the topology before choosing
   this path.

Neither switch completes the job on its own — each configures only the ASP.NET Core half.
The script drops a `README.SHAREDCOOKIE.md` or `README.REMOTEAUTH.md` into the new project
with the .NET Framework half. See [Authentication interop](../SKILL.md#authentication-interop).

## Invocation groups

To pre-wire authentication interop, append **one** of the following groups to the same
single-line command. Passing both groups, or any companion without its switch, is rejected.

Shared cookie — both apps read the same encrypted cookie. Filesystem key ring (the default),
a directory both hosts can read:

```text
-EnableSharedCookieAuth -SharedKeyRingPath '//fileserver/keyring' -SharedCertificateThumbprint 'A1B2C3...' -SharedApplicationName 'MyLegacyApp' -SharedCookieName '.AspNet.ApplicationCookie' -SharedCookieScheme 'ApplicationCookie'
```

> **Write a UNC key-ring path with forward slashes** (`//fileserver/keyring`), not
> `\\fileserver\keyring`. Git Bash collapses the leading `\\` to a single `\` before
> PowerShell ever sees it, producing a path that is not a UNC share — silently, with a
> successful exit. Windows resolves the forward-slash form identically, and it survives all
> three shells unchanged. Verified from PowerShell, cmd and Git Bash.

Shared cookie, Azure key ring — when the old app already persists its keys to blob storage,
or the two hosts share no filesystem. Adds two Azure NuGet packages:

```text
-EnableSharedCookieAuth -SharedKeyRingProvider azureblob -SharedKeyRingUri 'https://acct.blob.core.windows.net/dataprotection/keys.xml' -SharedKeyVaultKeyId 'https://myvault.vault.azure.net/keys/dp-key/abc123' -SharedApplicationName 'MyLegacyApp' -SharedCookieName '.AspNet.ApplicationCookie' -SharedCookieScheme 'ApplicationCookie'
```

Remote auth — the new app asks the old app who the user is:

```text
-EnableRemoteAuth -RemoteAppApiKey '11111111-2222-3333-4444-555555555555'
```

## Footguns and Visual Studio notes

> **Footgun — with remote auth, plain `[Authorize]` is not enough.** The scaffold registers
> remote authentication as a **non-default** scheme
> (`AddAuthenticationClient(isDefaultScheme: false)`), because this app fronts a catch-all
> `MapForwarder` route: as the default scheme, every forwarded request would make a remote
> authentication call to the Framework app that is about to authenticate it anyway,
> double-authenticating each request and risking a redirect loop between the two apps.
>
> The consequence is that a migrated endpoint must name the scheme explicitly —
> `[Authorize(AuthenticationSchemes = RemoteAppAuthenticationDefaults.AuthenticationScheme)]`.
> A plain `[Authorize]` falls back to a default scheme that does not exist, so it denies and then
> throws `InvalidOperationException: No authenticationScheme was specified, and there was no
> DefaultChallengeScheme found` — the endpoint returns **500**, not 401 and not an anonymous
> success. It fails closed; the confusion is the status code, not a hole. The alternative is to
> make remote auth the default and call `.ShortCircuit()` on the forwarder route; naming the
> scheme is the less surprising option and is what the generated `Program.cs` documents inline.

> **Remote auth requires SystemWebAdapters CoreServices `2.3.0` or newer.** The non-default-scheme
> registration above holds only because the adapters *also* register an internal sentinel scheme,
> which stops ASP.NET Core auto-promoting a lone registered scheme to the default. Older releases do
> not: on `2.0.0` the `isDefaultScheme: false` argument is accepted and `Remote` becomes the default
> anyway, so every forwarded request makes the remote authentication call the argument exists to
> prevent — and nothing reports it, because the project restores, builds and starts normally. The
> script therefore **rejects** `-EnableRemoteAuth` together with an older `-SystemWebAdaptersVersion`.
>
> If `get_supported_package_version` returns something older, **do not drop `-EnableRemoteAuth` to
> get past the error**, and do not add the flag back by hand-editing the generated project. Either
> scaffold without auth interop and tell the user that remote auth needs CoreServices `2.3.0` or
> newer, or use `-EnableSharedCookieAuth`, which does not depend on this behaviour.
>
> **If `Remote Authentication` was the confirmed `Cross-App Cookie Authentication` value**, the
> second of those is not yours to take unilaterally. The floor is a constraint the user never
> saw when they chose, and the option is never reopened, so switching mechanism here settles a
> decision behind them. Report that the floor blocks the confirmed path and let them choose
> between raising CoreServices to `2.3.0` and changing mechanism. Scaffolding without auth
> interop meanwhile is fine — it leaves the seam and forecloses nothing.

> **Footgun — the shared-cookie contract has four separate ways to fail silently.** The
> cookie name, the scheme name (which must equal the Framework app's `AuthenticationType`),
> the Data Protection application name, and the key ring itself must all match. Any mismatch
> produces the same symptom: the user appears signed out. This is why none of these parameters
> has a default. The script path writes the debugging order into `README.SHAREDCOOKIE.md`; the
> tool path writes no README, so walk the user through that order yourself — it is the
> shared-cookie row of the [troubleshooting table](troubleshooting.md).

**Visual Studio note.** The `scaffold_yarp_proxy_web_project` tool wires the same two paths
via `authInterop`, with three differences from the script (all covered in [Step 1](../SKILL.md#step-1-choose-the-scaffolding-path-for-this-host)): it requires
`targetFramework` net10.0 or later, it writes the configuration keys **blank** for the user to
fill in rather than taking the values as arguments, and it writes **no README** — the
`tmpl/auth/` notes ship inside this skill, which the tool cannot reach. The keys are the same
ones listed above. Blank values fail loudly rather than silently, but not at the same moment:
the shared-cookie keys throw at **startup** (`DirectoryInfo("")` is an eager argument), while
`RemoteApp:Url` throws on **first use of the remote scheme**, because its options are validated
lazily. Either way an unfinished configuration cannot be mistaken for a working one. After the
tool returns, point the user at the comments in the generated `Program.cs` and at the matching
Framework-side skill (`sharing-authentication-cookies-katana-interop` for shared cookie,
`migrating-mvc-system-web-adapters` for remote auth — subject to the same gate as the decision
table in the main skill's [Authentication interop](../SKILL.md#authentication-interop) section:
skip that load when `Remote Authentication` and `Direct Migration to ASP.NET Core APIs`
are both confirmed, and hand over this skill's `tmpl/auth/README.REMOTEAUTH.md` yourself, since
this path writes none). When you have the values and
the host allows it, `scaffold-project.ps1` is the better path.
