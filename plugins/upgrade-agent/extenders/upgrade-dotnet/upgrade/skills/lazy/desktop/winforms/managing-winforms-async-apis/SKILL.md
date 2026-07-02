---
name: managing-winforms-async-apis
description: >
  Adopts modern WinForms async APIs (.NET 9/10) including Control.InvokeAsync,
  Form.ShowAsync/ShowDialogAsync, and TaskDialog.ShowDialogAsync. Use when replacing
  Control.Invoke or Control.BeginInvoke with InvokeAsync, converting Form.ShowDialog to
  ShowDialogAsync, replacing synchronous MessageBox with TaskDialog.ShowDialogAsync, updating
  UI from background threads or async methods, implementing async event handlers, or migrating
  from ISynchronizeInvoke patterns. Also triggers for "Control.InvokeAsync", "ShowDialogAsync",
  "TaskDialog async", "async UI update", "replace Control.Invoke", "WinForms async",
  "async event handler", and "thread-safe UI access".
metadata:
  discovery: lazy
  traits: (.NET|CSharp|VisualBasic|DotNetCore) & WindowsForms
---

# WinForms Async APIs (.NET 9/10)

## When to use this skill

Use this skill when generating or reviewing WinForms code that:

- Marshals work to the UI thread from a worker thread or `Task.Run`.
- Updates controls, reads control state, or runs async UI-bound operations.
- Shows forms or dialogs asynchronously, especially in multi-form, MVVM, or DI scenarios.
- Triggers async work from a synchronous context (event handlers, `OnLoad`).
- Needs to defer work until after the message queue drains (post-show kickoff,
  reacting after a Windows message completes).
- Hits `InvokeAsync` overload-resolution errors/warnings (e.g. `WFO2001`).

Do **not** reach for these APIs to replace plain `await` of background work that
never touches the UI ─ that needs no marshalling.

## The APIs at a glance

| API | Status | Purpose |
| --- | --- | --- |
| `Control.InvokeAsync` | Stable (.NET 9) | Marshal sync/async callbacks to the UI thread, non-blocking. |
| `Form.ShowAsync` | Stable (.NET 10) | Show a modeless form asynchronously. |
| `Form.ShowDialogAsync` | Stable (.NET 10) | Show a modal dialog asynchronously. |
| `TaskDialog.ShowDialogAsync` | Stable (.NET 10) | Show a Task Dialog asynchronously. |

The form/dialog APIs were experimental in .NET 9 (required suppressing
`WFO5002`). As of .NET 10 they are stable ─ `WFO5002` is no longer raised, and no
opt-in is needed.

## Control.InvokeAsync

`InvokeAsync` *posts* the delegate to the WinForms message queue and returns
immediately ─ the calling thread is not blocked. Contrast with `Control.Invoke`,
which *sends* the delegate and blocks until the UI thread finishes it.

| Operation | Method | Blocking |
| --- | --- | --- |
| Send | `Control.Invoke` | Yes ─ waits for completion. |
| Post | `Control.InvokeAsync` | No ─ queues and returns. |

Posting keeps the message loop free to repaint, handle clicks, and process input,
so the UI stays responsive even under many UI-bound tasks.

### Overloads

```csharp
public async Task InvokeAsync(Action callback, CancellationToken cancellationToken = default)
public async Task<T> InvokeAsync<T>(Func<T> callback, CancellationToken cancellationToken = default)
public async Task InvokeAsync(Func<CancellationToken, ValueTask> callback, CancellationToken cancellationToken = default)
public async Task<T> InvokeAsync<T>(Func<CancellationToken, ValueTask<T>> callback, CancellationToken cancellationToken = default)
```

### Choosing the right overload

- Sync, no return value → `Action`.
- Sync, returns `T` → `Func<T>`.
- Async, no result → `Func<CancellationToken, ValueTask>`.
- Async, returns `T` → `Func<CancellationToken, ValueTask<T>>`.

The two async overloads receive a `CancellationToken` and return a `ValueTask`,
which `InvokeAsync` awaits internally.

### Examples

```csharp
// Sync, no return value.
await control.InvokeAsync(() => control.Text = "Updated Text");

// Sync, returns a value.
int itemCount = await control.InvokeAsync(() => comboBox.Items.Count);

// Async, no result.
await control.InvokeAsync(async (ct) =>
{
    await Task.Delay(1000, ct);
    control.Text = "Data Loaded";
});

// Async, returns a value.
int count = await control.InvokeAsync(async (ct) =>
{
    await Task.Delay(500, ct);

    return comboBox.Items.Count;
});
```

### Avoiding accidental fire-and-forget

Passing an async (`Task`-returning) method to a *synchronous* overload without a
`CancellationToken` produces a fire-and-forget call that cannot be awaited
internally. The WinForms analyzer flags this:

```text
warning WFO2001: Task is being passed to InvokeAsync without a cancellation token.
```

When generating code, ensure async callbacks return `ValueTask` (not `Task`),
accept a `CancellationToken`, and resolve to the async overload.

### Overload resolution with Task.Run

`InvokeAsync` returns a `Task` ─ that `Task` cannot be passed to `Task.Run`,
which needs an `Action` or a `Func<Task>`. Wrap the call in a local function:

```csharp
// Local function -> calls the loop on the UI thread.
Task InvokeTask() => this.InvokeAsync(ActualDisplayLoopAsync, CancellationToken.None);

await Task.Run(InvokeTask);

async ValueTask ActualDisplayLoopAsync(CancellationToken cancellation = default)
{
    // ...
}
```

## Deferred execution: posting work behind the message queue

`InvokeAsync` isn't only for cross-thread marshalling. Calling it from code that
is *already* on the UI thread is a legitimate pattern: the delegate is posted
**behind** all currently queued messages, so it runs only after the message loop
drains what's pending.

**Letting a Windows message finish before reacting to it.** Inside a `KeyDown`
handler, calling `SelectAll` directly can be defeated by the still-in-flight key
message. Posting it sidesteps that ─ and works whether or not `e.Handled` was set:

```csharp
private async void TextBox_KeyDown(object sender, KeyEventArgs e)
{
    if (e.KeyCode is Keys.Down)
    {
        _textBox.Text = "Some text to pick from";

        await InvokeAsync(() => _textBox.SelectAll());
    }
}
```

**Kicking off work once the form is fully shown.** As the last line of `OnLoad`,
a posted delegate runs after the framework's own show/activate/paint messages
drain ─ i.e. once the form is not just constructed but visible and active. It
keeps `OnLoad` synchronous (no `async void` on the override) and the kickoff
non-blocking, with its own `try`/`catch`:

```csharp
protected override void OnLoad(EventArgs e)
{
    base.OnLoad(e);

    // Synchronous infra setup runs here and completes before OnLoad returns.

    // Posted last: runs after the form is shown and the message queue drains.
    _ = InvokeAsync(StartUpWorkAsync, CancellationToken.None);
}
```

Note: this defers the kickoff past the *framework's* remaining init/paint
messages ─ not past your own `OnLoad` code, which has already run synchronously
by this point.

## Form and dialog async APIs

`Form.ShowAsync` and `Form.ShowDialogAsync` show forms asynchronously without
blocking the UI thread ─ handy when juggling multiple instances of the same
form type (e.g. one window per document). `ShowAsync` returns a plain `Task`
that completes when the form is closed or disposed; it returns immediately even
for a large, slow-to-initialize form.

As of .NET 10 the async task's state machine holds only a **weak reference** to
the form (not a strong one), so a long-lived task does not keep the form alive
and form lifetime stays decoupled from how long the caller retains the task.

```csharp
MyForm myForm = new();
await myForm.ShowAsync();
```

```csharp
DialogResult result = await myForm.ShowDialogAsync();

if (result is DialogResult.OK)
{
    // Act on the dialog result.
}
```

`TaskDialog.ShowDialogAsync` shows a Task Dialog asynchronously:

```csharp
TaskDialogPage taskDialogPage = new()
{
    Heading = "Processing...",
    Text = "Please wait while we complete the task."
};

TaskDialogButton buttonClicked = await TaskDialog.ShowDialogAsync(taskDialogPage);
```

Notes: implausible calls are expected to throw (e.g. calling `ShowAsync` twice on
the same instance). Forms are shown on the UI thread.

## Starting async work from synchronous code

Avoid `async void` ─ the caller cannot await or observe completion, and
exceptions escape normal `Task` error handling.

**Exception:** event handlers (and methods with event-handler signatures) cannot
return `Task`, so `async void` is unavoidable there. Wrap the awaited body in
`try`/`catch` so exceptions are still handled:

```csharp
private async void Button_Click(object sender, EventArgs e)
{
    try
    {
        await PerformLongRunningOperationAsync();
    }
    catch (Exception ex)
    {
        MessageBox.Show(
            $"An error occurred: {ex.Message}",
            "Error",
            MessageBoxButtons.OK,
            MessageBoxIcon.Error);
    }
}
```

Kicking an async loop off from `OnLoad` is the standard pattern. `OnLoad`
completes at the first `await`; the message loop stays free, and the runtime
resumes the method after each awaited task ─ so an infinite async loop does not
freeze the UI:

```csharp
protected override async void OnLoad(EventArgs e)
{
    base.OnLoad(e);
    await RunDisplayLoopAsync();
}
```

This is cooperative, not parallel ─ like a relay race passing a baton ─ until the
loop is explicitly moved onto another thread via `Task.Run`. At that point any UI
access inside it must go through `InvokeAsync`, or a cross-thread exception is
thrown.

## Parallelizing UI-bound work

To run two UI-bound operations concurrently inside a loop, start both, await
`Task.WhenAny` so the faster one isn't blocked by the slower, then reset the
completed task to `null` so the next iteration restarts it. Use a
`CancellationTokenSource` cancelled in `OnFormClosing` to break the loop cleanly:

```csharp
private async Task RunDisplayLoopAsync()
{
    Task? uiUpdateTask = null;
    Task? separatorFadingTask = null;

    while (true)
    {
        async Task FadeInFadeOutAsync(CancellationToken cancellation)
        {
            await _sevenSegmentTimer.FadeSeparatorsInAsync(cancellation).ConfigureAwait(false);
            await _sevenSegmentTimer.FadeSeparatorsOutAsync(cancellation).ConfigureAwait(false);
        }

        uiUpdateTask ??= _sevenSegmentTimer.UpdateTimeAndDelayAsync(
            time: TimeOnly.FromDateTime(DateTime.Now),
            cancellation: _formCloseCancellation.Token);

        separatorFadingTask ??= FadeInFadeOutAsync(_formCloseCancellation.Token);

        Task completed = await Task.WhenAny(separatorFadingTask, uiUpdateTask);

        if (completed.IsCanceled)
        {
            break;
        }

        if (completed == uiUpdateTask)
        {
            uiUpdateTask = null;
        }
        else
        {
            separatorFadingTask = null;
        }
    }
}

protected override void OnFormClosing(FormClosingEventArgs e)
{
    base.OnFormClosing(e);
    _formCloseCancellation.Cancel();
}
```

Use `ConfigureAwait(false)` for operations that are safe from any thread (e.g.
setting a label color); skip it where the continuation must stay on the UI thread.

## Quick checklist

- Marshalling to the UI thread, non-blocking → `InvokeAsync`, not `Invoke`.
- Match the overload to sync/async and return-value needs.
- Async callbacks: return `ValueTask`, take a `CancellationToken` ─ avoid `WFO2001`.
- Don't pass an `InvokeAsync` `Task` into `Task.Run`; wrap it in a local function.
- `async void` only for event handlers, always with `try`/`catch`.
- To run work after the message queue drains, post it with `InvokeAsync` from the
  UI thread (e.g. last line of `OnLoad`) ─ keeps `OnLoad` sync and non-blocking.
- Form/dialog async APIs are stable in .NET 10 (no `WFO5002` suppression needed).

## Related Skills

- [WinForms Development](../building-winforms-applications/SKILL.md)
- [WinForms Designer Code](../managing-winforms-designer-code/SKILL.md)
- [WinForms Data Binding](../managing-winforms-data-binding/SKILL.md)
- [WinForms MVVM](../managing-winforms-mvvm/SKILL.md)
- [WinForms High-DPI Fluent Layout](../managing-winforms-high-dpi-layout/SKILL.md)

Sample code: <https://github.com/microsoft/winforms-designer-extensibility/tree/main/Samples/NET%209/Async%20in%20NET%209>
