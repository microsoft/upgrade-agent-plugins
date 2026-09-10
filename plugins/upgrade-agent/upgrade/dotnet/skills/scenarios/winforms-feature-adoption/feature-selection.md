# Feature Selection Stage Instructions

Determine which WinForms features to adopt and identify good candidates for each feature.

## Step 1: Scan Codebase

For each WinForms project in scope:

### 1.1 Find Forms and UserControls
Search for `.Designer.cs` or `.Designer.vb` files - these indicate Forms/UserControls with Designer support.

Extract:
- Form/control name
- File paths (both `.cs`/`.vb` and `.Designer.cs`/`.Designer.vb`)
- Project path

### 1.2 Detect Current Patterns
For each form/control found, analyze:

**Color usage:**
- Uses `SystemColors.*` → good candidate for dark mode
- Uses hardcoded `Color.FromArgb()` → needs dark mode adaptation
- No color customization → dark mode ready

**Async patterns:**
- Contains `async void` event handlers → good candidate for modern async
- Uses `Control.Invoke()` / `Control.BeginInvoke()` → needs async migration
- Uses `Task.Run()` without proper UI marshaling → needs async fix
- No async usage → can skip async modernization

**Data binding:**
- Heavy use of manual property assignment (`label.Text = value;`) → good MVVM candidate
- Multiple controls bound to same data → good MVVM candidate
- Simple forms with no data → can skip MVVM
- Already uses data binding → may already follow MVVM or can enhance

### 1.3 Calculate Complexity Score
For each form/control, assign a complexity score (1-5):

| Score | Meaning | Recommendation |
|-------|---------|----------------|
| 1 | Simple (< 5 controls, no data) | Optional |
| 2 | Basic (5-15 controls, simple data) | Good starter candidate |
| 3 | Moderate (15-30 controls, moderate data) | Valuable modernization target |
| 4 | Complex (30-50 controls, rich data) | High-value but risky |
| 5 | Very complex (> 50 controls, complex data) | Consider breaking into UserControls first |

## Step 2: Feature-Specific Recommendations

### Dark Mode Recommendations
**Strong candidates:**
- Forms using `SystemColors` extensively → minimal work for dark mode
- Customer-facing UI with appearance expectations
- Settings/preferences dialogs (can add dark mode toggle)

**Weak candidates:**
- Internal tools with no appearance requirements
- Forms with heavy custom drawing (requires manual color adaptation)

### Async API Recommendations
**Strong candidates:**
- Forms with `Control.Invoke()` calls → direct async migration path
- Forms with `async void` event handlers → needs error handling
- Forms doing I/O or long-running work → improves responsiveness

**Weak candidates:**
- Static forms with no async operations
- Forms with only synchronous UI updates

### MVVM Recommendations
**Strong candidates:**
- Forms with lots of data manipulation logic in code-behind
- Forms that need unit testing (MVVM enables ViewModel testing)
- Complex business rules mixed with UI code
- Forms sharing data models across multiple instances

**Weak candidates:**
- Very simple forms (login, splash screens)
- Forms that are pure UI containers with no logic
- Designer-heavy forms with minimal code-behind

## Step 3: Create feature-selection.md

Document findings:

```markdown
# WinForms Feature Adoption - Feature Selection

## Target Projects
{list of WinForms projects with TFM versions}

## Discovered Forms and UserControls
{table with: Form/Control name, Project, Complexity, Current Patterns}

## Feature Recommendations

### Dark Mode
**Recommended candidates:**
- {form name} - uses SystemColors extensively, customer-facing
- {form name} - settings dialog, good place for mode toggle

**Skip:**
- {form name} - internal tool, no appearance requirements

### Async APIs
**Recommended candidates:**
- {form name} - uses Control.Invoke, straightforward migration
- {form name} - async void handlers, needs error handling

**Skip:**
- {form name} - no async operations

### MVVM
**Recommended candidates:**
- {form name} - complex data logic in code-behind
- {form name} - needs unit testing

**Skip:**
- {form name} - simple login form

## User-Confirmed Selections
{to be filled after user review}
- [ ] Dark Mode: {list of forms}
- [ ] Async APIs: {list of forms}
- [ ] MVVM: {list of forms}
```

## Step 4: Present to User

Show the recommendations and ask:
```
I've analyzed your WinForms codebase. Here's what I recommend:

**Dark Mode** (available for .NET 9+ projects):
- {X} forms are good candidates
- {Y} forms should skip (reasons)

**Modern Async APIs** (available for .NET 9+ projects):
- {X} forms would benefit
- {Y} forms have no async operations

**MVVM Pattern** (available for all .NET 8+ projects):
- {X} forms have complex logic that would benefit
- {Y} forms are too simple to justify refactoring

Would you like to:
1. Adopt all recommended features for all recommended forms
2. Pick specific features/forms
3. Start with one feature first
```

Capture user's choices and update `feature-selection.md` with confirmed selections.

## Step 5: Validate Selections

Before moving to planning:
- If user selected dark mode for .NET 8 project → warn and remove from selection
- If user selected async APIs for .NET 8 project → warn and remove from selection
- If user selected MVVM but no business logic exists → warn but allow (might be setting up for future)

Proceed to planning stage with confirmed feature selections.
