---
name: migrating-cryptography-namespaces
description: >
  Migrates System.Security.Cryptography namespace usage from .NET Framework to modern .NET.
  Analyzes C# source files to detect cryptographic type usage and adds the correct using
  statements and NuGet packages after the namespace split (X509Certificates, Pkcs, Xml).
  Use when upgrading .NET Framework projects that reference System.Security.Cryptography,
  fixing CS0246 errors for X509Certificate2, SignedCms, SignedXml, or other crypto types,
  or adding missing using statements for cryptography namespaces in .cs files.
metadata:
  discovery: lazy
  traits: .NET|CSharp|Cryptography
---

# System.Security.Cryptography Migration

## Overview

In modern .NET, `System.Security.Cryptography` was split: certificate types moved to `System.Security.Cryptography.X509Certificates`, CMS/PKCS types to `System.Security.Cryptography.Pkcs` (separate NuGet package), and XML signature types to `System.Security.Cryptography.Xml` (separate NuGet package). This skill maps each type to its correct namespace and determines which NuGet packages to add.

## Workflow

```
Migration Progress:
- [ ] Step 1: Detect target framework
- [ ] Step 2: Scan source files
- [ ] Step 3: Analyze type usage
- [ ] Step 4: Add required using statements
- [ ] Step 5: Add required NuGet packages
- [ ] Step 6: Verify build
```

### Step 1: Detect Target Framework

Read `<TargetFramework>` or `<TargetFrameworks>` from the project file or `Directory.Build.props`. If the user specifies a target framework, use that instead.

### Step 2: Scan Source Files

Search for files containing these using statements:
- `using System.Security.Cryptography;`
- `using System.Security.Cryptography.X509Certificates;`
- `using System.Security.Cryptography.Pkcs;`
- `using System.Security.Cryptography.Xml;`

### Step 3: Analyze Type Usage

For each file, extract type references and match against the namespace tables below. Only add using statements for namespaces containing types actually used in that file — blindly adding all namespaces causes unnecessary dependencies and hides which files depend on which crypto features.

### Step 4: Add Required Using Statements

For each source file:
1. If X509 types are used (`X509Certificate2`, `X509Chain`, etc.) → add `using System.Security.Cryptography.X509Certificates;`
2. If PKCS/CMS types are used (`SignedCms`, `CmsSigner`, etc.) → add `using System.Security.Cryptography.Pkcs;`
3. If XML crypto types are used (`SignedXml`, `EncryptedXml`, etc.) → add `using System.Security.Cryptography.Xml;`

### Step 5: Add Required NuGet Packages

Add packages only when the project uses types from that namespace:

```xml
<!-- Only if PKCS/CMS types are used -->
<PackageReference Include="System.Security.Cryptography.Pkcs" Version="{version-for-target-framework}" />

<!-- Only if XML cryptography types are used -->
<PackageReference Include="System.Security.Cryptography.Xml" Version="{version-for-target-framework}" />
```

Use tools to determine the correct package version for the target framework. If unavailable, match the target framework major version (e.g., `9.0.x` for `net9.0`, `10.0.x` for `net10.0`). X509Certificate types are built into the SDK and need no package.

### Step 6: Verify

Build the project and confirm no cryptography-related compile errors remain.

## Namespace Mapping

### X509Certificates (Built-in — no NuGet package)

Namespace: `System.Security.Cryptography.X509Certificates`

| Type | Notes |
|------|-------|
| `X509Certificate` | Base certificate class |
| `X509Certificate2` | Extended certificate with private key |
| `X509Certificate2Collection` | |
| `X509Chain` | Certificate chain validation |
| `X509Store` | Certificate store access |
| `X509ChainPolicy` | |
| `X509ChainStatus` | |
| `X509ChainStatusFlags` | |
| `X509ContentType` | |
| `X509KeyStorageFlags` | |
| `X509KeyUsageFlags` | |
| `X509NameType` | |
| `X509RevocationMode` | |
| `X509RevocationFlag` | |
| `X509VerificationFlags` | |
| `X509FindType` | |
| `X509Certificate2Enumerator` | |
| `PublicKey` | Public key from certificate |
| `RSACertificateExtensions` | Extension methods |
| `DSACertificateExtensions` | Extension methods |
| `ECDsaCertificateExtensions` | Extension methods |

### Pkcs (NuGet package: `System.Security.Cryptography.Pkcs`)

| Type | Notes |
|------|-------|
| `SignedCms` | CMS/PKCS#7 signed data |
| `EnvelopedCms` | CMS/PKCS#7 enveloped data |
| `CmsSigner` | |
| `CmsRecipient` | |
| `CmsRecipientCollection` | |
| `ContentInfo` | |
| `SignerInfo` | |
| `SignerInfoCollection` | |
| `Pkcs12Builder` | |
| `Pkcs12Info` | |
| `Pkcs12SafeContents` | |
| `Pkcs8PrivateKeyInfo` | |
| `Pkcs9AttributeObject` | |
| `Pkcs9ContentType` | |
| `Pkcs9SigningTime` | |
| `Pkcs9MessageDigest` | |
| `Rfc3161TimestampRequest` | |
| `Rfc3161TimestampToken` | |
| `Rfc3161TimestampTokenInfo` | |
| `SubjectIdentifier` | |
| `SubjectIdentifierOrKey` | |
| `RecipientInfo` | |
| `RecipientInfoCollection` | |

### Xml (NuGet package: `System.Security.Cryptography.Xml`)

| Type | Ambiguity Risk |
|------|----------------|
| `SignedXml` | Low |
| `EncryptedXml` | Low |
| `XmlDsigC14NTransform` | Low — unique prefix |
| `XmlDsigEnvelopedSignatureTransform` | Low — unique prefix |
| `XmlDsigExcC14NTransform` | Low — unique prefix |
| `XmlDsigXPathTransform` | Low — unique prefix |
| `KeyInfo` | Medium — verify context |
| `KeyInfoX509Data` | Low |
| `KeyInfoName` | Low |
| `EncryptedData` | Low |
| `EncryptedKey` | Low |
| `EncryptionMethod` | Medium — verify context |
| `CipherData` | Low |
| `TransformChain` | Low |

**Ambiguity warning:** Types like `Reference`, `Transform`, `Signature`, and `DataObject` exist in this namespace but have common names. Only add `System.Security.Cryptography.Xml` when unambiguous types (`SignedXml`, `EncryptedXml`, `XmlDsig*`) are also present — this avoids false positives from generic type names.

### Core (Built-in — no changes needed)

These types remain in `System.Security.Cryptography`:

`Aes`, `RSA`, `ECDsa`, `SHA256`, `SHA384`, `SHA512`, `HMACSHA256`, `RandomNumberGenerator`, `CryptographicException`, `HashAlgorithm`, `SymmetricAlgorithm`, `AsymmetricAlgorithm`

## Platform Considerations

Some crypto operations differ across platforms in modern .NET:

| Feature | Windows | Linux | macOS |
|---------|---------|-------|-------|
| `X509Store` (system stores) | Full | Limited | Limited |
| Hardware key storage | Full | Limited | Keychain |
| Private key persistence | Full | File-based | Keychain |

For cross-platform code:
- Prefer `X509Certificate2.CreateFromPem()` / `CreateFromPemFile()` over store-based loading
- Use `X509KeyStorageFlags.EphemeralKeySet` when persistence is unnecessary — this avoids platform-specific key storage issues
- Avoid relying on system certificate stores if cross-platform support is needed

## Example

**Before** (.NET Framework — single namespace covered everything):
```csharp
using System.Security.Cryptography;

public class CertificateValidator
{
    public bool Validate(X509Certificate2 cert)
    {
        var chain = new X509Chain();
        return chain.Build(cert);
    }

    public byte[] Sign(byte[] data, X509Certificate2 cert)
    {
        var cms = new SignedCms(new ContentInfo(data));
        cms.ComputeSignature(new CmsSigner(cert));
        return cms.Encode();
    }
}
```

**After** (modern .NET — split namespaces):
```csharp
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Security.Cryptography.Pkcs;

public class CertificateValidator
{
    public bool Validate(X509Certificate2 cert)
    {
        var chain = new X509Chain();
        return chain.Build(cert);
    }

    public byte[] Sign(byte[] data, X509Certificate2 cert)
    {
        var cms = new SignedCms(new ContentInfo(data));
        cms.ComputeSignature(new CmsSigner(cert));
        return cms.Encode();
    }
}
```

Code logic is unchanged — only `using` statements and NuGet packages are affected.
