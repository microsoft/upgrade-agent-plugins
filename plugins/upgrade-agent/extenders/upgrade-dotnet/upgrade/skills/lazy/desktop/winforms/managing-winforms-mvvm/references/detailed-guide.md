## Contents
- Use the heading outline to navigate sections quickly.
## Overview

MVVM separates application concerns into three layers:

**Model:**

- Domain objects and business entities
- Data access and persistence
- Business rules and validation

**View:**

- WinForms Forms and UserControls
- Pure UI concerns (dialogs, cursors, visual feedback)
- No business logic

**ViewModel:**

- Presentation logic and state
- Commands for user actions
- Property change notifications
- Testable without UI
- No dependency on any UI stack. Keep ViewModels in a pure .NET class library (.NET Standard or .NET 8+).

**Key Benefits:**

- **Testability** - Unit test business logic without Forms
- **Portability** - Share ViewModels across WinForms, WPF, MAUI
- **Maintainability** - Clear separation of concerns
- **Designer Compatibility** - Forms remain editable in Designer

## .NET 8+ MVVM Features

WinForms added these APIs in .NET 8 to enable MVVM:

| API | Description | Cascading |
|-----|-------------|-----------|
| `Control.DataContext` | Ambient property for hierarchical binding | Yes |
| `ButtonBase.Command` | ICommand binding for buttons | No |
| `ToolStripItem.Command` | ICommand binding for menus/toolbars | No |
| `*.CommandParameter` | Parameter passed to command | No |

**Important Notes:**

- `BindableComponent` is new in .NET 8+
- `ToolStripItem` now derives from `BindableComponent` (.NET 8+)
- Commands automatically enable/disable controls based on CanExecute
- DataContext flows down the control hierarchy

**Minimum Requirements:** .NET 8 or later for full MVVM support

## Project Structure (CRITICAL)

**Use a separate class library for ViewModels** - source generators are not transitive across projects.

```
MySolution/
├── MyApp.WinForms/              # WinForms presentation layer
│   ├── Forms/
│   │   ├── MainForm.cs
│   │   └── MainForm.Designer.cs
│   ├── Controls/                # Custom UserControls
│   └── Properties/
│       └── DataSources/         # .datasource files for ViewModels
├── MyApp.ViewModels/            # ViewModels class library (CRITICAL)
│   ├── PersonViewModel.cs
│   └── MainViewModel.cs
├── MyApp.Models/                # Domain models
│   ├── Person.cs
│   └── Order.cs
└── MyApp.Services/              # Business logic
    ├── IDataService.cs
    └── DataService.cs
```

**ViewModels Project Configuration:**
```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
    <Nullable>enable</Nullable>
  </PropertyGroup>
  
  <ItemGroup>
    <PackageReference Include="CommunityToolkit.Mvvm" Version="[8.*,)" />
  </ItemGroup>
</Project>
```

**Why Separate Project?**

- MVVM Toolkit source generators don't cascade across projects
- Creating ViewModels in WinForms project breaks code generation
- Separation enables ViewModel reuse across UI frameworks
- Clean dependency boundaries

## Basic ViewModel Pattern

### Simple ViewModel with MVVM Community Toolkit

```csharp
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;

namespace MyApp.ViewModels;

public partial class PersonViewModel : ObservableObject
{
    // Observable properties - toolkit generates public properties
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(FullName))]
    private string _firstName = string.Empty;

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(FullName))]
    private string _lastName = string.Empty;

    [ObservableProperty]
    private int _age;

    // Computed property
    public string FullName => $"{FirstName} {LastName}";

    // Commands - toolkit generates SaveCommand property
    [RelayCommand]
    private async Task SaveAsync(CancellationToken ct)
    {
        await _dataService.SaveAsync(FirstName, LastName, Age, ct);
    }

    // Command with CanExecute
    [RelayCommand(CanExecute = nameof(CanDelete))]
    private async Task DeleteAsync(CancellationToken ct)
    {
        await _dataService.DeleteAsync(_id, ct);
    }
    
    private bool CanDelete() => Age >= 18;

    // Property change notification hook
    partial void OnAgeChanged(int value)
    {
        // Update command state when age changes
        DeleteCommand.NotifyCanExecuteChanged();
    }
    
    private readonly IDataService _dataService;
    private readonly int _id;
    
    public PersonViewModel(IDataService dataService, int id)
    {
        _dataService = dataService;
        _id = id;
    }
}
```

**What the Toolkit Generates:**

- Public `FirstName`, `LastName`, `Age` properties
- `PropertyChanged` event raising in setters
- `SaveCommand` and `DeleteCommand` properties
- Command CanExecute wiring

## DataSource File for Designer Support

Create `.datasource` file to enable Designer property discovery:

**File:** `MyApp.WinForms/Properties/DataSources/PersonViewModel.datasource`

```xml
<?xml version="1.0" encoding="utf-8"?>
<GenericObjectDataSource DisplayName="PersonViewModel" Version="1.0" 
    xmlns="urn:schemas-microsoft-com:xml-msdatasource">
  <TypeInfo>MyApp.ViewModels.PersonViewModel, MyApp.ViewModels, Version=1.0.0.0, Culture=neutral, PublicKeyToken=null</TypeInfo>
</GenericObjectDataSource>
```

**Benefits:**

- Designer shows ViewModel properties
- IntelliSense when creating bindings
- Visual binding configuration in Properties window

## Form Design Pattern

### Designer Code (InitializeComponent)

```csharp
private void InitializeComponent()
{
    personViewModelBindingSource = new BindingSource(components);
    _txtFirstName = new TextBox();
    _txtLastName = new TextBox();
    _btnSave = new Button();
    
    SuspendLayout();
    
    // Configure BindingSource with ViewModel type
    personViewModelBindingSource.DataSource = typeof(MyApp.ViewModels.PersonViewModel);
    
    // Bind properties
    _txtFirstName.DataBindings.Add(
        new Binding("Text", personViewModelBindingSource, "FirstName", 
            true, DataSourceUpdateMode.OnPropertyChanged));
    
    _txtLastName.DataBindings.Add(
        new Binding("Text", personViewModelBindingSource, "LastName", 
            true, DataSourceUpdateMode.OnPropertyChanged));
    
    // Bind command
    _btnSave.DataBindings.Add(
        new Binding("Command", personViewModelBindingSource, "SaveCommand", true));
    
    // Form configuration...
    Controls.Add(_txtFirstName);
    Controls.Add(_txtLastName);
    Controls.Add(_btnSave);
    
    ResumeLayout(false);
}

private BindingSource personViewModelBindingSource;
private TextBox _txtFirstName;
private TextBox _txtLastName;
private Button _btnSave;
```

### Code-Behind (Main File)

```csharp
namespace MyApp.WinForms.Forms;

public partial class PersonEditForm : Form
{
    private readonly PersonViewModel _viewModel;

    public PersonEditForm(PersonViewModel viewModel)
    {
        ArgumentNullException.ThrowIfNull(viewModel);
        
        _viewModel = viewModel;
        InitializeComponent();
        
        // Set actual ViewModel instance
        personViewModelBindingSource.DataSource = _viewModel;
    }
}
```

**Key Pattern:**

1. Designer binds to `typeof(ViewModel)` for property discovery
2. Code-behind sets actual instance at runtime
3. All business logic stays in ViewModel

## Command Binding

### Basic Command Binding

```csharp
// In InitializeComponent
_btnSave.DataBindings.Add(
    new Binding("Command", viewModelBindingSource, "SaveCommand", true));
```

**How it works:**

- Button automatically enables/disables based on `CanExecute`
- Click executes the command
- No Click event handler needed!

### Command with Parameter

```csharp
// Multiple buttons sharing same command with different parameters
_btnApprove.DataBindings.Add(
    new Binding("Command", viewModelBindingSource, "ProcessCommand", true));
_btnApprove.CommandParameter = "Approve";

_btnReject.DataBindings.Add(
    new Binding("Command", viewModelBindingSource, "ProcessCommand", true));
_btnReject.CommandParameter = "Reject";
```

**ViewModel:**

```csharp
[RelayCommand]
private async Task ProcessAsync(string action, CancellationToken ct)
{
    if (action == "Approve")
        await _service.ApproveAsync(_id, ct);
    else if (action == "Reject")
        await _service.RejectAsync(_id, ct);
}
```

### Menu and Toolbar Commands

```csharp
// Menu item
_tsmFileSave.DataBindings.Add(
    new Binding("Command", mainViewModelBindingSource, "SaveCommand", true));

// Toolbar button
_tsbSave.DataBindings.Add(
    new Binding("Command", mainViewModelBindingSource, "SaveCommand", true));

// With parameter
_tsmFileExport.DataBindings.Add(
    new Binding("Command", mainViewModelBindingSource, "ExportCommand", true));
_tsmFileExport.CommandParameter = "PDF";
```

**Note:** `ToolStripItem` derives from `BindableComponent` in .NET 8+, enabling Command binding.

## ObservableCollection Support

### ViewModel with Collection

```csharp
public partial class PeopleListViewModel : ObservableObject
{
    [ObservableProperty]
    private ObservableCollection<PersonViewModel> _people = new();

    [ObservableProperty]
    private PersonViewModel? _selectedPerson;

    [RelayCommand]
    private void AddPerson()
    {
        People.Add(new PersonViewModel(_dataService, 0));
    }

    [RelayCommand(CanExecute = nameof(CanRemovePerson))]
    private void RemovePerson()
    {
        if (SelectedPerson != null)
            People.Remove(SelectedPerson);
    }
    
    private bool CanRemovePerson() => SelectedPerson != null;

    // Update command state when selection changes
    partial void OnSelectedPersonChanged(PersonViewModel? value)
    {
        RemovePersonCommand.NotifyCanExecuteChanged();
    }
    
    private readonly IDataService _dataService;
    
    public PeopleListViewModel(IDataService dataService)
    {
        _dataService = dataService;
    }
}
```

### Form with ObservableCollection Adapter

**Problem:** ObservableCollection uses `INotifyCollectionChanged`, but WinForms requires `IBindingList`.

**Solution:** Use adapter (see managing-winforms-data-binding skill for implementation):

```csharp
public partial class PeopleListForm : Form
{
    private readonly PeopleListViewModel _viewModel;
    private ObservableBindingList<PersonViewModel>? _bindingAdapter;

    public PeopleListForm(PeopleListViewModel viewModel)
    {
        ArgumentNullException.ThrowIfNull(viewModel);
        
        _viewModel = viewModel;
        InitializeComponent();
        
        // Adapter bridges ObservableCollection to BindingList
        _bindingAdapter = new ObservableBindingList<PersonViewModel>(viewModel.People);
        dataGridView1.DataSource = _bindingAdapter;
        
        // Bind selection
        dataGridView1.DataBindings.Add(
            new Binding("SelectedItem", viewModelBindingSource, "SelectedPerson", true));
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            _bindingAdapter?.Dispose();
            components?.Dispose();
        }
        base.Dispose(disposing);
    }
}
```

**Don't forget to dispose the adapter!**

## DataContext Property (.NET 8+)

DataContext enables hierarchical binding - set once on parent, flows to children.

### Parent Form

```csharp
public partial class MainForm : Form
{
    private readonly MainViewModel _viewModel;

    public MainForm(MainViewModel viewModel)
    {
        _viewModel = viewModel;
        InitializeComponent();
    }

    protected override void OnLoad(EventArgs e)
    {
        base.OnLoad(e);
        
        // Set DataContext - flows to all child controls
        DataContext = _viewModel;
    }
}
```

### Child UserControl

```csharp
public partial class PersonDetailsControl : UserControl
{
    private BindingSource? _personBindingSource;

    public PersonDetailsControl()
    {
        InitializeComponent();
    }

    protected override void OnDataContextChanged(EventArgs e)
    {
        base.OnDataContextChanged(e);
        
        // React to inherited DataContext
        if (DataContext is PersonViewModel viewModel)
        {
            _personBindingSource ??= new BindingSource();
            _personBindingSource.DataSource = viewModel;
            
            // Bind controls to local BindingSource
            _txtName.DataBindings.Clear();
            _txtName.DataBindings.Add(
                new Binding("Text", _personBindingSource, "FullName", true));
        }
    }
}
```

**Benefits:**

- No need to pass ViewModels through constructors
- Nested controls automatically get context
- Easier composition of complex UIs

## Migration from Event Handlers

### Before: Traditional Event-Handler Pattern

**Problems:**

- Business logic mixed with UI code
- Cannot unit test without creating Forms
- Manual synchronization between controls
- Exception handling scattered throughout UI

```csharp
public partial class PersonForm : Form
{
    private Person _person;
    
    private void BtnSave_Click(object? sender, EventArgs e)
    {
        // Business logic in Form - BAD!
        try
        {
            _person.FirstName = _txtFirstName.Text;
            _person.LastName = _txtLastName.Text;
            
            using var connection = new SqlConnection(_connectionString);
            connection.Open();
            // Save logic here...
            
            MessageBox.Show("Saved successfully!");
            DialogResult = DialogResult.OK;
        }
        catch (Exception ex)
        {
            MessageBox.Show($"Error: {ex.Message}");
        }
    }
}
```

### After: MVVM Pattern

**ViewModel (Testable):**
```csharp
public partial class PersonViewModel : ObservableObject
{
    [ObservableProperty]
    private string _firstName = string.Empty;
    
    [ObservableProperty]
    private string _lastName = string.Empty;
    
    [ObservableProperty]
    private bool _isLoading;

    [ObservableProperty]
    private string? _errorMessage;

    [RelayCommand]
    private async Task SaveAsync(CancellationToken ct)
    {
        try
        {
            IsLoading = true;
            ErrorMessage = null;
            
            await _dataService.SavePersonAsync(FirstName, LastName, ct);
        }
        catch (Exception ex)
        {
            ErrorMessage = $"Error: {ex.Message}";
        }
        finally
        {
            IsLoading = false;
        }
    }
    
    private readonly IDataService _dataService;
    
    public PersonViewModel(IDataService dataService)
    {
        _dataService = dataService;
    }
}
```

**Form (Pure View):**
```csharp
public partial class PersonForm : Form
{
    private readonly PersonViewModel _viewModel;

    public PersonForm(PersonViewModel viewModel)
    {
        _viewModel = viewModel;
        InitializeComponent();
        
        personViewModelBindingSource.DataSource = _viewModel;
        
        // Subscribe to ViewModel changes for UI-specific concerns
        _viewModel.PropertyChanged += ViewModel_PropertyChanged;
    }

    protected override async void OnLoad(EventArgs e)
    {
        base.OnLoad(e);
        
        // Execute load command
        try
        {
            await _viewModel.LoadCommand.ExecuteAsync(null);
        }
        catch (Exception ex)
        {
            Application.OnThreadException(ex);
        }
    }

    // Handle UI-specific concerns only
    private void ViewModel_PropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(PersonViewModel.ErrorMessage) && 
            !string.IsNullOrEmpty(_viewModel.ErrorMessage))
        {
            MessageBox.Show(_viewModel.ErrorMessage, "Error", 
                MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
        else if (e.PropertyName == nameof(PersonViewModel.IsLoading))
        {
            Cursor = _viewModel.IsLoading ? Cursors.WaitCursor : Cursors.Default;
        }
    }
}
```

**Benefits:**
- Business logic testable without Form
- ViewModel reusable across frameworks
- Clear separation of concerns
- Easier to maintain and extend

## Unit Testing ViewModels

```csharp
using Xunit;
using Moq;

public class PersonViewModelTests
{
    [Fact]
    public void FullName_CombinesFirstAndLastName()
    {
        // Arrange
        var mockService = new Mock<IDataService>();
        var vm = new PersonViewModel(mockService.Object, 0)
        {
            FirstName = "John",
            LastName = "Doe"
        };
        
        // Act
        string fullName = vm.FullName;
        
        // Assert
        Assert.Equal("John Doe", fullName);
    }

    [Theory]
    [InlineData(17, false)]
    [InlineData(18, true)]
    [InlineData(25, true)]
    public void DeleteCommand_CanExecute_BasedOnAge(int age, bool expected)
    {
        // Arrange
        var mockService = new Mock<IDataService>();
        var vm = new PersonViewModel(mockService.Object, 0)
        {
            Age = age
        };
        
        // Act
        bool canExecute = vm.DeleteCommand.CanExecute(null);
        
        // Assert
        Assert.Equal(expected, canExecute);
    }
    
    [Fact]
    public async Task SaveCommand_CallsDataService()
    {
        // Arrange
        var mockService = new Mock<IDataService>();
        var vm = new PersonViewModel(mockService.Object, 123)
        {
            FirstName = "John",
            LastName = "Doe",
            Age = 30
        };
        
        // Act
        await vm.SaveCommand.ExecuteAsync(null);
        
        // Assert
        mockService.Verify(s => s.SavePersonAsync("John", "Doe", 30, 
            It.IsAny<CancellationToken>()), Times.Once);
    }
    
    [Fact]
    public async Task SaveCommand_SetsErrorMessage_OnException()
    {
        // Arrange
        var mockService = new Mock<IDataService>();
        mockService.Setup(s => s.SavePersonAsync(It.IsAny<string>(), 
                It.IsAny<string>(), It.IsAny<int>(), It.IsAny<CancellationToken>()))
            .ThrowsAsync(new Exception("Database error"));
        
        var vm = new PersonViewModel(mockService.Object, 123);
        
        // Act
        await vm.SaveCommand.ExecuteAsync(null);
        
        // Assert
        Assert.Contains("Database error", vm.ErrorMessage);
    }
}
```

**Testing Benefits:**
- Fast tests (no UI creation)
- Isolated logic
- Easy mocking of dependencies
- High code coverage possible

## Best Practices

### DO

✅ Use separate class library for ViewModels
✅ Use MVVM Community Toolkit for code generation
✅ Create `.datasource` files for Designer support
✅ Keep Forms as pure views (no business logic)
✅ Unit test ViewModels extensively
✅ Use `DataContext` for nested controls
✅ Handle UI concerns (dialogs, cursors, MessageBox) in code-behind
✅ Inject dependencies into ViewModels (IDataService, etc.)
✅ Use async/await for long-running operations
✅ Dispose ObservableBindingList adapters

### DON'T

❌ Put business logic in Forms
❌ Use lambdas in `InitializeComponent`
❌ Reference WinForms types from ViewModel project
❌ Bind `ObservableCollection<T>` directly without adapter
❌ Create ViewModels in WinForms project (breaks code generation)
❌ Test Forms directly (test ViewModels instead)
❌ Mix event handlers and Commands for same action
❌ Forget to call `NotifyCanExecuteChanged` when command state changes

## Troubleshooting

### Code Generation Not Working

**Symptom:** Properties and Commands not generated

**Solutions:**
1. Ensure ViewModels in separate class library
2. Check MVVM Toolkit package is installed
3. Verify class is `partial`
4. Rebuild project to trigger generators
5. Check for compilation errors

### Commands Not Updating UI

**Symptom:** Button stays enabled when it should be disabled

**Solution:** Call `NotifyCanExecuteChanged()`:
```csharp
partial void OnSelectedPersonChanged(PersonViewModel? value)
{
    DeleteCommand.NotifyCanExecuteChanged();
}
```

### ObservableCollection Binding Issues

**Symptom:** UI doesn't update when collection changes

**Solution:** Use `ObservableBindingList<T>` adapter (see managing-winforms-data-binding skill).

### Designer Can't Find ViewModel Properties

**Symptom:** Properties not showing in Designer

**Solutions:**
1. Create `.datasource` file
2. Rebuild ViewModels project
3. Restart Visual Studio/VS Code
4. Check TypeInfo in .datasource file is correct

## Related Skills

For related topics:
- **managing-winforms-data-binding** - Core data binding patterns and BindingSource
- **building-winforms-applications** - Overall WinForms development patterns
- **managing-winforms-high-dpi-layout** - High-DPI fluent layout and control arrangement

## Summary

MVVM in WinForms (.NET 8+) enables:

**Testability:**
- Business logic unit tested without Forms
- Fast, isolated tests
- High code coverage achievable

**Portability:**
- ViewModels shared across WinForms, WPF, MAUI
- UI framework independence
- Easier migration paths

**Maintainability:**
- Clear separation of concerns
- Business logic centralized in ViewModels
- Forms remain simple and Designer-compatible

**Key Enablers:**
- `DataContext` property for hierarchical binding
- `Command` properties on controls
- `BindingSource` component
- MVVM Community Toolkit
- ObservableBindingList adapter

Follow these patterns for modern, testable, maintainable WinForms applications.
