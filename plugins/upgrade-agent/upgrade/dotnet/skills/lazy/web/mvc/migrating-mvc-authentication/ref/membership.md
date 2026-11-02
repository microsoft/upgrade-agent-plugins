# Membership and User Stores

Read when the authentication inventory finds a Membership provider or `Roles` usage.
The main skill's side-by-side cookie gate still applies to these user-store migrations.

## SqlMembershipProvider / SimpleMembership → ASP.NET Core Identity

If the project uses `SqlMembershipProvider` or `SimpleMembership`, migrate to ASP.NET Core Identity. For detailed Identity migration (DbContext, UserManager, SignInManager), see `migrating-aspnet-identity`.

**Password hashing change:** ASP.NET Membership uses SHA-1 or SHA-256 hashed passwords. ASP.NET Core Identity uses PBKDF2 with HMAC-SHA256. Existing password hashes are incompatible. Implement a compatibility hasher that verifies old hashes and re-hashes on successful login:

```csharp
public class MembershipPasswordHasher : IPasswordHasher<ApplicationUser>
{
    private readonly PasswordHasher<ApplicationUser> _coreHasher = new();

    public string HashPassword(ApplicationUser user, string password)
    {
        return _coreHasher.HashPassword(user, password);
    }

    public PasswordVerificationResult VerifyHashedPassword(
        ApplicationUser user, string hashedPassword, string providedPassword)
    {
        // Try ASP.NET Core format first
        var result = _coreHasher.VerifyHashedPassword(user, hashedPassword, providedPassword);
        if (result != PasswordVerificationResult.Failed)
            return result;

        // Fall back to legacy Membership hash verification
        if (VerifyLegacyHash(hashedPassword, providedPassword))
            return PasswordVerificationResult.SuccessRehashNeeded;

        return PasswordVerificationResult.Failed;
    }

    private bool VerifyLegacyHash(string hashedPassword, string providedPassword)
    {
        // Implement legacy hash verification matching the old provider's algorithm
        // (SHA-1, SHA-256, or custom — check the old <membership> config for hashAlgorithmType)
        throw new NotImplementedException("Match the old provider's hash algorithm");
    }
}
```

Register the custom hasher:

```csharp
builder.Services.AddScoped<IPasswordHasher<ApplicationUser>, MembershipPasswordHasher>();
```

**⚠️ Security note:** The `VerifyLegacyHash` implementation must match the exact algorithm from the old `<membership>` configuration, including salt handling. Get this wrong and either all logins fail or password verification is insecure.

## Custom MembershipProvider → Custom UserStore

If the project uses a custom `MembershipProvider`, implement `IUserStore<TUser>` and optionally `IUserPasswordStore<TUser>`:

```csharp
public class LegacyUserStore : IUserStore<ApplicationUser>, IUserPasswordStore<ApplicationUser>
{
    // Map old MembershipProvider methods to UserStore interface
    // GetUser → FindByIdAsync / FindByNameAsync
    // ValidateUser → handled by IPasswordHasher
    // CreateUser → CreateAsync
}
```

Replace `Roles.IsUserInRole(username, role)` with:

```csharp
// In a controller (synchronous check via ClaimsPrincipal):
User.IsInRole("Admin")

// Via UserManager (async):
await userManager.IsInRoleAsync(user, "Admin")
```
