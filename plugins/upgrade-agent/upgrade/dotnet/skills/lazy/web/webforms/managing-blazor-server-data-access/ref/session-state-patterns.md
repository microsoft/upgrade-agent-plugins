# Session State Migration Patterns

Session state migration from Web Forms to Blazor Server requires understanding the HttpContext limitation in Interactive Server Mode and choosing the appropriate alternative pattern.

## Contents
- The Session State Problem
- Option A: Minimal API Endpoints (Recommended for Form Submissions)
- Option B: Scoped Service (For Transient UI State)
- Option C: Database-Backed (For Persistent State)
- Option D: ProtectedSessionStorage (For Browser Session Tab State)
- State Storage Comparison Table
- Decision Guide
- Recommendation

## The Session State Problem

> **CRITICAL:** When using `<Routes @rendermode="InteractiveServer" />` (global interactive server mode), `HttpContext.Session` is **NULL** during WebSocket rendering. Any code that accesses `HttpContext.Session` inside a Blazor component event handler or lifecycle method will throw a `NullReferenceException` or silently fail.

**Why this happens:** After the initial HTTP request establishes the SignalR circuit, Blazor communicates over WebSocket. There is no HTTP request/response — and therefore no session middleware processing — during component interactions.

---

## Option A: Minimal API Endpoints (Recommended for Form Submissions)

Use standard HTML `<form method="post">` elements that submit to minimal API endpoints via full HTTP POST requests. The endpoint has a real `HttpContext` with session access.

### Example: Student Form Submission

```csharp
// Program.cs
app.MapPost("/api/students/add", async (StudentDto dto, SchoolContext db) =>
{
    var student = new Student 
    { 
        FirstName = dto.FirstName, 
        LastName = dto.LastName, 
        EnrollmentDate = dto.EnrollmentDate 
    };
    db.Students.Add(student);
    await db.SaveChangesAsync();
    return Results.Ok(student.StudentID);
}).DisableAntiforgery();
```

```razor
@* In Students.razor *@
@inject HttpClient Http

@code {
    private async Task AddStudent()
    {
        await Http.PostAsJsonAsync("/api/students/add", newStudent);
        await RefreshGrid();
    }
}
```

> **Important:** The endpoint MUST call `.DisableAntiforgery()` because Blazor's HTML rendering does not include antiforgery tokens.

**When to use:**
- Form submissions that need to persist data
- Operations that require HttpContext access
- Business-critical state that must be guaranteed

---

## Option B: Scoped Service (For Transient UI State)

Replace `Session["key"]` with a scoped DI service. State lives in server memory for the duration of the SignalR circuit.

### Example: Shopping Cart Service

```csharp
// CartService.cs
public class CartService
{
    private readonly List<CartItem> _items = new();
    public void Add(CartItem item) => _items.Add(item);
    public IReadOnlyList<CartItem> Items => _items.AsReadOnly();
    public decimal GetTotal() => _items.Sum(i => i.Price * i.Quantity);
}

// Program.cs
builder.Services.AddScoped<CartService>();

// Component usage
@inject CartService CartService

<button @onclick="() => CartService.Add(new CartItem(...))">Add</button>
```

**Trade-off:** State is lost if the user refreshes the page or the circuit disconnects. Good for transient UI state (form drafts, temporary selections), not for durable cart data.

**When to use:**
- Transient UI state (wizard progress, temporary filters)
- State that doesn't need to survive refresh
- Fast, in-memory operations

---

## Option C: Database-Backed (For Persistent State)

Store state in the database, keyed by user ID or a cookie-based session token. Survives circuit disconnects, page refreshes, and server restarts.

### Example: User Preferences Service

```csharp
// UserPreferencesService.cs  
public class UserPreferencesService(IDbContextFactory<SchoolContext> factory)
{
    public async Task<string?> GetAsync(string userId, string key)
    {
        using var db = factory.CreateDbContext();
        var pref = await db.UserPreferences.FirstOrDefaultAsync(p => p.UserId == userId && p.Key == key);
        return pref?.Value;
    }

    public async Task SetAsync(string userId, string key, string value)
    {
        using var db = factory.CreateDbContext();
        var pref = await db.UserPreferences.FirstOrDefaultAsync(p => p.UserId == userId && p.Key == key);
        if (pref != null)
            pref.Value = value;
        else
            db.UserPreferences.Add(new UserPreference { UserId = userId, Key = key, Value = value });
        await db.SaveChangesAsync();
    }
}

// Program.cs
builder.Services.AddScoped<UserPreferencesService>();
```

**When to use:**
- Business-critical state (shopping carts, saved searches)
- State that must survive server restarts
- Multi-device synchronization needs

---

## Option D: ProtectedSessionStorage (For Browser Session Tab State)

For state that must survive page refreshes within the same browser tab, but doesn't need server-side persistence.

```razor
@inject ProtectedSessionStorage SessionStorage

@code {
    protected override async Task OnAfterRenderAsync(bool firstRender)
    {
        if (firstRender)
        {
            var result = await SessionStorage.GetAsync<ShoppingCart>("cart");
            cart = result.Success ? result.Value! : new ShoppingCart();
        }
    }

    private async Task SaveCart()
    {
        await SessionStorage.SetAsync("cart", cart);
    }
}
```

> **Note:** `ProtectedSessionStorage` only works after the first render (requires JS interop). Always access in `OnAfterRenderAsync`, not `OnInitializedAsync`.

**When to use:**
- State that needs to survive refresh but not server restart
- Tab-specific state (separate cart per browser tab)
- Encrypted client-side storage needs

---

## State Storage Comparison Table

| Web Forms | Blazor Equivalent | Scope | Survives Refresh? | Survives Disconnect? |
|-----------|------------------|-------|-------------------|----------------------|
| `Session["key"]` | Scoped service | Per-circuit | ❌ No | ❌ No |
| `Session["key"]` (persistent) | `ProtectedSessionStorage` | Browser tab | ✅ Yes | ❌ No |
| `Session["key"]` (persistent) | Database-backed service | Per-user | ✅ Yes | ✅ Yes |
| `Application["key"]` | Singleton service | App-wide | ✅ Yes | ❌ No |
| `Cache["key"]` | `IMemoryCache` or `IDistributedCache` | Configurable | Depends | Depends |
| `ViewState["key"]` | Component fields/properties | Per-component | ❌ No | ❌ No |

---

## Decision Guide

**Choose Option A (Minimal API Endpoints) when:**
- ✅ Submitting forms with business data
- ✅ Need HttpContext.Session access
- ✅ Operation must be guaranteed (HTTP response confirms success)

**Choose Option B (Scoped Service) when:**
- ✅ Transient UI state (wizard progress, temp filters)
- ✅ Performance is critical (in-memory)
- ❌ Don't need to survive refresh

**Choose Option C (Database-Backed) when:**
- ✅ Business-critical state (shopping cart, bookmarks)
- ✅ Must survive server restarts
- ✅ Need cross-device sync

**Choose Option D (ProtectedSessionStorage) when:**
- ✅ Need to survive refresh
- ✅ Tab-specific data (each tab has separate state)
- ❌ Don't need server-side persistence

---

## Recommendation

**For shopping carts and other business-critical state:** Prefer Option A (minimal API endpoints) or Option C (database). Use Option B only for transient UI state that can be safely lost on refresh or disconnect.
