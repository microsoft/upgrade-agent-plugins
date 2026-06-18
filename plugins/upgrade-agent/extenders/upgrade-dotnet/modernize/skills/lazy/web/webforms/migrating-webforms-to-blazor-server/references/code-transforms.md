# Code Transformation Rules

Patterns for migrating Web Forms code-behind, data binding, and master pages to Blazor equivalents.

**Parent skill:** [migrating-webforms-to-blazor-server](../SKILL.md)

## Contents
- Code-Behind Migration
- Data Binding Migration
- Master Page → Layout Migration

---

## Code-Behind Migration

### Lifecycle Methods

| Web Forms | Blazor | Notes |
|-----------|--------|-------|
| `Page_Load(object sender, EventArgs e)` | `protected override async Task OnInitializedAsync()` | First load |
| `Page_PreRender(...)` | `protected override async Task OnParametersSetAsync()` | Before each render |
| `Page_Init(...)` | `protected override void OnInitialized()` | Sync initialization |
| `if (!IsPostBack)` | Remove the guard — `OnInitializedAsync` only runs once | Block always executes — correct for first-render code |
| `if (IsPostBack)` (without `!`) | **Dead code — flag for manual review** | Never enters the block in Blazor; move logic to event handlers |

```csharp
// Web Forms
protected void Page_Load(object sender, EventArgs e)
{
    if (!IsPostBack)
    {
        products = GetProducts();
        GridView1.DataBind();
    }
}

// Blazor — OnInitializedAsync runs once on first render (no postback concept)
protected override async Task OnInitializedAsync()
{
    products = await ProductService.GetProductsAsync();
}
```

### Event Handlers

```csharp
// Web Forms
protected void SubmitBtn_Click(object sender, EventArgs e)
{
    Response.Redirect("~/Confirmation");
}

// Blazor — no sender/EventArgs parameters
private void SubmitBtn_Click()
{
    NavigationManager.NavigateTo("/Confirmation");
}
```

### Navigation

| Web Forms | Blazor |
|-----------|--------|
| `Response.Redirect("~/path")` | `NavigationManager.NavigateTo("/path")` |
| `Response.RedirectToRoute(...)` | `NavigationManager.NavigateTo($"/path/{param}")` |
| `Server.Transfer("~/page.aspx")` | `NavigationManager.NavigateTo("/page")` |

### Query String / Route Parameters

```csharp
// Web Forms (Model Binding)
public IQueryable<Product> GetProducts([QueryString] int? categoryId) { ... }

// Blazor
[SupplyParameterFromQuery] public int? CategoryId { get; set; }
```

```csharp
// Web Forms (RouteData)
public void GetProduct([RouteData] int productId) { ... }

// Blazor
@page "/Products/{ProductId:int}"
[Parameter] public int ProductId { get; set; }
```

---

## Data Binding Migration

### Collection-Bound Controls

For GridView, ListView, Repeater, DataList, DataGrid:

| Web Forms Pattern | Blazor Pattern |
|-------------------|----------------|
| `SelectMethod="GetProducts"` | Load data in `OnInitializedAsync` and bind to a list property |
| `ItemType="Namespace.Product"` | `Product` (use directly in `@foreach`) |
| `DataSource=<%# GetItems() %>` + `DataBind()` | `products = await ProductService.GetProductsAsync()` in `OnInitializedAsync` |
| `DataKeyNames="ProductID"` | Track key in component state |

```razor
@inject IProductService ProductService

<table>
    <thead><tr><th>Name</th><th>Price</th></tr></thead>
    <tbody>
        @foreach (var item in products)
        {
            <tr>
                <td>@item.Name</td>
                <td>@item.UnitPrice.ToString("C")</td>
            </tr>
        }
    </tbody>
</table>

@code {
    private List<Product> products = [];

    protected override async Task OnInitializedAsync()
    {
        products = await ProductService.GetProductsAsync();
    }
}
```

### Single-Record Controls

For FormView, DetailsView:

| Web Forms Pattern | Blazor Pattern |
|-------------------|----------------|
| `SelectMethod="GetProduct"` | `product = await ProductService.GetProductAsync(id)` in `OnInitializedAsync` |
| `ItemType="Namespace.Product"` | Use `Product` type directly in markup |

### Template Binding

| Web Forms | Blazor | Notes |
|-----------|--------|-------|
| `<%# Item.Name %>` | `@item.Name` | Inside `@foreach` loop |
| `<%# Eval("Name") %>` | `@item.Name` | Direct property access replaces reflection |
| `<%# Bind("Name") %>` | `@bind-Value="item.Name"` | Two-way in edit templates |

---

## Master Page → Layout Migration

### Web Forms Master Page

```html
<%@ Master Language="C#" CodeBehind="Site.master.cs" Inherits="MyApp.SiteMaster" %>
<!DOCTYPE html>
<html>
<head runat="server">
    <title><%: Page.Title %></title>
    <asp:ContentPlaceHolder ID="HeadContent" runat="server" />
</head>
<body>
    <form runat="server">
        <asp:ScriptManager runat="server" />
        <header>
            <nav><asp:Menu ID="MainMenu" runat="server" ... /></nav>
        </header>
        <main>
            <asp:ContentPlaceHolder ID="MainContent" runat="server" />
        </main>
        <footer>© <%: DateTime.Now.Year %></footer>
    </form>
</body>
</html>
```

### Blazor Layout Equivalent

```razor
@inherits LayoutComponentBase

<header>
    <nav><Menu ... /></nav>
</header>
<main>
    @Body
</main>
<footer>© @DateTime.Now.Year</footer>
```

**Key changes:**
- `<%@ Master %>` → `@inherits LayoutComponentBase`
- `<form runat="server">` → replaced with `<div>` (preserves `id` attribute and CSS block formatting context)
- `<asp:ContentPlaceHolder ID="MainContent">` → `@Body`
- `<asp:ScriptManager>` → remove (Blazor handles JS automatically)
- CSS `<link>` elements from master page `<head>` → `App.razor` `<head>` section (relative `href` paths must be rewritten to absolute, e.g., `CSS/style.css` → `/CSS/style.css`, because `<HeadContent>` resolves from the page URL)
- `<head runat="server">` content → `<HeadContent>` in layout or `App.razor`

### Nested Master Pages → Nested Layouts

```razor
@inherits LayoutComponentBase
@layout MainLayout

<div class="child-wrapper">
    @Body
</div>
```