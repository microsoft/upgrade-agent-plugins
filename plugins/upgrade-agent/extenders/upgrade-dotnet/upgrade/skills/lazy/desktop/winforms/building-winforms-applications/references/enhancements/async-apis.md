# Modern Async APIs for WinForms (.NET 9+)

**Prerequisite:** Application must target .NET 9.0 or higher.

> 📖 **For general WinForms patterns**, see the [main detailed guide](../detailed-guide.md). For comprehensive async guidance, see [managing-winforms-async-apis skill](../../managing-winforms-async-apis/SKILL.md).

## Overview

.NET 9+ introduces modern async APIs for WinForms that replace legacy `Control.Invoke()` patterns with proper async/await support including cancellation tokens.

## Quick Migration Guide

### Replace Control.Invoke with InvokeAsync

**Before (.NET 8 and earlier):**
```csharp
private void UpdateUIFromWorkerThread()
{
    Control.Invoke(() => 
    {
        label.Text = "Updated";
        progressBar.Value = 50;
    });
}
```

**After (.NET 9+):**
```csharp
private async Task UpdateUIFromWorkerThreadAsync()
{
    await InvokeAsync(() => 
    {
        label.Text = "Updated";
        progressBar.Value = 50;
    });
}
```

### InvokeAsync Overloads

| Scenario | Signature | Use Case |
|----------|-----------|----------|
| Sync UI update | `InvokeAsync(Action)` | Simple property updates |
| Async UI work | `InvokeAsync(Func<CancellationToken, ValueTask>)` | Load data then update UI |
| Sync with result | `InvokeAsync<T>(Func<T>)` | Read control value from worker thread |
| Async with result | `InvokeAsync<T>(Func<CancellationToken, ValueTask<T>>)` | Async operation that returns value |

### Example: Load Data Asynchronously

```csharp
private async void LoadButton_Click(object? sender, EventArgs e)
{
    try
    {
        // Disable UI during load
        loadButton.Enabled = false;
        
        // Load data on background thread
        var data = await Task.Run(() => LoadDataFromDatabase());
        
        // Update UI on UI thread (automatically marshaled)
        dataGridView.DataSource = data;
    }
    catch (Exception ex)
    {
        MessageBox.Show($"Error: {ex.Message}", "Error",
            MessageBoxButtons.OK, MessageBoxIcon.Error);
    }
    finally
    {
        loadButton.Enabled = true;
    }
}
```

### Example: Async with Cancellation

```csharp
private CancellationTokenSource? _loadCts;

private async void LoadButton_Click(object? sender, EventArgs e)
{
    // Cancel previous load if still running
    _loadCts?.Cancel();
    _loadCts = new CancellationTokenSource();
    
    try
    {
        loadButton.Enabled = false;
        cancelButton.Enabled = true;
        
        // Pass cancellation token to async work
        var data = await LoadDataAsync(_loadCts.Token);
        
        // Update UI via InvokeAsync with cancellation support
        await InvokeAsync(async (ct) =>
        {
            dataGridView.DataSource = data;
            await UpdateStatusAsync(ct);
        }, _loadCts.Token);
    }
    catch (OperationCanceledException)
    {
        // Expected when cancelled - no error needed
        statusLabel.Text = "Load cancelled";
    }
    catch (Exception ex)
    {
        MessageBox.Show($"Error: {ex.Message}", "Error");
    }
    finally
    {
        loadButton.Enabled = true;
        cancelButton.Enabled = false;
    }
}

private void CancelButton_Click(object? sender, EventArgs e)
{
    _loadCts?.Cancel();
}
```

## Critical: Exception Handling in Async Event Handlers

**⚠️ MANDATORY:** Always wrap `await` in try/catch blocks in `async void` event handlers!

```csharp
// ❌ WRONG - Will crash app on exception
private async void Button_Click(object? sender, EventArgs e)
{
    await LoadDataAsync();  // Exception kills the app!
}

// ✅ CORRECT - Gracefully handles errors
private async void Button_Click(object? sender, EventArgs e)
{
    try
    {
        await LoadDataAsync();
    }
    catch (Exception ex)
    {
        MessageBox.Show($"Error: {ex.Message}", "Error",
            MessageBoxButtons.OK, MessageBoxIcon.Error);
    }
}
```

**Why:** Unhandled exceptions in `async void` methods terminate the application. Only `async void` event handlers need this - regular `async Task` methods propagate exceptions naturally.

## Common Patterns

### Fire-and-Forget Trap (AVOID)

```csharp
// ❌ WRONG - Fire-and-forget loses context
await InvokeAsync<string>(() => await LoadDataAsync());

// ✅ CORRECT - Properly awaited with cancellation
await InvokeAsync<string>(async (ct) => await LoadDataAsync(ct), cancellationToken);
```

### Background Work with Progress Updates

```csharp
private async void ProcessButton_Click(object? sender, EventArgs e)
{
    try
    {
        var progress = new Progress<int>(value => progressBar.Value = value);
        
        await Task.Run(async () =>
        {
            for (int i = 0; i <= 100; i += 10)
            {
                await Task.Delay(100);
                ((IProgress<int>)progress).Report(i);
            }
        });
        
        MessageBox.Show("Complete!");
    }
    catch (Exception ex)
    {
        MessageBox.Show($"Error: {ex.Message}");
    }
}
```

### Async Form Load

```csharp
public partial class MyForm : Form
{
    public MyForm()
    {
        InitializeComponent();
        
        // Start async load after form construction
        Load += async (s, e) => await LoadFormDataAsync();
    }
    
    private async Task LoadFormDataAsync()
    {
        try
        {
            var data = await FetchInitialDataAsync();
            dataGridView.DataSource = data;
        }
        catch (Exception ex)
        {
            MessageBox.Show($"Failed to load: {ex.Message}");
        }
    }
}
```

## Validation Checklist

After modernizing async patterns:

- [ ] All `Control.Invoke()` calls replaced with `await InvokeAsync()`
- [ ] All `Control.BeginInvoke()` calls replaced with `await InvokeAsync()`
- [ ] All `async void` event handlers wrapped in try/catch
- [ ] Cancellation tokens passed where long-running operations occur
- [ ] No `.Result` or `.Wait()` calls on UI thread (causes deadlocks)
- [ ] Progress reporting uses `IProgress<T>` instead of direct UI updates
- [ ] Application doesn't freeze during async operations
- [ ] Exceptions display user-friendly error messages

## Troubleshooting

**Problem:** Application hangs when calling async methods  
**Solution:** Check for `.Result` or `.Wait()` calls - use `await` instead

**Problem:** Exception crashes the application  
**Solution:** Ensure all `async void` event handlers have try/catch blocks

**Problem:** UI updates from wrong thread exception  
**Solution:** Use `await InvokeAsync()` to marshal UI updates to UI thread

**Problem:** Cancellation doesn't work  
**Solution:** Ensure `CancellationToken` is passed through the entire async call chain

## Additional Resources

- See [managing-winforms-async-apis](../../managing-winforms-async-apis/SKILL.md) for comprehensive async guidance
- See [main detailed guide](../detailed-guide.md) for full WinForms development patterns
