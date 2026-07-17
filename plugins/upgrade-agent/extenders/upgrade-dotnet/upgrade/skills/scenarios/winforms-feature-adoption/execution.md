# Execution Stage Instructions

Apply WinForms feature adoption to the codebase using lazy-loaded skills.

## Overview

Each task loads the appropriate lazy skill and follows its guidance. This file provides scenario-specific execution rules and integration points.

## Task Execution Pattern

For each task in plan.md:

1. **Read task.md** - understand scope and requirements
2. **Load appropriate skill(s)** - based on feature being adopted
3. **Apply changes** - following skill guidance
4. **Validate** - build + Designer compatibility + feature-specific checks
5. **Commit** - per commit strategy in scenario-instructions.md

## Feature-Specific Execution

### Dark Mode Execution

**Task type:** Enable Dark Mode Application-Wide

**Skills/guides to load:**
- `building-winforms-applications/ref/dark-mode.md` - focused dark mode guide

**Changes to make:**
1. Open Program.cs (or Program.vb)
2. Locate the `Main()` method or `ApplicationConfiguration.Initialize()` call
3. Add `Application.SetColorMode(SystemColorMode.System);` immediately after
4. Verify order: `SetColorMode` → `SetHighDpiMode` → `Application.Run`

**C# example:**
```csharp
[STAThread]
static void Main()
{
    ApplicationConfiguration.Initialize();
    Application.SetColorMode(SystemColorMode.System);  // Add this
    Application.SetHighDpiMode(HighDpiMode.SystemAware);
    Application.Run(new MainForm());
}
```

**VB example:**
```vb
' In ApplicationEvents.vb
Private Sub MyApplication_ApplyApplicationDefaults(sender As Object, e As ApplyApplicationDefaultsEventArgs) Handles Me.ApplyApplicationDefaults
    e.ColorMode = SystemColorMode.System  ' Add this
    e.HighDpiMode = HighDpiMode.SystemAware
End Sub
```

**Validation:**
- [ ] Code compiles
- [ ] Application starts
- [ ] Changing OS theme changes app appearance (manual test)

---

**Task type:** Adapt Form for Dark Mode

**Skills/guides to load:**
- `building-winforms-applications/ref/dark-mode.md` - focused dark mode guide
- `managing-winforms-rendering` - if form has custom drawing

**Changes to make:**
1. Open {FormName}.cs
2. Find color assignments:
   - **If using SystemColors** → no change needed (auto-adapts)
   - **If using hardcoded colors** → convert to dual-mode:
     ```csharp
     Color backColor = Application.IsDarkModeEnabled
         ? Color.FromArgb(0xFF, 0x2D, 0x2D, 0x30)  // Dark mode
         : Color.FromArgb(0xFF, 0xF0, 0xF0, 0xF0); // Light mode
     ```
3. If form has custom drawing (OnPaint overrides):
   - Update colors to check `Application.IsDarkModeEnabled`
   - Use SystemColors where possible
4. **DO NOT modify InitializeComponent** - color logic goes in regular code

**Validation:**
- [ ] Code compiles
- [ ] Designer opens form successfully
- [ ] Form looks correct in light mode (manual test)
- [ ] Form looks correct in dark mode (manual test)
- [ ] Switching OS theme updates colors at runtime

---

### Async API Execution

**Task type:** Modernize Form Async Patterns

**Skills/guides to load:**
- `building-winforms-applications/ref/async-apis.md` - focused async guide
- `managing-winforms-async-apis` - comprehensive async patterns (if needed)

**Changes to make:**
1. Open {FormName}.cs
2. Find `Control.Invoke()` calls:
   ```csharp
   // Before
   Control.Invoke(() => label.Text = "Updated");
   
   // After
   await InvokeAsync(() => label.Text = "Updated");
   ```
3. Find `async void` event handlers:
   ```csharp
   // Before
   private async void LoadButton_Click(object sender, EventArgs e)
   {
       var data = await LoadDataAsync();
       dataGrid.DataSource = data;
   }
   
   // After
   private async void LoadButton_Click(object sender, EventArgs e)
   {
       try
       {
           var data = await LoadDataAsync();
           dataGrid.DataSource = data;
       }
       catch (Exception ex)
       {
           MessageBox.Show($"Error: {ex.Message}", "Error",
               MessageBoxButtons.OK, MessageBoxIcon.Error);
       }
   }
   ```
4. Add cancellation token support where applicable:
   ```csharp
   private CancellationTokenSource? _cts;
   
   private async void LoadButton_Click(object sender, EventArgs e)
   {
       _cts?.Cancel();
       _cts = new CancellationTokenSource();
       
       try
       {
           var data = await LoadDataAsync(_cts.Token);
           dataGrid.DataSource = data;
       }
       catch (OperationCanceledException)
       {
           // Expected when cancelled
       }
       catch (Exception ex)
       {
           MessageBox.Show($"Error: {ex.Message}");
       }
   }
   ```

**Validation:**
- [ ] Code compiles
- [ ] No blocking calls on UI thread (no `.Result`, `.Wait()`)
- [ ] All async event handlers have try/catch
- [ ] Form remains responsive during async operations
- [ ] Cancellation works (if implemented)

---

### MVVM Execution

**Task type:** Set Up MVVM Infrastructure

**Skills to load:**
- `managing-winforms-mvvm` - for MVVM setup guidance

**Changes to make:**
1. Add NuGet package:
   ```powershell
   dotnet add package CommunityToolkit.Mvvm
   ```
2. Create folder structure:
   ```
   MyProject/
   ├── ViewModels/
   │   └── (ViewModels will go here)
   ├── Views/
   │   └── (existing forms)
   ```
3. If not using CommunityToolkit, create base ViewModel:
   ```csharp
   public abstract class ViewModelBase : INotifyPropertyChanged
   {
       public event PropertyChangedEventHandler? PropertyChanged;
       
       protected void OnPropertyChanged([CallerMemberName] string? propertyName = null)
       {
           PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
       }
   }
   ```

**Validation:**
- [ ] NuGet package installed
- [ ] Folder structure created
- [ ] Project compiles

---

**Task type:** Refactor Form to MVVM

**Skills to load:**
- `managing-winforms-mvvm` - for MVVM refactoring patterns
- `managing-winforms-data-binding` - for data binding setup
- `managing-winforms-designer-code` - to ensure Designer compatibility

**Changes to make:**

1. **Create ViewModel**:
   ```csharp
   // ViewModels/SettingsViewModel.cs
   public partial class SettingsViewModel : ObservableObject
   {
       [ObservableProperty]
       private string _username = string.Empty;
       
       [ObservableProperty]
       private bool _enableNotifications;
       
       [RelayCommand]
       private async Task SaveAsync()
       {
           // Business logic here (moved from code-behind)
           await SaveSettingsToDbAsync();
       }
   }
   ```

2. **Update Form Constructor**:
   ```csharp
   // SettingsForm.cs
   public partial class SettingsForm : Form
   {
       private readonly SettingsViewModel _viewModel;
       
       public SettingsForm()
       {
           InitializeComponent();
           
           _viewModel = new SettingsViewModel();
           
           // Bind controls to ViewModel
           txtUsername.DataBindings.Add(nameof(txtUsername.Text),
               _viewModel, nameof(_viewModel.Username),
               formattingEnabled: false,
               DataSourceUpdateMode.OnPropertyChanged);
           
           chkNotifications.DataBindings.Add(nameof(chkNotifications.Checked),
               _viewModel, nameof(_viewModel.EnableNotifications),
               formattingEnabled: false,
               DataSourceUpdateMode.OnPropertyChanged);
           
           btnSave.Click += async (s, e) => await _viewModel.SaveCommand.ExecuteAsync(null);
       }
   }
   ```

3. **Move business logic** from code-behind to ViewModel
4. **DO NOT touch InitializeComponent** - bindings go in constructor after it

**Validation:**
- [ ] Code compiles
- [ ] Designer opens form successfully
- [ ] Form displays data from ViewModel
- [ ] Changes in form controls update ViewModel properties
- [ ] Commands execute when buttons clicked
- [ ] Business logic is now testable (can instantiate ViewModel in tests)

---

## Common Validation Steps

After every task:

1. **Build validation**:
   ```
   dotnet build <project>.csproj
   ```
   Must succeed with 0 errors

2. **Designer validation**:
   - Open each modified form in Visual Studio Designer
   - Verify form loads without errors
   - Verify controls are visible and correctly positioned
   - Close Designer (it will regenerate Designer code if needed)

3. **Runtime validation**:
   - Run the application
   - Navigate to modified form
   - Test the feature:
     - **Dark mode**: switch OS theme, verify appearance
     - **Async**: trigger async operations, verify no blocking
     - **MVVM**: interact with UI, verify ViewModel updates

4. **Test validation** (if tests exist):
   ```
   dotnet test <test-project>.csproj
   ```
   Must pass with 0 failures

## Error Recovery

**Designer won't open form**:
- Check for modern C# in InitializeComponent (lambdas, null coalescing, etc.)
- Revert Designer.cs file
- Apply changes in regular .cs file only

**Build errors after MVVM**:
- Check NuGet package installed: `CommunityToolkit.Mvvm`
- Verify binding paths match ViewModel property names (case-sensitive)
- Check for circular references (ViewModel → Form → ViewModel)

**Dark mode colors wrong**:
- Verify `Application.SetColorMode()` called before `Application.Run()`
- Check SystemColors used (not hardcoded colors)
- For custom colors, verify `Application.IsDarkModeEnabled` checked

**Async hangs or deadlocks**:
- Check for `.Result` or `.Wait()` on UI thread
- Verify using `await InvokeAsync()`, not `Invoke()`
- Check ConfigureAwait usage (shouldn't be needed in WinForms)

## Commit After Task

After successful validation:
```
git add .
git commit -m "feat(winforms): {task description}"
```

Proceed to next task in plan.md.
