# Authentication

Every Track 1 library invented its own credential type. Track 2 replaced all of them with one
abstraction — `TokenCredential` from `Azure.Core`, implemented by `Azure.Identity` — plus a few
narrow key-based types. The mapping is identical for the management plane and the client plane.

## Contents

- [Scope boundary](#scope-boundary)
- [Track 2 credential shapes](#track-2-credential-shapes)
- [Legacy credential mapping](#legacy-credential-mapping)
- [AppAuthentication configuration](#appauthentication-configuration)
- [Choosing a credential](#choosing-a-credential)
- [Common rewrites](#common-rewrites)
- [Connection strings and account keys](#connection-strings-and-account-keys)
- [Dependency injection](#dependency-injection)
- [Sovereign clouds](#sovereign-clouds)
- [Troubleshooting](#troubleshooting)

## Scope boundary

This file covers replacing credentials **used to authenticate Azure SDK clients**. If the legacy ADAL
code is doing general-purpose user authentication — acquiring tokens for your own APIs, interactive
sign-in flows, token caching for a web app — that is a different migration and belongs to
`migrating-adal-to-msal`. Load that skill instead of forcing `Azure.Identity` onto it.

## Track 2 credential shapes

| Shape | Type | Used for |
|---|---|---|
| Entra token | `TokenCredential` (defined in `Azure.Core`, implemented by `Azure.Identity`) | The default for everything. Required for all management-plane calls. |
| API key | `AzureKeyCredential` | Services authenticated by a flat key — Search, Event Grid, the AI services. |
| Shared access signature | `AzureSasCredential` | Pre-signed URLs. |

Shared-key (account-key) authentication is a fourth shape, and the type differs per service:

| Service | Shared-key credential type |
|---|---|
| Blobs, Queues, Files | `StorageSharedKeyCredential` (`Azure.Storage.Common`) |
| Tables | `TableSharedKeyCredential` (`Azure.Data.Tables`) |
| Service Bus, Event Hubs | `AzureNamedKeyCredential` (`Azure.Core`) |

Each client accepts only the subset its service supports — Search takes `AzureKeyCredential` and
`TokenCredential` but not a shared key; the management plane takes only `TokenCredential`. Check the
client's constructor overloads with `get_type_info` rather than assuming a credential is portable.

Credentials are re-read by the client before every request, so a client never needs rebuilding to pick
up a **new token** from the same credential object. That is not the same as rotating the credential's
*configuration*: `ClientSecretCredential` and `EnvironmentCredential` capture their settings at
construction, so changing a secret or an environment variable does not affect an existing instance.
Where a rotating key is genuinely needed, use the mutable key credentials (`AzureKeyCredential.Update`,
`AzureSasCredential.Update`). Credentials are thread-safe and cache tokens internally: construct one
per application and share it across every client.

## Legacy credential mapping

| Legacy type or pattern | Came from | Track 2 replacement |
|---|---|---|
| `ServiceClientCredentials`, `TokenCredentials` | `Microsoft.Rest.ClientRuntime` | `TokenCredential` |
| `ApplicationTokenProvider.LoginSilentAsync(tenant, clientId, secret)` | `Microsoft.Rest.ClientRuntime.Azure.Authentication` | `ClientSecretCredential(tenantId, clientId, secret)` |
| `ApplicationTokenProvider.LoginSilentAsync(tenant, clientAssertionCertificate)` | same | `ClientCertificateCredential(tenantId, clientId, certificate)` |
| `UserTokenProvider.LoginWithPromptAsync(...)` | same | `InteractiveBrowserCredential` |
| `SdkContext.AzureCredentialsFactory.FromServicePrincipal(...)` | `Microsoft.Azure.Management.*.Fluent` | `ClientSecretCredential` or `ClientCertificateCredential` |
| `SdkContext.AzureCredentialsFactory.FromFile(authFilePath)` | same | No Track 2 equivalent — the auth-file format is gone. Read the file yourself and construct the matching credential from its values (`ClientSecretCredential` for a client-secret file), or move the values to environment variables and use `EnvironmentCredential`. The file also carries the **subscription ID**, which must be passed to `ArmClient` explicitly. Do not substitute `DefaultAzureCredential`. |
| `SdkContext.AzureCredentialsFactory.FromMSI(...)` | same | `ManagedIdentityCredential` |
| `AzureServiceTokenProvider(...)` | `Microsoft.Azure.Services.AppAuthentication` | Resolve its constructor connection string or `AzureServicesAuthConnectionString` first; see AppAuthentication configuration below. Some modes have no direct replacement. |
| `AzureServiceTokenProvider().KeyVaultTokenCallback` | same | Pass that identity-preserving credential straight to `SecretClient`/`KeyClient`/`CertificateClient`. |
| `AzureServiceTokenProvider().GetAccessTokenAsync(resource)` | same | `credential.GetTokenAsync(new TokenRequestContext(scopes), ct)` — the resource becomes a **scope**, normally the resource URI with `/.default` appended |
| `KeyVaultClient.AuthenticationCallback` | `Microsoft.Azure.KeyVault` | `TokenCredential` |
| `AuthenticationContext.AcquireTokenAsync(...)` | ADAL | `ClientSecretCredential` / `ClientCertificateCredential` — but see the scope boundary above |
| `StorageCredentials(accountName, key)` | `WindowsAzure.Storage` | `StorageSharedKeyCredential(accountName, key)`; switching to `TokenCredential` is a separate, approved authentication change. |
| `StorageCredentials(sasToken)` | same | `AzureSasCredential`, or append the SAS to the service URI |
| `TokenProvider.CreateSharedAccessSignatureTokenProvider(keyName, key)` | `WindowsAzure.ServiceBus` | Connection string with the shared access key, or `AzureNamedKeyCredential` |
| `TokenProvider.CreateManagedIdentityTokenProvider()` | same | `ManagedIdentityCredential`, preserving any user-assigned identity selector |
| `SearchCredentials(apiKey)` | `Microsoft.Azure.Search` | `AzureKeyCredential(apiKey)` |
| `ApiKeyServiceClientCredentials(key)` | `Microsoft.Azure.CognitiveServices.*` | `AzureKeyCredential(key)` |

## AppAuthentication configuration

The constructor alone does not identify the provider. Inspect an explicitly supplied connection
string and the effective `AzureServicesAuthConnectionString` in deployment configuration, with the
owner if needed. Record the mode and identity selectors, never secret values. Use the
[official migration table](https://learn.microsoft.com/en-us/dotnet/api/overview/azure/app-auth-migration)
and verify the target version:

| Existing configuration | Migration |
|---|---|
| `RunAs=Developer;DeveloperTool=AzureCli` or `VisualStudio` | Corresponding `AzureCliCredential` or `VisualStudioCredential`; preserve tenant/account selection. |
| `RunAs=App` | System-assigned `ManagedIdentityCredential`. |
| `RunAs=App;AppId=...` without secret/certificate selectors | User-assigned managed identity with that selector. |
| `RunAs=App;AppId=...;TenantId=...;AppKey=...` | `ClientSecretCredential` with the same values. |
| `CertificateThumbprint` or `CertificateSubjectName` plus `CertificateStoreLocation` | No automatic certificate-store lookup in the new credential. Load the same certificate explicitly, preserving store, selection and rotation behavior, then use `ClientCertificateCredential`; unresolved selection blocks migration. |
| `RunAs=CurrentUser` or `KeyVaultCertificateSecretIdentifier` | No direct Azure.Identity equivalent in this migration model. Stop/report and obtain an approved design; do not select a nearby identity. |
| No effective connection string, or configuration cannot be inspected | Environment-dependent selection; ask which identities/paths must remain. `DefaultAzureCredential` has a different provider order and is not evidence of equivalence. |

Also search for `PrincipalUsed` consumers and runtime configuration changes: logging a credential
attempt does not replace that programmatic identity contract. Report unsupported behavior explicitly.

## Choosing a credential

`DefaultAzureCredential` is convenient for getting started and local development, but its broad
discovery chain is not the recommended production default. Follow the
[Azure Identity best practices](https://learn.microsoft.com/en-us/dotnet/azure/sdk/authentication/best-practices):
select a specific credential for each production environment so a newly available source cannot
silently change the identity. Preserve the existing principal, tenant, cloud and authentication mode;
changing the credential type is not permission to change any of them.

| Environment | Credential |
|---|---|
| App Service, Functions, VM, Container Apps | `ManagedIdentityCredential` |
| AKS with workload identity | `WorkloadIdentityCredential` |
| CI with an existing federated identity | The credential matching that pipeline's federation mechanism |
| Existing service principal with a secret or certificate | `ClientSecretCredential` or `ClientCertificateCredential` |
| Local development | `AzureCliCredential`, `VisualStudioCredential`, or `DefaultAzureCredential` |
| Explicit ordered fallback | `ChainedTokenCredential(first, second, ...)` |

**When the legacy code used a user-assigned managed identity, its selector must carry across.**
Do not substitute the system-assigned identity when its client ID is missing. Constructor overloads
have changed across `Azure.Identity` versions; inspect `ManagedIdentityCredential` and its identity
options with `get_type_info` rather than copying a version-incompatible snippet.

Use `ChainedTokenCredential` only when fallback between the named sources is intentional. It tries
them in order, skipping `CredentialUnavailableException`; an authentication failure stops the chain.
This differs from `DefaultAzureCredential`: since Azure.Identity 1.10.1 its developer-tool credentials
can continue after authentication failures, while deployed credentials stop when they can attempt
authentication but fail. A named chain limits the sources; it does not guarantee a single principal.

For example, if the application already uses a user-assigned managed identity in production and
allows either Visual Studio or Azure CLI locally, select those paths explicitly:

```csharp
TokenCredential credential;
if (builder.Environment.IsProduction() || builder.Environment.IsStaging())
{
    credential = new ManagedIdentityCredential(
        ManagedIdentityId.FromUserAssignedClientId(userAssignedClientId));
}
else
{
    credential = new ChainedTokenCredential(
        new VisualStudioCredential(new VisualStudioCredentialOptions { TenantId = tenantId }),
        new AzureCliCredential(new AzureCliCredentialOptions { TenantId = tenantId }));
}
```

Check that the installed version exposes `ManagedIdentityId`. Adapt the example to the application's
known environments; do not add developer fallback to production or replace a CI service principal
with a CLI credential unless that is the existing, deliberately configured authentication path.

## Common rewrites

In examples that reuse `credential`, it is the `TokenCredential` selected above for the existing
identity and environment. Client construction must not introduce a new credential choice.

Management plane, Track 1:

```csharp
// Old
ServiceClientCredentials credentials =
    await ApplicationTokenProvider.LoginSilentAsync(tenantId, clientId, clientSecret);
var computeClient = new ComputeManagementClient(credentials) { SubscriptionId = subscriptionId };
var networkClient = new NetworkManagementClient(credentials) { SubscriptionId = subscriptionId };

// New — one credential, one client, every provider reachable from it
var credential = new ClientSecretCredential(tenantId, clientId, clientSecret);
var armClient = new ArmClient(credential, subscriptionId);
```

Management plane, Fluent:

```csharp
// Old — the auth file carries tenant, client, secret, and subscription
var credentials = SdkContext.AzureCredentialsFactory.FromFile(authFilePath);
var azure = Azure.Configure().Authenticate(credentials).WithDefaultSubscription();

// New — the file format is gone, so read it and carry every value across.
// Do NOT collapse this to DefaultAzureCredential: that selects a different principal.
var credential = new ClientSecretCredential(tenantId, clientId, clientSecret);
var armClient = new ArmClient(credential, subscriptionId);
```

`WithDefaultSubscription()` resolved the subscription from the auth file. `ArmClient` takes it as a
constructor argument, so dropping it changes which subscription the code mutates.
`armClient.GetDefaultSubscriptionAsync()` is only equivalent when the identity genuinely has one
default subscription — prefer passing the ID explicitly.

Key Vault, replacing the token callback:

```csharp
// Old
var tokenProvider = new AzureServiceTokenProvider();
var client = new KeyVaultClient(
    new KeyVaultClient.AuthenticationCallback(tokenProvider.KeyVaultTokenCallback));
SecretBundle secret = await client.GetSecretAsync(vaultBaseUrl, "connection-string");

// New — no callback plumbing; the vault URI moves to the constructor
var secretClient = new SecretClient(new Uri(vaultBaseUrl), credential);
KeyVaultSecret secret = await secretClient.GetSecretAsync("connection-string");
```

The old client accepted a vault per call; `SecretClient` binds one at construction. Inspect every
old get/set call and reuse one client per distinct vault and credential/options configuration, not
one client for all vaults. Apply the same rule to key and certificate clients and cross-vault copies.
Also preserve secret names and versions when splitting a full secret identifier.

Requesting a raw token, where the legacy *resource* becomes a *scope*:

```csharp
// Old
var tokenProvider = new AzureServiceTokenProvider();
string token = await tokenProvider.GetAccessTokenAsync("https://management.azure.com/");

// New
AccessToken token = await credential.GetTokenAsync(
    new TokenRequestContext(["https://management.azure.com/.default"]),
    cancellationToken);
```

## Connection strings and account keys

Most data-plane clients still support a connection string. Preserving one keeps authentication
behavior stable, but support is not a security recommendation:

```csharp
var blobServiceClient = new BlobServiceClient(connectionString);
```

**Moving to Entra authentication is a behavior change, not a refactor.** It needs a role assignment on
the target resource — for example **Storage Blob Data Contributor**, which is a different role
definition from the control-plane **Contributor**. Do not fold it into a package migration. If the
legacy code authenticated with a key or connection string, the port keeps doing so unless the user
asked otherwise; switching is a separate, reported decision:

```csharp
var blobServiceClient = new BlobServiceClient(
    new Uri("https://myaccount.blob.core.windows.net"),
    credential);
```

**Retained secret-based authentication is a finding.** Report secret-bearing connection strings,
account keys and other long-lived shared secrets, even when supplied through environment variables.
Name the mechanism and configuration location, never the secret value. State that it was preserved
deliberately and recommend a separate move to managed/workload identity where the service supports
it, including required role assignments. Do not silently change the authentication mode.

**Preserving a secret-bearing credential file is behavior-preserving, and also a finding.** Reading
a client secret or private key from disk retains a filesystem secret dependency; a tenant or client
ID alone is not a secret. Port it faithfully so the principal does not change, and report it:
name the file, say the migration preserved the mechanism deliberately, and
offer a safer credential mechanism as a follow-up the user can accept or decline. Moving the same
secret into an environment variable addresses its file storage, not the retained-secret finding.
Do not switch the mechanism unasked; do not stay silent about it either.

## Dependency injection

Keep the application's existing DI approach. If it already uses `AddAzureClients`, retain the
authentication mode and client lifetime; a connection-string registration remains:

```csharp
builder.Services.AddAzureClients(clients =>
{
    clients.AddBlobServiceClient(connectionString);
});
```

Use an endpoint overload plus `UseCredential(credential)` only for an existing Entra/token-auth path,
with the identity-preserving credential selected above. A legacy callback can become that credential;
the old code need not literally use the Track 2 `TokenCredential` type. Do not introduce
`Microsoft.Extensions.Azure`, replace manual registrations, or convert connection strings to Entra
as an incidental package change. A DI refactor is separately scoped and must preserve per-client
credentials, options and lifetimes rather than forcing every client onto one identity.

## Sovereign clouds

Track 1 selected a cloud through `AzureEnvironment.AzureChinaCloud` or a base-URI property. Track 2
sets the authority on the credential and the endpoint on the client. For an existing client-secret
service principal in Azure China, retain its tenant, client and secret:

```csharp
var credential = new ClientSecretCredential(
    tenantId, clientId, clientSecret, new ClientSecretCredentialOptions
    {
        AuthorityHost = AzureAuthorityHosts.AzureChina
    });

var armClient = new ArmClient(credential, subscriptionId, new ArmClientOptions
{
    Environment = ArmEnvironment.AzureChina
});
```

Both halves are required. Setting only the authority host authenticates against the right cloud and
then calls the public endpoint. For another authentication mode, keep its credential type and apply
the corresponding supported cloud configuration rather than switching to a client secret.

## Troubleshooting

**`CredentialUnavailableException` from `DefaultAzureCredential`.** No source in the chain was
configured. Confirm one of: `az login`, a Visual Studio account, the `AZURE_TENANT_ID` /
`AZURE_CLIENT_ID` / `AZURE_CLIENT_SECRET` environment variables, or an assigned managed identity.

**Authentication succeeds but calls return 403.** The identity is real but lacks a data-plane role
assignment. Control-plane roles do not grant data access.

**Worked before the migration, fails after, on a VM or App Service.** A user-assigned managed identity
was in use and its client ID was dropped.

**Token acquisition is slow on the first call.** `DefaultAzureCredential` probes multiple sources;
unavailable configuration may fail fast, while other attempts add latency. Use the intended concrete
credential in production rather than relying on discovery.

**Diagnosing which source was selected.** Enable SDK logging with
`AzureEventSourceListener.CreateConsoleLogger()`; it reports each credential attempt and why it was
skipped.
