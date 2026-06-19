# Control Translation Reference

Reference tables for mapping ASP.NET Web Forms server controls to their Blazor equivalents.

**Parent skill:** [migrating-webforms-to-blazor-server](../SKILL.md)

## Contents
- Control Translation Table
- Page Title
- Not Directly Replaceable

---

## Control Translation Table

### Simple Controls (Trivial Migration)

| Web Forms | Blazor | Changes |
|-----------|---------------|---------|
| `<asp:Label ID="x" runat="server" Text="Hello" CssClass="title" />` | `<label class="title">Hello</label>` | Remove `asp:`, `runat`; use plain HTML |
| `<asp:Literal ID="x" runat="server" Text="Hello" />` | `@("Hello")` or just `Hello` | Render text directly |
| `<asp:HyperLink NavigateUrl="~/About" Text="About" runat="server" />` | `<a href="/About">About</a>` | `~/` → `/` |
| `<asp:Image ImageUrl="~/images/logo.png" runat="server" />` | `<img src="/images/logo.png" />` | `~/` → `/` |
| `<asp:Panel CssClass="container" runat="server">` | `<div class="container">` | Use `<div>` |
| `<asp:PlaceHolder runat="server">` | (remove — just use the inner content) | No equivalent needed |
| `<asp:HiddenField Value="x" runat="server" />` | `<input type="hidden" @bind="x" />` | Use standard HTML |

### Form Controls (Easy Migration)

| Web Forms | Blazor | Notes |
|-----------|--------|-------|
| `<asp:TextBox ID="Name" runat="server" />` | `<input @bind="model.Name" />` | Use `@bind` |
| `<asp:TextBox TextMode="Password" runat="server" />` | `<input type="password" @bind="model.Password" />` | `type="password"` |
| `<asp:TextBox TextMode="MultiLine" Rows="5" runat="server" />` | `<textarea @bind="model.Notes" rows="5"></textarea>` | Use `<textarea>` |
| `<asp:DropDownList ID="Category" runat="server" />` | `<select @bind="model.Category">@foreach...</select>` | Use `<select>` with `@foreach` |
| `<asp:CheckBox ID="Active" runat="server" Checked="true" />` | `<input type="checkbox" @bind="model.Active" />` | Use `type="checkbox"` |
| `<asp:RadioButton GroupName="G" runat="server" />` | `<input type="radio" name="G" @bind="model.Selected" />` | Use `type="radio"` |
| `<asp:FileUpload ID="Upload" runat="server" />` | `<InputFile OnChange="HandleFile" />` | Blazor `InputFile` component |
| `<asp:Button Text="Submit" OnClick="Submit_Click" runat="server" />` | `<button @onclick="Submit_Click">Submit</button>` | `@onclick` event |
| `<asp:LinkButton Text="Edit" CommandName="Edit" runat="server" />` | `<a href="#" @onclick="Edit_Click">Edit</a>` | Use anchor with `@onclick` |
| `<asp:ImageButton ImageUrl="~/btn.png" OnClick="Btn_Click" runat="server" />` | `<img src="/btn.png" @onclick="Btn_Click" style="cursor:pointer" />` | `~/` → `/` |

### Validation Controls (Use EditForm Pattern)

Blazor validation uses `<EditForm>` with data annotations and `<ValidationMessage>`. Replace all Web Forms validators with this pattern:

```razor
<EditForm Model="@_model" OnValidSubmit="HandleSubmit">
    <DataAnnotationsValidator />
    <ValidationSummary />

    <div>
        <label>Name</label>
        <InputText @bind-Value="_model.Name" />
        <ValidationMessage For="@(() => _model.Name)" />
    </div>

    <div>
        <label>Age</label>
        <InputNumber @bind-Value="_model.Age" />
        <ValidationMessage For="@(() => _model.Age)" />
    </div>

    <button type="submit">Submit</button>
</EditForm>

@code {
    private MyModel _model = new();

    private void HandleSubmit()
    {
        // Only called when model is valid
    }
}
```

```csharp
// Model with data annotations
public class MyModel
{
    [Required(ErrorMessage = "Name is required")]
    public string Name { get; set; } = "";

    [Range(1, 100, ErrorMessage = "Age must be between 1 and 100")]
    public int Age { get; set; }

    [RegularExpression(@"\d+", ErrorMessage = "Must be numeric")]
    public string Code { get; set; } = "";
}
```

| Web Forms Validator | Blazor Equivalent |
|---------------------|-------------------|
| `<asp:RequiredFieldValidator>` | `[Required]` data annotation + `<ValidationMessage>` |
| `<asp:CompareValidator>` | `[Compare]` data annotation |
| `<asp:RangeValidator>` | `[Range]` data annotation |
| `<asp:RegularExpressionValidator>` | `[RegularExpression]` data annotation |
| `<asp:CustomValidator>` | Custom `ValidationAttribute` or `IValidatableObject` |
| `<asp:ValidationSummary>` | `<ValidationSummary />` inside `<EditForm>` |

### Data Controls (Medium Migration)

#### GridView

```xml
<!-- Web Forms -->
<asp:GridView ID="ProductGrid" runat="server"
    ItemType="WingtipToys.Models.Product"
    SelectMethod="GetProducts"
    AutoGenerateColumns="false"
    AllowPaging="true" PageSize="10">
    <Columns>
        <asp:BoundField DataField="Name" HeaderText="Product" />
        <asp:TemplateField HeaderText="Price">
            <ItemTemplate><%#: Item.UnitPrice.ToString("C") %></ItemTemplate>
        </asp:TemplateField>
    </Columns>
</asp:GridView>
```

```razor
@* Blazor — @foreach table *@
@inject IProductService ProductService

<table>
    <thead>
        <tr>
            <th>Product</th>
            <th>Price</th>
        </tr>
    </thead>
    <tbody>
        @foreach (var item in _products)
        {
            <tr>
                <td>@item.Name</td>
                <td>@item.UnitPrice.ToString("C")</td>
            </tr>
        }
    </tbody>
</table>

@code {
    private List<Product> _products = [];

    protected override async Task OnInitializedAsync()
    {
        _products = await ProductService.GetProductsAsync();
    }
}
```

> **For advanced scenarios** (sorting, pagination, virtualization), use **Microsoft.AspNetCore.Components.QuickGrid**:
> ```bash
> dotnet add package Microsoft.AspNetCore.Components.QuickGrid
> ```
> ```razor
> @using Microsoft.AspNetCore.Components.QuickGrid
>
> <QuickGrid Items="@_products.AsQueryable()" Pagination="@pagination">
>     <PropertyColumn Property="@(p => p.Name)" Sortable="true" />
>     <PropertyColumn Property="@(p => p.UnitPrice)" Format="C" Sortable="true" />
> </QuickGrid>
> <Paginator State="@pagination" />
>
> @code {
>     private List<Product> _products = [];
>     private PaginationState pagination = new PaginationState { ItemsPerPage = 10 };
> }
> ```

#### ListView

```xml
<!-- Web Forms -->
<asp:ListView ID="ProductList" runat="server"
    ItemType="WingtipToys.Models.Product" SelectMethod="GetProducts">
    <ItemTemplate>
        <div class="product">
            <h3><%#: Item.ProductName %></h3>
            <p><%#: Item.UnitPrice.ToString("C") %></p>
        </div>
    </ItemTemplate>
</asp:ListView>
```

```razor
@* Blazor — @foreach with custom markup *@
@foreach (var item in _products)
{
    <div class="product">
        <h3>@item.ProductName</h3>
        <p>@item.UnitPrice.ToString("C")</p>
    </div>
}
```

#### ListView with GroupItemCount (grid layout)

```razor
@* Blazor — group by chunks *@
@foreach (var group in _products.Chunk(4))
{
    <div class="row">
        @foreach (var item in group)
        {
            <div class="col-3">
                <a href="/Products/@item.ProductID">
                    <img src="@item.ImagePath" alt="@item.ProductName" />
                </a>
                <span>@item.ProductName</span>
                <span>@item.UnitPrice.ToString("C")</span>
            </div>
        }
    </div>
}
```

#### Repeater / DataList

```razor
@* Blazor — @foreach loop *@
@foreach (var item in _items)
{
    <div class="item">
        <strong>@item.Name</strong>: @item.Description
    </div>
}
```

#### FormView / DetailsView

```razor
@* Blazor — direct property binding *@
@if (_product != null)
{
    <h2>@_product.ProductName</h2>
    <p>@_product.Description</p>
    <p>Price: @_product.UnitPrice.ToString("C")</p>
}

@code {
    private Product? _product;

    protected override async Task OnInitializedAsync()
    {
        _product = await ProductService.GetProductAsync(ProductId);
    }
}
```

### Navigation Controls

| Web Forms | Blazor | Notes |
|-----------|--------|-------|
| `<asp:Menu>` | Custom `<nav>` with `<NavLink>` components | Use `<NavLink>` for active state |
| `<asp:TreeView>` | Recursive component pattern | Build a custom tree component |
| `<asp:SiteMapPath>` | Custom breadcrumb component | Use `<NavLink>` items |

### AJAX Controls (Replacement)

| Web Forms | Blazor | Notes |
|-----------|--------|-------|
| `<asp:ScriptManager runat="server" />` | (remove) | Blazor handles JS automatically |
| `<asp:ScriptManagerProxy runat="server" />` | (remove) | Not needed |
| `<asp:UpdatePanel runat="server">` | (remove wrapper, keep content) | Blazor re-renders automatically |
| `<asp:UpdateProgress runat="server">` | `@if (_isLoading) { <div>Loading...</div> }` | Use component state |
| `<asp:Timer Interval="5000" runat="server" />` | `PeriodicTimer` in `OnInitializedAsync` | Dispose timer to avoid background-loop leaks |

---

## Page Title

| Web Forms | Blazor |
|-----------|--------|
| `Page.Title = "My Page";` in code-behind | `<PageTitle>My Page</PageTitle>` in `.razor` markup |
| `<title><%: Page.Title %></title>` in master page | `<PageTitle>` component from `Microsoft.AspNetCore.Components.Web` |

```razor
@page "/products"

<PageTitle>Products - My App</PageTitle>

<h1>Products</h1>
```

---

## Not Directly Replaceable

| Control | Alternative |
|---------|------------|
| `SqlDataSource` | Injected service + EF Core |
| `ObjectDataSource` | Injected service |
| `EntityDataSource` | Injected service + EF Core |
| `Wizard` | Multi-step form with component state |
| `Web Parts` | Redesign as Blazor components |
| `Chart` | Use a JavaScript charting library via JS interop, or a Blazor chart package |

### Ajax Control Toolkit Extenders

There is no drop-in package for Ajax Control Toolkit extenders in Blazor. Each control is replaced individually using native HTML5, Blazor component state, or CSS — most require very little effort:

| ACT Extender | Native Replacement | Effort |
|---|---|---|
| `ConfirmButtonExtender` | `@onclick` + `IJSRuntime.InvokeAsync<bool>("confirm", ...)` | Low |
| `AutoCompleteExtender` | HTML5 `<datalist>` + `@oninput` handler | Low |
| `CalendarExtender` | `<input type="date">` | Trivial |
| `SliderExtender` | `<input type="range">` | Trivial |
| `NumericUpDownExtender` | `<input type="number" min max step>` | Trivial |
| `TextBoxWatermarkExtender` | `placeholder` attribute | Trivial |
| `MaskedEditExtender` | `pattern` attribute or JS interop | Low |
| `FilteredTextBoxExtender` | `@oninput` handler filtering characters | Low |
| `CollapsiblePanelExtender` | `@if (_expanded)` state toggle | Low |
| `Accordion` / `AccordionPane` | HTML5 `<details>`/`<summary>` | Trivial |
| `TabContainer` / `TabPanel` | Blazor state tracking active tab + CSS | Low |
| `ModalPopupExtender` | `@if (_showModal)` with overlay div | Low |
| `DropShadowExtender` | CSS `box-shadow` | Trivial |
| `RoundedCornersExtender` | CSS `border-radius` | Trivial |
| `AlwaysVisibleControlExtender` | CSS `position: fixed` | Trivial |
| `DragPanelExtender` | JS interop or third-party library | Medium |

For per-control code examples, use the Ajax Control Toolkit migration reference in this skill.
