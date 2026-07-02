# Planning Stage Instructions

Create the execution plan for WinForms feature adoption based on confirmed feature selections.

## Step 1: Read Confirmed Selections

Load `feature-selection.md` and extract:
- Which features were selected (dark mode, async, MVVM)
- Which forms/controls for each feature
- Target projects and their TFMs

## Step 2: Determine Task Order

**Standard order** (respects dependencies):
1. **Dark Mode** tasks (application-level, then per-form adjustments)
2. **Async APIs** tasks (per-form async modernization)
3. **MVVM** tasks (per-form ViewModel creation and wiring)

**Rationale:**
- Dark mode is application-level setup + per-form color fixes → quick wins
- Async APIs are isolated to individual forms → medium scope
- MVVM is architectural → largest scope, benefits from clean async code

**Allow user to override** if they prefer a different order (e.g., "start with MVVM for one form").

## Step 3: Task Breakdown

### 3.1 Dark Mode Tasks

**If dark mode selected:**

**Task 1: Enable Dark Mode Application-Wide**
- **Scope**: Main Program.cs entry point
- **Work**:
  - Add `Application.SetColorMode(SystemColorMode.System);` in Program.cs
  - Verify it's called before `Application.Run()`
- **Validation**: Application starts and respects OS theme setting
- **Commit**: After this task

**Task 2-N: Adapt Forms for Dark Mode**
- One task per form (or group simple forms)
- **Scope**: {FormName}.cs and {FormName}.Designer.cs
- **Work**:
  - Review color usage: replace hardcoded colors with SystemColors or dual-mode colors
  - Test appearance in light and dark modes
  - Update custom drawing code to query `Application.IsDarkModeEnabled`
- **Validation**: Form displays correctly in both light and dark mode
- **Commit**: After each form (or batch if low-risk)

### 3.2 Async API Tasks

**If async APIs selected:**

**Task N: Modernize {FormName} Async Patterns**
- One task per form
- **Scope**: {FormName}.cs
- **Work**:
  - Replace `Control.Invoke()` with `await Control.InvokeAsync()`
  - Wrap `async void` event handlers in try/catch blocks
  - Pass cancellation tokens where applicable
  - Remove blocking `.Result` or `.Wait()` calls on UI thread
- **Validation**: Form operates correctly, no blocking calls, errors handled gracefully
- **Commit**: After each form

### 3.3 MVVM Tasks

**If MVVM selected:**

**Task N: Set Up MVVM Infrastructure** (if first MVVM adoption)
- **Scope**: Project-level
- **Work**:
  - Add `CommunityToolkit.Mvvm` NuGet package (or plain INotifyPropertyChanged)
  - Create ViewModels folder structure
  - Add base ViewModel class if not using toolkit
- **Validation**: Project builds, infrastructure in place
- **Commit**: After this task

**Task N: Refactor {FormName} to MVVM**
- One task per form
- **Scope**: {FormName}.cs + new {FormName}ViewModel.cs
- **Work**:
  - Extract business logic to ViewModel
  - Implement INotifyPropertyChanged (or inherit ObservableObject)
  - Convert button clicks to Commands
  - Set Form.DataContext to ViewModel in constructor
  - Update control bindings
  - Move complex logic out of code-behind
- **Validation**: Form works identically, logic is testable, Designer still opens form
- **Commit**: After each form

## Step 4: Risk Assessment

For each task, identify risks:

**Dark Mode Risks:**
- Custom drawing may look wrong in dark mode → manual testing required
- Third-party controls may not support dark mode → document limitations

**Async API Risks:**
- Existing code may have subtle race conditions masked by synchronous Invoke → careful testing
- Exception handling changes behavior → ensure equivalent error UX

**MVVM Risks:**
- Designer compatibility: ensure no MVVM logic leaks into InitializeComponent
- DataContext binding errors silent at compile time → runtime testing critical
- Over-refactoring: don't move Designer-managed properties to ViewModel

## Step 5: Define Commit Strategy

**Recommended strategy**: After each task (matches other scenarios)

**Alternative**: After each feature (all dark mode tasks → commit, all async → commit, all MVVM → commit)

**Reasoning**: Smaller commits are easier to review and revert if something breaks

## Step 6: Create plan.md

Document the execution plan:

```markdown
# WinForms Feature Adoption Plan

## Features to Adopt
- {list features and target forms}

## Task Breakdown

### Phase 1: Dark Mode Adoption
1. **Enable Dark Mode Application-Wide**
   - Scope: Program.cs
   - Risk: Low
   - Estimated effort: 5 minutes

2. **Adapt MainForm for Dark Mode**
   - Scope: MainForm.cs, MainForm.Designer.cs
   - Risk: Medium (custom drawing)
   - Estimated effort: 30 minutes

{continue for each form...}

### Phase 2: Async API Modernization
1. **Modernize DataLoadForm Async Patterns**
   - Scope: DataLoadForm.cs
   - Risk: Low (straightforward migration)
   - Estimated effort: 15 minutes

{continue for each form...}

### Phase 3: MVVM Adoption
1. **Set Up MVVM Infrastructure**
   - Scope: Project-level
   - Risk: Low
   - Estimated effort: 10 minutes

2. **Refactor SettingsForm to MVVM**
   - Scope: SettingsForm.cs + SettingsViewModel.cs
   - Risk: Medium (complex data binding)
   - Estimated effort: 45 minutes

{continue for each form...}

## Total Estimated Effort
{calculate total}

## Success Criteria
- [ ] All features applied to target forms
- [ ] Application builds without errors
- [ ] Designer opens all modified forms
- [ ] Visual verification in both light/dark modes (if dark mode applied)
- [ ] All tests pass
```

## Step 7: Create scenario-instructions.md

Persist execution constraints:

```markdown
# WinForms Feature Adoption - Execution Instructions

## Selected Features
- Dark Mode: {enabled/disabled} - {list of forms}
- Async APIs: {enabled/disabled} - {list of forms}
- MVVM: {enabled/disabled} - {list of forms}

## Task Execution Order
1. Dark Mode tasks
2. Async API tasks
3. MVVM tasks

## Commit Strategy
{after-each-task | after-each-feature}

## Required Skills
- building-winforms-applications (for dark mode setup)
- managing-winforms-async-apis (for async modernization)
- managing-winforms-mvvm (for MVVM refactoring)
- managing-winforms-designer-code (for Designer compatibility validation)

## Critical Constraints
- NEVER modify InitializeComponent with modern C# features
- ALWAYS validate Designer can open forms after changes
- ALWAYS test dark mode appearance visually
- ALWAYS wrap async void event handlers in try/catch
```

## Step 8: Present Plan to User

Show the plan summary:
```
I've created a plan to adopt {features} across {N} forms.

**Timeline:**
- Dark Mode: {X} tasks, ~{Y} minutes
- Async APIs: {X} tasks, ~{Y} minutes
- MVVM: {X} tasks, ~{Y} minutes

**Total estimated effort**: ~{Z} minutes

The work will be committed {strategy description}.

Ready to proceed?
```

If user approves, proceed to execution stage.
