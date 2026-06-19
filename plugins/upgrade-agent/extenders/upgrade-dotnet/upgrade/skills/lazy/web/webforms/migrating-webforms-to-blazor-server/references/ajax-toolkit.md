# Ajax Control Toolkit Migration

Patterns for migrating ASP.NET **Ajax Control Toolkit** extenders and containers to Blazor equivalents.

**Parent skill:** [migrating-webforms-to-blazor-server](../SKILL.md)

## Contents
- Overview
- Control Translation Table
- Detection: How to Identify Ajax Control Toolkit Usage
- Per-Control Migration Patterns
- Unsupported Controls

---

## Overview

### What is the Ajax Control Toolkit?

The Ajax Control Toolkit (ACT) is a library of reusable ASP.NET Web Forms components that add rich client-side JavaScript behaviors — modals, popups, autocomplete, tabs, accordions, sliders, and more. In Web Forms markup, they appear as `<ajaxToolkit:*>` prefixed components.

**Examples:**
- `<ajaxToolkit:ConfirmButtonExtender>` — Browser confirmation dialog
- `<ajaxToolkit:AutoCompleteExtender>` — Typeahead suggestions
- `<ajaxToolkit:ModalPopupExtender>` — Modal dialog with overlay
- `<ajaxToolkit:TabContainer>` — Tabbed content panes
- `<ajaxToolkit:Accordion>` — Collapsible accordion panels

### There is No Drop-in Package

Unlike the core Web Forms controls, there is no single NuGet package that provides drop-in Blazor replacements for Ajax Control Toolkit extenders. Each control must be replaced manually using native HTML5, Blazor component state, or JS interop — depending on the control.

The good news: most ACT behaviors have **direct HTML5 equivalents** that require zero JavaScript, or straightforward Blazor component state patterns.

---

## Control Translation Table

| Web Forms | Blazor / HTML5 Equivalent | Effort |
|-----------|----------------------------------|--------|
| `<ajaxToolkit:ConfirmButtonExtender>` | `@onclick` with `IJSRuntime.InvokeAsync<bool>("confirm", "message")` | Low |
| `<ajaxToolkit:AutoCompleteExtender>` | HTML5 `<datalist>` or `<input>` + Blazor filtering with `@bind` + `@oninput` | Low–Medium |
| `<ajaxToolkit:CalendarExtender>` | `<input type="date">` (HTML5 native date picker) | Trivial |
| `<ajaxToolkit:MaskedEditExtender>` | `<input pattern="...">` (HTML5) or `inputmode` attribute | Low |
| `<ajaxToolkit:FilteredTextBoxExtender>` | `@oninput` handler that filters characters in `@code` | Low |
| `<ajaxToolkit:SliderExtender>` | `<input type="range" @bind="value">` (HTML5 native) | Trivial |
| `<ajaxToolkit:NumericUpDownExtender>` | `<input type="number" min="..." max="..." step="...">` (HTML5 native) | Trivial |
| `<ajaxToolkit:ToggleButtonExtender>` | `<input type="checkbox">` with custom CSS styling | Low |
| `<ajaxToolkit:CollapsiblePanelExtender>` | `<details>`/`<summary>` (HTML5) or Blazor `@if (_expanded)` state | Trivial |
| `<ajaxToolkit:Accordion>` / `<ajaxToolkit:AccordionPane>` | `<details>`/`<summary>` per pane, or Blazor state tracking active pane | Low |
| `<ajaxToolkit:TabContainer>` / `<ajaxToolkit:TabPanel>` | Blazor component state for active tab + CSS classes | Low |
| `<ajaxToolkit:ModalPopupExtender>` | `<dialog>` element (HTML5) or Blazor `@if (_showModal)` with overlay | Low–Medium |
| `<ajaxToolkit:HoverMenuExtender>` | CSS `:hover` + `position: absolute` dropdown | Low |
| `<ajaxToolkit:PopupControlExtender>` | Blazor `@onclick` toggle + `@if (_showPopup)` | Low |
| `<ajaxToolkit:TextBoxWatermarkExtender>` | HTML5 `placeholder` attribute | Trivial |
| `<ajaxToolkit:DropShadowExtender>` | CSS `box-shadow` | Trivial |
| `<ajaxToolkit:RoundedCornersExtender>` | CSS `border-radius` | Trivial |
| `<ajaxToolkit:AlwaysVisibleControlExtender>` | CSS `position: fixed` | Trivial |
| `<ajaxToolkit:UpdatePanelAnimationExtender>` | CSS transitions on state change | Low |
| `<ajaxToolkit:ValidatorCalloutExtender>` | `<ValidationMessage For="...">` inside `<EditForm>` | Low |
| `<ajaxToolkit:DragPanelExtender>` | JS interop or third-party Blazor drag-drop library | Medium |
| `<ajaxToolkit:ResizableControlExtender>` | CSS `resize: both; overflow: auto` | Trivial |

---

## Detection: How to Identify Ajax Control Toolkit Usage

### 1. Assembly Registration Directives

Look for `<%@ Register %>` directives that reference AjaxControlToolkit:

```html
<%@ Register Assembly="AjaxControlToolkit" 
             Namespace="AjaxControlToolkit" 
             TagPrefix="ajaxToolkit" %>
```

**Action:** Remove this directive entirely in Blazor (no equivalent needed).

### 2. ToolkitScriptManager

Look for this pattern:

```html
<ajaxToolkit:ToolkitScriptManager ID="ToolkitScriptManager1" runat="server" />
```

**Action:** Delete it. Blazor handles script loading automatically.

### 3. Extender and Container Components

Any component with the `ajaxToolkit:` prefix:

```html
<ajaxToolkit:ConfirmButtonExtender ID="cbe1" runat="server"
    TargetControlID="btnDelete"
    ConfirmText="Are you sure?" />
```

---

## Per-Control Migration Patterns

### ConfirmButtonExtender — Confirmation Dialog

**Web Forms:**
```html
<asp:Button ID="btnDelete" Text="Delete" OnClick="Delete_Click" runat="server" />
<ajaxToolkit:ConfirmButtonExtender runat="server"
    TargetControlID="btnDelete"
    ConfirmText="Delete this record permanently?" />
```

**Blazor:**
```razor
<button @onclick="ConfirmAndDelete">Delete</button>

@code {
    [Inject] IJSRuntime JS { get; set; } = default!;

    private async Task ConfirmAndDelete()
    {
        if (await JS.InvokeAsync<bool>("confirm", "Delete this record permanently?"))
        {
            // Delete logic here
        }
    }
}
```

---

### AutoCompleteExtender — Typeahead

**Web Forms:**
```html
<asp:TextBox ID="searchBox" runat="server" />
<ajaxToolkit:AutoCompleteExtender runat="server"
    TargetControlID="searchBox"
    ServiceMethod="GetSuggestions"
    MinimumPrefixLength="2" />
```

**Blazor (using HTML5 `<datalist>`):**
```razor
<input list="suggestions" @bind="_searchText" @oninput="UpdateSuggestions" />
<datalist id="suggestions">
    @foreach (var s in _suggestions)
    {
        <option value="@s" />
    }
</datalist>

@code {
    private string _searchText = "";
    private List<string> _suggestions = [];

    private async Task UpdateSuggestions(ChangeEventArgs e)
    {
        var prefix = e.Value?.ToString() ?? "";
        if (prefix.Length >= 2)
        {
            _suggestions = await ProductService.SearchAsync(prefix);
        }
    }
}
```

---

### CalendarExtender — Date Picker

**Web Forms:**
```html
<asp:TextBox ID="dateBox" runat="server" />
<ajaxToolkit:CalendarExtender runat="server" TargetControlID="dateBox" />
```

**Blazor:**
```razor
<input type="date" @bind="_selectedDate" class="form-control" />

@code {
    private DateTime _selectedDate = DateTime.Today;
}
```

HTML5 `<input type="date">` renders a native date picker in all modern browsers.

---

### TabContainer / TabPanel — Tabs

**Web Forms:**
```html
<ajaxToolkit:TabContainer runat="server">
    <ajaxToolkit:TabPanel HeaderText="Tab 1">Content 1</ajaxToolkit:TabPanel>
    <ajaxToolkit:TabPanel HeaderText="Tab 2">Content 2</ajaxToolkit:TabPanel>
</ajaxToolkit:TabContainer>
```

**Blazor:**
```razor
<div class="tabs">
    <div class="tab-headers">
        <button class="@TabClass(0)" @onclick="@(() => _activeTab = 0)">Tab 1</button>
        <button class="@TabClass(1)" @onclick="@(() => _activeTab = 1)">Tab 2</button>
    </div>
    <div class="tab-content">
        @if (_activeTab == 0) { <p>Content 1</p> }
        @if (_activeTab == 1) { <p>Content 2</p> }
    </div>
</div>

@code {
    private int _activeTab = 0;
    private string TabClass(int i) => i == _activeTab ? "tab active" : "tab";
}
```

---

### Accordion / AccordionPane — Collapsible Panels

**Web Forms:**
```html
<ajaxToolkit:Accordion runat="server">
    <Panes>
        <ajaxToolkit:AccordionPane>
            <Header>Section 1</Header>
            <Content>Details...</Content>
        </ajaxToolkit:AccordionPane>
    </Panes>
</ajaxToolkit:Accordion>
```

**Blazor (using HTML5 `<details>`):**
```razor
<details>
    <summary>Section 1</summary>
    <p>Details...</p>
</details>
<details>
    <summary>Section 2</summary>
    <p>More details...</p>
</details>
```

HTML5 `<details>`/`<summary>` is fully interactive with no JavaScript required.

---

### ModalPopupExtender — Modal Dialog

**Web Forms:**
```html
<asp:Button ID="btnOpen" Text="Open" runat="server" />
<ajaxToolkit:ModalPopupExtender runat="server"
    TargetControlID="btnOpen"
    PopupControlID="dialogPanel" />
<asp:Panel ID="dialogPanel" runat="server" style="display:none">
    Modal content here
    <asp:Button ID="btnClose" Text="Close" runat="server" />
</asp:Panel>
```

**Blazor:**
```razor
<button @onclick="@(() => _showModal = true)">Open</button>

@if (_showModal)
{
    <div class="modal-overlay" @onclick="@(() => _showModal = false)">
        <div class="modal-dialog" @onclick:stopPropagation>
            <p>Modal content here</p>
            <button @onclick="@(() => _showModal = false)">Close</button>
        </div>
    </div>
}

@code {
    private bool _showModal = false;
}
```

Or use the HTML5 `<dialog>` element with `IJSRuntime` to call `.showModal()`.

---

### CollapsiblePanelExtender — Expand/Collapse

**Web Forms:**
```html
<ajaxToolkit:CollapsiblePanelExtender runat="server"
    TargetControlID="myPanel"
    CollapseControlID="btnToggle" />
```

**Blazor:**
```razor
<button @onclick="@(() => _expanded = !_expanded)">Toggle</button>

@if (_expanded)
{
    <div>Panel content here</div>
}

@code {
    private bool _expanded = true;
}
```

---

### SliderExtender — Range Slider

**Web Forms:**
```html
<ajaxToolkit:SliderExtender runat="server" TargetControlID="sliderInput" Minimum="0" Maximum="100" />
```

**Blazor:**
```razor
<input type="range" min="0" max="100" @bind="_value" />
<span>@_value</span>

@code {
    private int _value = 50;
}
```

---

### MaskedEditExtender — Input Mask

**Web Forms:**
```html
<asp:TextBox ID="phoneBox" runat="server" />
<ajaxToolkit:MaskedEditExtender runat="server"
    TargetControlID="phoneBox"
    Mask="(999) 999-9999" />
```

**Blazor:** Use HTML5 `pattern` for validation, and `placeholder` for guidance:
```razor
<input type="tel"
       pattern="\(\d{3}\) \d{3}-\d{4}"
       placeholder="(555) 555-5555"
       @bind="_phone"
       class="form-control" />
```

For true character-by-character masking, use JS interop or a Blazor input masking library (e.g., `Blazored.FluentValidation` or IMask.js via interop).

---

### ValidatorCalloutExtender — Validation Callouts

**Web Forms:**
```html
<ajaxToolkit:ValidatorCalloutExtender runat="server" TargetControlID="emailBox" />
```

**Blazor:** Use `<EditForm>` with `<ValidationMessage>`:
```razor
<EditForm Model="@_model" OnValidSubmit="HandleSubmit">
    <DataAnnotationsValidator />
    <div>
        <InputText @bind-Value="_model.Email" />
        <ValidationMessage For="@(() => _model.Email)" />
    </div>
    <button type="submit">Submit</button>
</EditForm>
```

---

### CSS-Only Replacements (Trivial)

These ACT extenders are replaced entirely by CSS:

| ACT Extender | CSS Replacement |
|---|---|
| `DropShadowExtender` | `box-shadow: 5px 5px 10px rgba(0,0,0,0.5)` |
| `RoundedCornersExtender` | `border-radius: 10px` |
| `AlwaysVisibleControlExtender` | `position: fixed; top: 10px; right: 10px` |
| `TextBoxWatermarkExtender` | `placeholder="..."` attribute on `<input>` |
| `ResizableControlExtender` | `resize: both; overflow: auto` |

---

## Unsupported Controls

These require manual JS interop or a third-party Blazor library:

| ACT Extender | Replacement Strategy |
|---|---|
| `DragPanelExtender` | JS interop with pointer events, or a Blazor drag-drop library |
| `UpdatePanelAnimationExtender` | CSS `transition` + Blazor state changes |
| `HoverMenuExtender` | CSS `:hover` + `position: absolute` |

---

## See Also

For general control prefix removal patterns and full control mapping, review the parent skill's reference list and open the relevant reference from there.