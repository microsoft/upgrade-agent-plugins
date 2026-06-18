# Markup Transformation Reference

Complete tables and patterns for converting Web Forms markup to Blazor.

**Parent skill:** [migrating-webforms-to-blazor-server](../SKILL.md)

## Contents
- File Conversion
- Directive Conversion
- Expression Conversion
- URL Conversion
- Content and Layout Conversion
- Form Wrapper
- Control Prefix Removal
- runat="server" Removal
- Ajax Control Toolkit Prefix Removal

---

## File Conversion

| Web Forms | Blazor | Notes |
|-----------|--------|-------|
| `MyPage.aspx` | `MyPage.razor` | Page markup |
| `MyPage.aspx.cs` | `MyPage.razor.cs` | Code-behind (keep as partial class) |
| `MyControl.ascx` | `MyControl.razor` | User control markup |
| `MyControl.ascx.cs` | `MyControl.razor.cs` | User control code-behind |
| `Site.Master` | `MainLayout.razor` | Master page → Layout |
| `Site.Master.cs` | `MainLayout.razor.cs` | Layout code-behind |

---

## Directive Conversion

| Web Forms Directive | Blazor Equivalent |
|--------------------|-------------------|
| `<%@ Page Title="X" Language="C#" MasterPageFile="~/Site.Master" AutoEventWireup="true" CodeBehind="Y.aspx.cs" Inherits="NS.Y" %>` | `@page "/route"` |
| `<%@ Master Language="C#" ... %>` | `@inherits LayoutComponentBase` |
| `<%@ Control Language="C#" ... %>` | (remove — components don't need directives) |
| `<%@ Register TagPrefix="uc" TagName="X" Src="~/Controls/X.ascx" %>` | `@using MyApp.Components` (if needed) |
| `<%@ Import Namespace="X" %>` | `@using X` |

**Drop entirely** (no Blazor equivalent): 
- `AutoEventWireup`
- `CodeBehind` / `CodeFile`
- `Inherits`
- `EnableViewState` / `ViewStateMode`
- `MasterPageFile`
- `ValidateRequest`
- `MaintainScrollPositionOnPostBack`
- `ClientIDMode`
- `EnableTheming`
- `SkinID`

---

## Expression Conversion

| Web Forms Expression | Blazor Equivalent | Notes |
|---------------------|-------------------|-------|
| `<%: expression %>` | `@(expression)` | HTML-encoded output |
| `<%= expression %>` | `@(expression)` | Blazor always HTML-encodes |
| `<%# Item.Property %>` | `@context.Property` | Inside data-bound templates |
| `<%#: Item.Property %>` | `@context.Property` | Same — Blazor always encodes |
| `<%# Eval("Property") %>` | `@context.Property` | Direct property access |
| `<%# Bind("Property") %>` | `@bind-Value="context.Property"` | Two-way binding |
| `<%# string.Format("{0:C}", Item.Price) %>` | `@context.Price.ToString("C")` | Format in code |
| `<%$ RouteValue:id %>` | `@Id` (with `[Parameter]`) | Route parameters |
| `<%-- comment --%>` | `@* comment *@` | Razor comments |
| `<% if (condition) { %>` | `@if (condition) {` | Control flow |
| `<% foreach (var x in items) { %>` | `@foreach (var x in items) {` | Loops |
| `<% } %>` | `}` | Closing brace |

---

## URL Conversion

| Web Forms | Blazor |
|-----------|--------|
| `href="~/Products"` | `href="/Products"` |
| `src="~/images/logo.png"` | `src="/images/logo.png"` |
| `NavigateUrl="~/Products/<%: Item.ID %>"` | `NavigateUrl="@($"/Products/{context.ID}")"` |
| `ImageUrl="~/images/product.png"` | `ImageUrl="/images/product.png"` |

The `~/` application root token must be replaced with `/` because Blazor uses different path resolution.

---

## Content and Layout Conversion

| Web Forms | Blazor | Notes |
|-----------|--------|-------|
| `<asp:Content ContentPlaceHolderID="MainContent" runat="server">` | (remove wrapper, keep inner content) | Page body IS the content |
| `<asp:Content ContentPlaceHolderID="HeadContent" runat="server">` | `<HeadContent>` ... `</HeadContent>` | Preserves head content |
| `<asp:ContentPlaceHolder ID="MainContent" runat="server" />` | `@Body` | In layout files |
| `<asp:ContentPlaceHolder ID="HeadContent" runat="server" />` | `<HeadOutlet />` | In layout files |

### Master Page to Layout Example

**Web Forms (Site.Master):**
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
        <header>
            <nav>...</nav>
        </header>
        <main>
            <asp:ContentPlaceHolder ID="MainContent" runat="server" />
        </main>
        <footer>© <%: DateTime.Now.Year %></footer>
    </form>
</body>
</html>
```

**Blazor (MainLayout.razor):**
```razor
@inherits LayoutComponentBase

<PageTitle>My App</PageTitle>

<header>
    <nav>...</nav>
</header>
<main>
    @Body
</main>
<footer>© @DateTime.Now.Year</footer>
```

**Key changes:**
- `<%@ Master %>` → `@inherits LayoutComponentBase`
- `<form runat="server">` → removed (use `<div>` if CSS block formatting context needed)
- `<asp:ContentPlaceHolder ID="MainContent">` → `@Body`
- `<title><%: Page.Title %></title>` → `<PageTitle>` component in each page's markup

---

## Form Wrapper

Web Forms requires `<form runat="server">` for server controls. Blazor doesn't need this.

**Web Forms:**
```html
<form runat="server" id="mainForm">
    <asp:Button Text="Submit" ... />
</form>
```

**Blazor replacement options:**

1. **Remove entirely** (if no CSS dependency):
```razor
<button type="submit">Submit</button>
```

2. **Replace with `<div>`** (preserves CSS block formatting context):
```razor
<div id="mainForm">
    <button type="submit">Submit</button>
</div>
```

3. **Use `<EditForm>`** (for validation scenarios):
```razor
<EditForm Model="@model" OnValidSubmit="HandleSubmit">
    <DataAnnotationsValidator />
    <ValidationSummary />
    <button type="submit">Submit</button>
</EditForm>
```

Many Web Forms stylesheets use `position: relative` offsets that depend on the form wrapper as the containing block. Replacing with `<div>` preserves this behavior.

---

## Control Prefix Removal

Remove `asp:` from all control tags and convert to native HTML/Blazor equivalents:

```html
<!-- Before -->
<asp:Label ID="lblMessage" runat="server" Text="Hello" />
<asp:Button ID="btnSubmit" runat="server" Text="Submit" OnClick="Submit_Click" />
<asp:GridView ID="GridView1" runat="server" />

<!-- After (Blazor) -->
<label>Hello</label>
<button @onclick="Submit_Click">Submit</button>
@* GridView → <table> with @foreach, or use Microsoft.AspNetCore.Components.QuickGrid for advanced scenarios *@
```

**Pattern:** `<asp:ControlName` → native HTML element or Blazor component

---

## runat="server" Removal

Remove all `runat="server"` attributes:

```html
<!-- Before -->
<asp:TextBox ID="txtName" runat="server" />
<div id="container" runat="server">

<!-- After (Blazor) -->
<input @bind="txtName" />
<div id="container">
```

Blazor components don't need `runat="server"`.

For plain HTML elements with `runat="server"`, just remove the attribute. If you need programmatic access in code-behind, use `@ref`:

```razor
<div @ref="_containerRef">
```

```csharp
private ElementReference _containerRef;
```

---

## Ajax Control Toolkit Prefix Removal

Do not perform prefix-only renames for Ajax Control Toolkit controls. Replace each `ajaxToolkit:` control with native HTML/Blazor patterns (or JS interop where needed). For complete control-by-control replacements, open the Ajax Control Toolkit reference via the parent skill's reference list.

```html
<!-- Before -->
<ajaxToolkit:ConfirmButtonExtender ID="cbe1" runat="server" TargetControlID="btnDelete" ConfirmText="Delete this record?" />
<asp:Button ID="btnDelete" runat="server" Text="Delete" />

<!-- After (Blazor) -->
<button @onclick="ConfirmAndDelete">Delete</button>
```

```razor
@code {
    [Inject] private IJSRuntime JS { get; set; } = default!;

    private async Task ConfirmAndDelete()
    {
        if (await JS.InvokeAsync<bool>("confirm", "Delete this record?"))
        {
            // delete logic
        }
    }
}
```
