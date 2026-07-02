## Contents
- Use the heading outline to navigate sections quickly.
## Overview

WinForms data binding connects UI controls to data sources through:

- **BindingSource** - Mediator component between data and controls
- **INotifyPropertyChanged** - Interface for property change notifications
- **BindingList<T>** - Collection with change notification support
- **Binding** - Individual property-to-property connections
- **DataSourceUpdateMode** - Controls when data flows from UI to source

## Breaking Changes: .NET Framework vs .NET 8+

Understanding version differences is critical for migration and new development:

| Feature | .NET Framework ≤ 4.8.1 | .NET 8+ |
|---------|----------------------|---------|
| Typed DataSets | Designer supported | Code-only (legacy, not recommended) |
| Object Binding | Supported | Enhanced UI, fully supported |
| Data Sources Window | Available | Not available |
| ICommand Support | Not available | Built-in via `Command` property |
| DataContext | Not available | Ambient property for hierarchical binding |

**Recommendation:** Use object binding with BindingSource for all new development in .NET 8+.

## Core Requirements

### INotifyPropertyChanged Implementation

**Required for:** Property change notifications from data objects to UI controls.

```csharp
public class Person : INotifyPropertyChanged
{
    private string _name = string.Empty;
    
    public string Name
    {
        get => _name;
        set
        {
            if (_name != value)
            {
                _name = value;
                OnPropertyChanged();
            }
        }
    }
    
    public event PropertyChangedEventHandler? PropertyChanged;
    
    protected void OnPropertyChanged([CallerMemberName] string? propertyName = null)
        => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
}
```

**Key Points:**

- Raise PropertyChanged ONLY when value actually changes
- Use CallerMemberName to avoid magic strings
- Make event nullable for .NET 8+ NRT support

### BindingList<T> for Collections

**Required for:** Collection change notifications (add, remove, clear).

```csharp
BindingList<Person> people = new BindingList<Person>();
dataGridView1.DataSource = people;

// Changes automatically reflect in UI
people.Add(new Person { Name = "John Doe" });
people.RemoveAt(0);
```

**Why not List<T>?** List<T> doesn't notify UI of collection changes. BindingList<T> implements IBindingList which WinForms understands.

## BindingSource Component

Acts as a mediator between data sources and bound controls, providing:

- Currency management (current item tracking)
- Sorting and filtering
- Change notification
- Designer support

### Basic Pattern

**In Designer (InitializeComponent):**

```csharp
personBindingSource = new BindingSource(components);
personBindingSource.DataSource = typeof(MyApp.Models.Person);

_txtName.DataBindings.Add(
    new Binding("Text", personBindingSource, "Name", true));
_txtEmail.DataBindings.Add(
    new Binding("Text", personBindingSource, "Email", true));
```

**In Code (Form constructor or Load event):**

```csharp
// Set actual instance
personBindingSource.DataSource = new Person { Name = "John Doe" };

// Or for collections
personBindingSource.DataSource = new BindingList<Person> { /* ... */ };
```

### Why Two Steps?

1. **Designer compatibility** - typeof() in InitializeComponent allows Designer to discover properties
2. **Runtime flexibility** - Actual instance set in code, can be from database, service, etc.

## DataSourceUpdateMode

Controls WHEN changes flow from UI control back to data source:

| Mode | Behavior | Use Case |
|------|----------|----------|
| `OnValidation` | Updates when control loses focus | Default; most common |
| `OnPropertyChanged` | Updates immediately on every keystroke | Real-time validation, search-as-you-type |
| `Never` | One-way binding (source → control only) | Read-only displays, calculated fields |

**Example:**

```csharp
// Update on every keystroke for live search
_txtSearch.DataBindings.Add(
    new Binding("Text", searchBindingSource, "SearchTerm", 
        true, DataSourceUpdateMode.OnPropertyChanged));

// Update on blur for normal data entry
_txtName.DataBindings.Add(
    new Binding("Text", personBindingSource, "Name", 
        true, DataSourceUpdateMode.OnValidation));
```

## Adding Object DataSources for Designer Support

Create `.datasource` file in `Properties/DataSources/` directory:

**File:** `Properties/DataSources/Person.datasource`

```xml
<?xml version="1.0" encoding="utf-8"?>
<GenericObjectDataSource DisplayName="Person" Version="1.0" 
    xmlns="urn:schemas-microsoft-com:xml-msdatasource">
  <TypeInfo>MyApp.Models.Person, MyApp.Models, Version=1.0.0.0, Culture=neutral, PublicKeyToken=null</TypeInfo>
</GenericObjectDataSource>
```

**Benefits:**

- Designer shows available properties
- IntelliSense when creating bindings
- Visual binding configuration

**Create from VS Code:**

1. Create XML file manually in Properties/DataSources/
2. Update TypeInfo with your full type name
3. Restart VS Code for Designer to pick up

## ObservableCollection Adapter

**When needed:** Sharing ViewModels between WinForms and WPF/MAUI, or using MVVM Community Toolkit patterns that use ObservableCollection<T>.

**Problem:** ObservableCollection<T> uses INotifyCollectionChanged, but WinForms requires IBindingList.

**Solution:** Adapter pattern to bridge the two:

```csharp
public class ObservableBindingList<T> : BindingList<T>
{
    private ObservableCollection<T>? _observableCollection;

    public ObservableBindingList(ObservableCollection<T> observableCollection)
    {
        _observableCollection = observableCollection;
        
        // Initial population
        foreach (T item in _observableCollection)
            Add(item);
        
        // Subscribe to changes
        _observableCollection.CollectionChanged += OnCollectionChanged;
    }

    private void OnCollectionChanged(object? sender, NotifyCollectionChangedEventArgs e)
    {
        switch (e.Action)
        {
            case NotifyCollectionChangedAction.Add:
                if (e.NewItems is not null)
                    foreach (T item in e.NewItems)
                        Add(item);
                break;
                
            case NotifyCollectionChangedAction.Remove:
                if (e.OldItems is not null)
                    foreach (T item in e.OldItems)
                        Remove(item);
                break;
                
            case NotifyCollectionChangedAction.Reset:
                Clear();
                if (_observableCollection is not null)
                    foreach (T item in _observableCollection)
                        Add(item);
                break;
        }
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing && _observableCollection is not null)
        {
            _observableCollection.CollectionChanged -= OnCollectionChanged;
            _observableCollection = null;
        }
        base.Dispose(disposing);
    }
}
```

**Usage:**

```csharp
// In ViewModel (shared between WinForms and WPF)
public ObservableCollection<Person> People { get; } = new();

// In WinForms Form
_bindingAdapter = new ObservableBindingList<Person>(viewModel.People);
dataGridView1.DataSource = _bindingAdapter;

// Don't forget to dispose!
protected override void Dispose(bool disposing)
{
    if (disposing)
    {
        _bindingAdapter?.Dispose();
        components?.Dispose();
    }
    base.Dispose(disposing);
}
```

## Value Conversion (IValueConverter Workaround)

WinForms doesn't have IValueConverter, but you can use `Format` and `Parse` events on Binding:

```csharp
private void SetupCurrencyBinding()
{
    Binding binding = new Binding("Text", personBindingSource, "Salary", true);
    
    // Format: Data source → Control (display)
    binding.Format += (s, e) =>
    {
        if (e.Value is decimal d)
            e.Value = d.ToString("C2");
    };
    
    // Parse: Control → Data source (user input)
    binding.Parse += (s, e) =>
    {
        if (e.Value is string str && 
            decimal.TryParse(str, NumberStyles.Currency, null, out decimal d))
            e.Value = d;
    };
    
    _txtSalary.DataBindings.Add(binding);
}
```

**Common Conversions:**

- Currency formatting
- Date formatting
- Boolean to Yes/No text
- Enum to display text
- Number rounding

## Master-Detail Binding

Display related data in separate controls (e.g., Customers and their Orders):

```csharp
// Customer BindingSource
BindingSource customerBindingSource = new()
{
    DataSource = typeof(Customer)
};

// Orders BindingSource - bound to Customer's Orders property
BindingSource ordersBindingSource = new()
{
    DataSource = customerBindingSource,
    DataMember = "Orders"  // Navigation property name
};

// Set up controls
dataGridView1.DataSource = customerBindingSource;  // Master
dataGridView2.DataSource = ordersBindingSource;    // Detail

// Load data
customerBindingSource.DataSource = GetCustomers();
```

**How it works:**

- When current customer changes in dataGridView1
- ordersBindingSource automatically shows that customer's orders
- No manual synchronization code needed!

## Validation

### IDataErrorInfo Implementation

```csharp
public class Person : INotifyPropertyChanged, IDataErrorInfo
{
    private string _name = string.Empty;
    private int _age;
    
    public string Name
    {
        get => _name;
        set
        {
            if (_name != value)
            {
                _name = value;
                OnPropertyChanged();
            }
        }
    }
    
    public int Age
    {
        get => _age;
        set
        {
            if (_age != value)
            {
                _age = value;
                OnPropertyChanged();
            }
        }
    }
    
    // IDataErrorInfo implementation
    public string Error => string.Empty;
    
    public string this[string columnName] => columnName switch
    {
        nameof(Name) when string.IsNullOrWhiteSpace(Name) 
            => "Name is required",
        nameof(Age) when Age < 0 || Age > 120 
            => "Age must be between 0 and 120",
        _ => string.Empty
    };
    
    public event PropertyChangedEventHandler? PropertyChanged;
    protected void OnPropertyChanged([CallerMemberName] string? propertyName = null)
        => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
}
```

### ErrorProvider Integration

```csharp
ErrorProvider errorProvider = new()
{
    DataSource = personBindingSource
};

// ErrorProvider automatically shows validation errors from IDataErrorInfo
```

**CRITICAL:** Never set `e.Cancel = true` in validation events - this breaks focus navigation and traps users!

```csharp
// ❌ WRONG - Blocks user from leaving control
private void TextBox_Validating(object sender, CancelEventArgs e)
{
    if (string.IsNullOrEmpty(textBox.Text))
        e.Cancel = true;  // User trapped!
}

// ✅ CORRECT - Show error but allow navigation
private void TextBox_Validating(object sender, CancelEventArgs e)
{
    if (string.IsNullOrEmpty(textBox.Text))
        errorProvider.SetError(textBox, "Required field");
    else
        errorProvider.SetError(textBox, string.Empty);
}
```

## DataGridView Patterns

### Basic Binding

```csharp
BindingList<Person> people = new BindingList<Person>();
dataGridView1.DataSource = people;
```

### Custom Columns

```csharp
dataGridView1.AutoGenerateColumns = false;

dataGridView1.Columns.Add(new DataGridViewTextBoxColumn
{
    DataPropertyName = "Name",
    HeaderText = "Full Name",
    Width = 200
});

dataGridView1.Columns.Add(new DataGridViewTextBoxColumn
{
    DataPropertyName = "Email",
    HeaderText = "Email Address",
    Width = 250
});

dataGridView1.DataSource = people;
```

### Virtual Mode (Large Datasets)

For 10,000+ rows, use virtual mode to load data on-demand:

```csharp
dataGridView1.VirtualMode = true;
dataGridView1.RowCount = _totalRecords;

dataGridView1.CellValueNeeded += (s, e) =>
{
    // Load data on demand
    e.Value = _dataCache[e.RowIndex].GetValue(e.ColumnIndex);
};

dataGridView1.CellValuePushed += (s, e) =>
{
    // Save edited data
    _dataCache[e.RowIndex].SetValue(e.ColumnIndex, e.Value);
};
```

## ComboBox/ListBox Binding

### Display and Value Members

```csharp
comboBox1.DataSource = people;
comboBox1.DisplayMember = "Name";  // What user sees
comboBox1.ValueMember = "Id";      // What you get from SelectedValue

// Get selected ID
int selectedId = (int)comboBox1.SelectedValue;
```

### Bind Selection to Property

```csharp
_cmbCountry.DataSource = countries;
_cmbCountry.DisplayMember = "Name";
_cmbCountry.ValueMember = "Code";

// Bind selected value to person's country code
_cmbCountry.DataBindings.Add(
    new Binding("SelectedValue", personBindingSource, "CountryCode", true));
```

## Best Practices

### DO

✅ Use `BindingSource` as intermediary between data and controls
✅ Implement `INotifyPropertyChanged` on all data objects
✅ Use `BindingList<T>` for WinForms collections
✅ Validate at form level, not field level
✅ Create `.datasource` files for Designer support
✅ Dispose BindingSource in form's Dispose method
✅ Use DataSourceUpdateMode appropriately for each scenario
✅ Test binding with null/empty data sources

### DON'T

❌ Set `e.Cancel = true` in validation events (traps user)
❌ Use `ObservableCollection<T>` directly without adapter
❌ Forget to call `WriteValue()` before reading bound data
❌ Use DataSets for new development (legacy technology)
❌ Create bindings without checking for null data sources
❌ Bind to properties without INotifyPropertyChanged
❌ Mix manual updates with data binding (pick one approach)

## Troubleshooting

### Binding Not Updating

**Symptom:** UI doesn't reflect data changes

**Solutions:**

1. Verify `INotifyPropertyChanged` is implemented
2. Ensure `PropertyChanged` event is raised in property setter
3. Check that binding's DataSourceUpdateMode is appropriate
4. Verify BindingSource.DataSource is set to actual instance

### Performance Issues

**Symptom:** Slow UI updates, especially with DataGridView

**Solutions:**

1. Use virtual mode for DataGridView with large datasets
2. Implement paging (load 100 rows at a time)
3. Use `SuspendBinding()` / `ResumeBinding()` during bulk updates
4. Consider caching frequently accessed data

**Example:**

```csharp
bindingSource.SuspendBinding();
try
{
    // Bulk updates
    for (int i = 0; i < 1000; i++)
        list.Add(new Person());
}
finally
{
    bindingSource.ResumeBinding();
}
```

### Memory Leaks

**Symptom:** Memory usage grows over time

**Solutions:**

1. Dispose BindingSource in form's Dispose method
2. Clear event handlers before setting DataSource to null
3. Set DataSource to null when done

**Example:**

```csharp
protected override void Dispose(bool disposing)
{
    if (disposing)
    {
        if (personBindingSource != null)
        {
            personBindingSource.DataSource = null;
            personBindingSource.Dispose();
        }
        components?.Dispose();
    }
    base.Dispose(disposing);
}
```

### Binding to Null

**Symptom:** Exceptions when binding to null objects

**Solution:** Check for null before binding:

```csharp
personBindingSource.DataSource = person ?? new Person();
```

## Related Skills

For specialized topics:

- **managing-winforms-mvvm** - MVVM pattern with ViewModels, Commands, and DataContext
- **building-winforms-applications** - Overall WinForms development patterns
- **managing-winforms-high-dpi-layout** - High-DPI fluent layout and control arrangement

## Summary

Effective data binding in WinForms requires:

- Proper INotifyPropertyChanged implementation
- BindingSource as intermediary
- Appropriate DataSourceUpdateMode selection
- Understanding of validation patterns
- Performance considerations for large datasets
- Proper disposal of binding components

Follow these patterns for maintainable, efficient data-bound applications.
