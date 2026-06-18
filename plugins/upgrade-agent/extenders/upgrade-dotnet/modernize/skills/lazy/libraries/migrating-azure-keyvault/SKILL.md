---
name: migrating-azure-keyvault
description: >
  Migrates from the deprecated Microsoft.Azure.KeyVault SDK
  to the modern Azure.Security.KeyVault client libraries
  (Secrets, Keys, Certificates). Use ONLY when
  Microsoft.Azure.KeyVault has been flagged as obsolete or
  deprecated and must be replaced — not for version-bump
  scenarios where Microsoft.Azure.KeyVault is still
  supported.
metadata:
  discovery: lazy
  traits: .NET|CSharp|VisualBasic|DotNetCore
---

# Azure Key Vault SDK Migration

## Overview

Migrate from the deprecated `Microsoft.Azure.KeyVault` SDK to the modern `Azure.Security.KeyVault.*` libraries. The new SDK splits the single `KeyVaultClient` into resource-specific clients (`SecretClient`, `KeyClient`, `CertificateClient`) and uses `Azure.Identity` for authentication instead of custom token callbacks. Both synchronous and asynchronous APIs are available.

## Package Reference Changes

### Old References (Remove)

```xml
<PackageReference Include="Microsoft.Azure.KeyVault" Version="{any}" />
<PackageReference Include="Microsoft.Azure.KeyVault.Models" Version="{any}" />
<!-- Legacy authentication helper -->
<PackageReference Include="Microsoft.Azure.Services.AppAuthentication" Version="{any}" />
```

### New References (Add)

```xml
<!-- Add only the packages for the resource types the project uses -->
<PackageReference Include="Azure.Security.KeyVault.Secrets" Version="{latest-stable}" />
<PackageReference Include="Azure.Security.KeyVault.Keys" Version="{latest-stable}" />
<PackageReference Include="Azure.Security.KeyVault.Certificates" Version="{latest-stable}" />

<!-- Unified authentication -->
<PackageReference Include="Azure.Identity" Version="{latest-stable}" />
```

Use tools or [NuGet](https://www.nuget.org/packages/Azure.Security.KeyVault.Secrets) to find the latest stable versions. Only add the `Azure.Security.KeyVault.*` packages that the project actually needs.

## Workflow

```
Migration Progress:
- [ ] Step 1: Detect Key Vault SDK usage
- [ ] Step 2: Update package references
- [ ] Step 3: Replace authentication
- [ ] Step 4: Replace client initialization
- [ ] Step 5: Convert secret operations
- [ ] Step 6: Convert key and certificate operations
- [ ] Step 7: Migrate error handling
- [ ] Step 8: Build and verify
```

### Step 1: Detect Key Vault SDK Usage

Scan the project for:
- `using Microsoft.Azure.KeyVault;` and `using Microsoft.Azure.KeyVault.Models;`
- Types: `KeyVaultClient`, `SecretBundle`, `KeyBundle`, `CertificateBundle`
- Methods: `GetSecretAsync`, `SetSecretAsync`, `GetKeyAsync`, `GetCertificateAsync`
- Authentication patterns: `KeyVaultClient.AuthenticationCallback`, `AzureServiceTokenProvider`

### Step 2: Update Package References

Remove `Microsoft.Azure.KeyVault`, `Microsoft.Azure.KeyVault.Models`, and `Microsoft.Azure.Services.AppAuthentication` from the project file. Add the appropriate `Azure.Security.KeyVault.*` and `Azure.Identity` packages.

### Step 3: Replace Authentication

```csharp
// Old — custom token callback
var azureServiceTokenProvider = new AzureServiceTokenProvider();
var client = new KeyVaultClient(
    new KeyVaultClient.AuthenticationCallback(
        azureServiceTokenProvider.KeyVaultTokenCallback));

// New — Azure.Identity (works with managed identity, Azure CLI, Visual Studio, etc.)
var credential = new DefaultAzureCredential();
```

`DefaultAzureCredential` chains multiple authentication methods automatically. For production scenarios that need a specific identity, use `ManagedIdentityCredential`, `ClientSecretCredential`, or another concrete type from `Azure.Identity`.

### Step 4: Replace Client Initialization

```csharp
// Old — single client for all resource types
var client = new KeyVaultClient(authCallback);

// New — one client per resource type
var vaultUri = new Uri("https://my-vault.vault.azure.net/");
var secretClient = new SecretClient(vaultUri, credential);
var keyClient = new KeyClient(vaultUri, credential);
var certificateClient = new CertificateClient(vaultUri, credential);
```

### Step 5: Convert Secret Operations

```csharp
// Old
SecretBundle secret = await client.GetSecretAsync(vaultBaseUrl, "my-secret");
string value = secret.Value;

await client.SetSecretAsync(vaultBaseUrl, "my-secret", "new-value");

// New
KeyVaultSecret secret = await secretClient.GetSecretAsync("my-secret");
string value = secret.Value;

await secretClient.SetSecretAsync("my-secret", "new-value");
```

The new client takes the vault URI at construction — pass only the secret name to each operation.

### Step 6: Convert Key and Certificate Operations

```csharp
// Old — Keys
KeyBundle key = await client.GetKeyAsync(vaultBaseUrl, "my-key");

// New — Keys
KeyVaultKey key = await keyClient.GetKeyAsync("my-key");

// Old — Certificates
CertificateBundle cert = await client.GetCertificateAsync(vaultBaseUrl, "my-cert");

// New — Certificates
KeyVaultCertificateWithPolicy cert = await certificateClient.GetCertificateAsync("my-cert");
```

### Step 7: Migrate Error Handling

```csharp
// Old
try { /* operation */ }
catch (KeyVaultErrorException ex) when (ex.Response.StatusCode == HttpStatusCode.NotFound)
{ /* handle */ }

// New
try { /* operation */ }
catch (RequestFailedException ex) when (ex.Status == 404)
{ /* handle */ }
```

`RequestFailedException` is the unified exception type across all `Azure.*` client libraries.

### Step 8: Build and Verify

1. Build the project:
   ```
   dotnet build
   ```
2. Verify authentication works in the target environment (local development, CI, Azure)
3. Test secret retrieval and any key/certificate operations against a development vault

## API Differences

| Old SDK (Microsoft.Azure.KeyVault) | New SDK (Azure.Security.KeyVault.*) | Notes |
|-------------------------------------|-------------------------------------|-------|
| `KeyVaultClient` | `SecretClient` / `KeyClient` / `CertificateClient` | One client per resource type |
| `AuthenticationCallback` | `DefaultAzureCredential` (Azure.Identity) | No manual token management |
| `AzureServiceTokenProvider` | `DefaultAzureCredential` | Automatic credential chaining |
| `SecretBundle` | `KeyVaultSecret` | Simpler model |
| `KeyBundle` | `KeyVaultKey` | Simpler model |
| `CertificateBundle` | `KeyVaultCertificateWithPolicy` | Includes policy in response |
| `GetSecretAsync(vaultUrl, name)` | `GetSecretAsync(name)` | Vault URL set at client construction |
| `SetSecretAsync(vaultUrl, name, value)` | `SetSecretAsync(name, value)` | Vault URL set at client construction |
| `KeyVaultErrorException` | `RequestFailedException` | Unified Azure SDK exception |
| Async-only APIs | Sync and async APIs | Both `GetSecret` and `GetSecretAsync` available |

## Troubleshooting

### Authentication Failures with DefaultAzureCredential

`DefaultAzureCredential` tries multiple credential sources in order. If it fails, check that at least one source is configured: Azure CLI login (`az login`), Visual Studio authentication, environment variables (`AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_CLIENT_SECRET`), or managed identity. Enable logging with `AzureEventSourceListener` to see which credential is attempted.

### Vault URL No Longer Passed Per-Call

The new clients take the vault URI in the constructor. If the old code used different vault URLs for different operations, create separate client instances for each vault.

### Missing SecretBundle or KeyBundle Types

These types are replaced by `KeyVaultSecret` and `KeyVaultKey` in the new SDK. Update all variable declarations and return types. Properties like `SecretBundle.Value` map directly to `KeyVaultSecret.Value`.

### Package Version Conflicts with Other Azure SDKs

The new Key Vault libraries depend on `Azure.Core`. If other Azure SDK packages are present, ensure all packages use compatible `Azure.Core` versions to avoid binding redirect issues.
