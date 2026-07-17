## Contents
- Use the heading outline to navigate sections quickly.
## Core Layout Principles

### Scaling and DPI Awareness

**DPI Settings:**

- Use 96 DPI / 100% scaling as the design baseline for new Forms/UserControls
- Set `AutoScaleMode` appropriately
- For existing forms: Leave `AutoScaleMode` as-is, account for scaling
- .NET 9+: Query DarkMode status via `Application.IsDarkModeEnabled`

**Important:** Only `SystemColors` change automatically in DarkMode. Absolute colors require manual handling.

### Layout Strategy Overview

**Divide and Conquer:**

- Use multiple or nested TableLayoutPanels for logical sections
- Don't cram everything into one mega-grid
- Main form uses SplitContainer or outer TableLayoutPanel with percentage/AutoSize rows/cols
- Each UI section gets its own nested TableLayoutPanel or UserControl

**Keep It Simple:**

- Individual TableLayoutPanels: 2-4 columns maximum
- Use GroupBoxes with nested TableLayoutPanels for visual grouping
- RadioButton clusters: single-column, auto-size-cells TableLayoutPanel inside AutoSize GroupBox
- Large content scrolling: Nested panel controls with `AutoScroll` enabled

## TableLayoutPanel Fundamentals

### Cell Sizing Priority

**For Rows:**

```text
AutoSize > Percent > Absolute
```

**For Columns:**

```text
AutoSize > Percent > Absolute
```

### Column Sizing Rules

| Size Mode | Use Case | Anchor | Notes |
|-----------|----------|--------|-------|
| **AutoSize** | Caption columns | `Left and Right` | For labels and prompts |
| **Percent** | Content columns | `Top, Bottom, Left, and Right` | Distribute by reasoning |
| **Absolute** | Fixed content only | Varies | Icons, buttons (avoid when possible) |

**CRITICAL:** Never dock controls in TableLayoutPanel cells ─ always use Anchor!

### Row Sizing Rules

| Size Mode | Use Case | Notes |
|-----------|----------|-------|
| **AutoSize** | Single-line content | Entry fields, captions, checkboxes |
| **Percent** | Multi-line content | TextBoxes, rendering areas, fill space |
| **Absolute** | Avoid | Only for truly fixed-size content |

### Margin and Padding

**Margins:**

- Set `Margin` on controls (minimum 3px default)
- Margins create spacing between controls

**Padding:**

- `Padding` does NOT affect TableLayoutPanel cells
- Use for container controls only

## Example: Basic Form Layout (Designer-Compatible)

All controls are declared as backing fields and configured inside `InitializeComponent`:

```csharp
// In MainForm.Designer.cs
private void InitializeComponent()
{
    _tableLayoutPanel = new TableLayoutPanel();
    _lblName = new Label();
    _txtName = new TextBox();
    _lblEmail = new Label();
    _txtEmail = new TextBox();
    _buttonPanel = new FlowLayoutPanel();
    _btnOK = new Button();
    _btnCancel = new Button();

    SuspendLayout();
    _tableLayoutPanel.SuspendLayout();

    // _tableLayoutPanel
    _tableLayoutPanel.ColumnCount = 2;
    _tableLayoutPanel.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
    _tableLayoutPanel.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));
    _tableLayoutPanel.Controls.Add(_lblName, 0, 0);
    _tableLayoutPanel.Controls.Add(_txtName, 1, 0);
    _tableLayoutPanel.Controls.Add(_lblEmail, 0, 1);
    _tableLayoutPanel.Controls.Add(_txtEmail, 1, 1);
    _tableLayoutPanel.Controls.Add(_buttonPanel, 1, 2);
    _tableLayoutPanel.Dock = DockStyle.Fill;
    _tableLayoutPanel.Location = new Point(0, 0);
    _tableLayoutPanel.Name = "_tableLayoutPanel";
    _tableLayoutPanel.RowCount = 3;
    _tableLayoutPanel.RowStyles.Add(new RowStyle(SizeType.AutoSize));
    _tableLayoutPanel.RowStyles.Add(new RowStyle(SizeType.AutoSize));
    _tableLayoutPanel.RowStyles.Add(new RowStyle(SizeType.Percent, 100F));
    _tableLayoutPanel.Size = new Size(400, 200);
    _tableLayoutPanel.TabIndex = 0;

    // _lblName
    _lblName.Anchor = AnchorStyles.Left | AnchorStyles.Right;
    _lblName.AutoSize = true;
    _lblName.Location = new Point(3, 3);
    _lblName.Margin = new Padding(3);
    _lblName.Name = "_lblName";
    _lblName.Size = new Size(42, 15);
    _lblName.TabIndex = 0;
    _lblName.Text = "Name:";

    // _txtName
    _txtName.Anchor = AnchorStyles.Top | AnchorStyles.Bottom | AnchorStyles.Left | AnchorStyles.Right;
    _txtName.Location = new Point(51, 3);
    _txtName.Margin = new Padding(3);
    _txtName.Name = "_txtName";
    _txtName.Size = new Size(346, 23);
    _txtName.TabIndex = 1;

    // _lblEmail
    _lblEmail.Anchor = AnchorStyles.Left | AnchorStyles.Right;
    _lblEmail.AutoSize = true;
    _lblEmail.Location = new Point(3, 32);
    _lblEmail.Margin = new Padding(3);
    _lblEmail.Name = "_lblEmail";
    _lblEmail.Size = new Size(39, 15);
    _lblEmail.TabIndex = 2;
    _lblEmail.Text = "Email:";

    // _txtEmail
    _txtEmail.Anchor = AnchorStyles.Top | AnchorStyles.Bottom | AnchorStyles.Left | AnchorStyles.Right;
    _txtEmail.Location = new Point(51, 32);
    _txtEmail.Margin = new Padding(3);
    _txtEmail.Name = "_txtEmail";
    _txtEmail.Size = new Size(346, 23);
    _txtEmail.TabIndex = 3;

    // _buttonPanel
    _buttonPanel.Anchor = AnchorStyles.Bottom | AnchorStyles.Right;
    _buttonPanel.AutoSize = true;
    _buttonPanel.FlowDirection = FlowDirection.LeftToRight;
    _buttonPanel.Location = new Point(238, 61);
    _buttonPanel.Name = "_buttonPanel";
    _buttonPanel.Size = new Size(159, 29);
    _buttonPanel.TabIndex = 4;

    // _btnOK
    _btnOK.Location = new Point(3, 3);
    _btnOK.Name = "_btnOK";
    _btnOK.Size = new Size(75, 23);
    _btnOK.TabIndex = 0;
    _btnOK.Text = "OK";
    _btnOK.UseVisualStyleBackColor = true;

    // _btnCancel
    _btnCancel.Location = new Point(84, 3);
    _btnCancel.Name = "_btnCancel";
    _btnCancel.Size = new Size(75, 23);
    _btnCancel.TabIndex = 1;
    _btnCancel.Text = "Cancel";
    _btnCancel.UseVisualStyleBackColor = true;

    // _buttonPanel - add buttons
    _buttonPanel.Controls.Add(_btnOK);
    _buttonPanel.Controls.Add(_btnCancel);

    // MainForm
    AcceptButton = _btnOK;
    AutoScaleDimensions = new SizeF(7F, 15F);
    AutoScaleMode = AutoScaleMode.Font;
    CancelButton = _btnCancel;
    ClientSize = new Size(400, 200);
    Controls.Add(_tableLayoutPanel);
    Name = "MainForm";
    Text = "Contact Form";

    _tableLayoutPanel.ResumeLayout(false);
    _tableLayoutPanel.PerformLayout();
    ResumeLayout(false);
}

private TableLayoutPanel _tableLayoutPanel;
private Label _lblName;
private TextBox _txtName;
private Label _lblEmail;
private TextBox _txtEmail;
private FlowLayoutPanel _buttonPanel;
private Button _btnOK;
private Button _btnCancel;
```

## Complex Nested Layout Pattern (Designer-Compatible)

For complex layouts with toolbar, content area, and status bar, all controls are still declared as backing fields and configured inside `InitializeComponent`. The key is nesting containers:

```csharp
// In MainForm.Designer.cs
private void InitializeComponent()
{
    _outerLayout = new TableLayoutPanel();
    _toolStrip = new ToolStrip();
    _splitContainer = new SplitContainer();
    _treeView = new TreeView();
    _detailsPanel = new TableLayoutPanel();
    _lblDetail1 = new Label();
    _txtDetail1 = new TextBox();
    _statusStrip = new StatusStrip();
    _statusLabel = new ToolStripStatusLabel();

    SuspendLayout();
    _outerLayout.SuspendLayout();
    ((ISupportInitialize)_splitContainer).BeginInit();
    _splitContainer.Panel1.SuspendLayout();
    _splitContainer.Panel2.SuspendLayout();
    _splitContainer.SuspendLayout();
    _detailsPanel.SuspendLayout();

    // _outerLayout
    _outerLayout.ColumnCount = 1;
    _outerLayout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));
    _outerLayout.Controls.Add(_toolStrip, 0, 0);
    _outerLayout.Controls.Add(_splitContainer, 0, 1);
    _outerLayout.Controls.Add(_statusStrip, 0, 2);
    _outerLayout.Dock = DockStyle.Fill;
    _outerLayout.Location = new Point(0, 0);
    _outerLayout.Name = "_outerLayout";
    _outerLayout.RowCount = 3;
    _outerLayout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
    _outerLayout.RowStyles.Add(new RowStyle(SizeType.Percent, 100F));
    _outerLayout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
    _outerLayout.Size = new Size(800, 600);
    _outerLayout.TabIndex = 0;

    // _toolStrip
    _toolStrip.Location = new Point(0, 0);
    _toolStrip.Name = "_toolStrip";
    _toolStrip.Size = new Size(800, 25);
    _toolStrip.TabIndex = 0;

    // _splitContainer
    _splitContainer.Dock = DockStyle.Fill;
    _splitContainer.Location = new Point(3, 28);
    _splitContainer.Name = "_splitContainer";
    _splitContainer.Size = new Size(794, 544);
    _splitContainer.SplitterDistance = 250;
    _splitContainer.TabIndex = 1;

    // _treeView (in Panel1)
    _treeView.Dock = DockStyle.Fill;
    _treeView.Location = new Point(0, 0);
    _treeView.Name = "_treeView";
    _treeView.Size = new Size(250, 544);
    _treeView.TabIndex = 0;

    // _detailsPanel (in Panel2)
    _detailsPanel.ColumnCount = 2;
    _detailsPanel.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
    _detailsPanel.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));
    _detailsPanel.Controls.Add(_lblDetail1, 0, 0);
    _detailsPanel.Controls.Add(_txtDetail1, 1, 0);
    _detailsPanel.Dock = DockStyle.Fill;
    _detailsPanel.Location = new Point(0, 0);
    _detailsPanel.Name = "_detailsPanel";
    _detailsPanel.RowCount = 2;
    _detailsPanel.RowStyles.Add(new RowStyle(SizeType.AutoSize));
    _detailsPanel.RowStyles.Add(new RowStyle(SizeType.Percent, 100F));
    _detailsPanel.Size = new Size(540, 544);
    _detailsPanel.TabIndex = 0;

    // _lblDetail1
    _lblDetail1.Anchor = AnchorStyles.Left | AnchorStyles.Right;
    _lblDetail1.AutoSize = true;
    _lblDetail1.Location = new Point(3, 5);
    _lblDetail1.Name = "_lblDetail1";
    _lblDetail1.Size = new Size(42, 15);
    _lblDetail1.TabIndex = 0;
    _lblDetail1.Text = "Name:";

    // _txtDetail1
    _txtDetail1.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;
    _txtDetail1.Location = new Point(51, 3);
    _txtDetail1.Name = "_txtDetail1";
    _txtDetail1.Size = new Size(486, 23);
    _txtDetail1.TabIndex = 1;

    // _statusStrip
    _statusStrip.Location = new Point(0, 575);
    _statusStrip.Name = "_statusStrip";
    _statusStrip.Size = new Size(800, 25);
    _statusStrip.TabIndex = 2;

    // _statusLabel
    _statusLabel.Name = "_statusLabel";
    _statusLabel.Size = new Size(39, 20);
    _statusLabel.Text = "Ready";

    // Wire up panels
    _splitContainer.Panel1.Controls.Add(_treeView);
    _splitContainer.Panel2.Controls.Add(_detailsPanel);
    _statusStrip.Items.Add(_statusLabel);

    // MainForm
    AutoScaleDimensions = new SizeF(7F, 15F);
    AutoScaleMode = AutoScaleMode.Font;
    ClientSize = new Size(800, 600);
    Controls.Add(_outerLayout);
    Name = "MainForm";
    Text = "Application";

    _detailsPanel.ResumeLayout(false);
    _detailsPanel.PerformLayout();
    _splitContainer.Panel1.ResumeLayout(false);
    _splitContainer.Panel2.ResumeLayout(false);
    ((ISupportInitialize)_splitContainer).EndInit();
    _splitContainer.ResumeLayout(false);
    _outerLayout.ResumeLayout(false);
    _outerLayout.PerformLayout();
    ResumeLayout(false);
    PerformLayout();
}

private TableLayoutPanel _outerLayout;
private ToolStrip _toolStrip;
private SplitContainer _splitContainer;
private TreeView _treeView;
private TableLayoutPanel _detailsPanel;
private Label _lblDetail1;
private TextBox _txtDetail1;
private StatusStrip _statusStrip;
private ToolStripStatusLabel _statusLabel;
```

**Key points:**

- All controls are backing fields, not local variables
- No helper methods ─ everything is in `InitializeComponent`
- SuspendLayout/ResumeLayout called for each container
- ISupportInitialize used for SplitContainer
- Form configuration is LAST

## RadioButton Cluster Pattern (Designer-Compatible)

RadioButton groups use a GroupBox with a nested single-column TableLayoutPanel. All configured in `InitializeComponent`:

```csharp
// Inside InitializeComponent (showing relevant section)

// Instantiation
_grpOptions = new GroupBox();
_radioLayout = new TableLayoutPanel();
_rbOption1 = new RadioButton();
_rbOption2 = new RadioButton();
_rbOption3 = new RadioButton();

// ...after SuspendLayout()...

// _grpOptions
_grpOptions.AutoSize = true;
_grpOptions.AutoSizeMode = AutoSizeMode.GrowAndShrink;
_grpOptions.Controls.Add(_radioLayout);
_grpOptions.Location = new Point(3, 3);
_grpOptions.Name = "_grpOptions";
_grpOptions.Size = new Size(150, 100);
_grpOptions.TabIndex = 0;
_grpOptions.TabStop = false;
_grpOptions.Text = "Select Option";

// _radioLayout
_radioLayout.AutoSize = true;
_radioLayout.ColumnCount = 1;
_radioLayout.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
_radioLayout.Controls.Add(_rbOption1, 0, 0);
_radioLayout.Controls.Add(_rbOption2, 0, 1);
_radioLayout.Controls.Add(_rbOption3, 0, 2);
_radioLayout.Dock = DockStyle.Fill;
_radioLayout.Location = new Point(3, 19);
_radioLayout.Name = "_radioLayout";
_radioLayout.RowCount = 3;
_radioLayout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
_radioLayout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
_radioLayout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
_radioLayout.Size = new Size(144, 78);
_radioLayout.TabIndex = 0;

// _rbOption1
_rbOption1.AutoSize = true;
_rbOption1.Location = new Point(3, 3);
_rbOption1.Name = "_rbOption1";
_rbOption1.Size = new Size(72, 19);
_rbOption1.TabIndex = 0;
_rbOption1.Text = "Option 1";
_rbOption1.UseVisualStyleBackColor = true;

// _rbOption2
_rbOption2.AutoSize = true;
_rbOption2.Location = new Point(3, 28);
_rbOption2.Name = "_rbOption2";
_rbOption2.Size = new Size(72, 19);
_rbOption2.TabIndex = 1;
_rbOption2.Text = "Option 2";
_rbOption2.UseVisualStyleBackColor = true;

// _rbOption3
_rbOption3.AutoSize = true;
_rbOption3.Location = new Point(3, 53);
_rbOption3.Name = "_rbOption3";
_rbOption3.Size = new Size(72, 19);
_rbOption3.TabIndex = 2;
_rbOption3.Text = "Option 3";
_rbOption3.UseVisualStyleBackColor = true;

// Backing fields at EOF:
private GroupBox _grpOptions;
private TableLayoutPanel _radioLayout;
private RadioButton _rbOption1;
private RadioButton _rbOption2;
private RadioButton _rbOption3;
```

## Form/Control Initialization Order

### Constructor Execution Chain

**CRITICAL:** WinForms uses OOP inheritance and virtual methods heavily. For inherited controls, the inherited constructor does NOT run first!

**Order of Execution:**

1. Base class field initializers
2. Base class constructor
3. (If overridden) `DefaultSize` of youngest descendant
4. (If overridden) `SetStyle` of youngest descendant
5. Likely all `SetStyle` calls in inheritance chain up to base
6. (If overridden) `CreateParams` of youngest descendant
7. Likely all `CreateParams` calls in inheritance chain up to base
8. All constructor bodies, oldest to youngest descendant
9. Field initializers of youngest descendant
10. Constructor body of youngest descendant

### Why This Matters

**When overriding `CreateParams` or `SetStyle`:**

- Class constructor has NOT run yet
- Accessing backing fields may get `null` or uninitialized values
- Return const values for `DefaultSize` ─ don't depend on constructor state

**Example:**

```csharp
public class CustomControl : Control
{
    private int _borderWidth;

    public CustomControl()
    {
        _borderWidth = 2;  // This runs AFTER CreateParams
    }

    protected override CreateParams CreateParams
    {
        get
        {
            CreateParams cp = base.CreateParams;
            // ❌ WRONG - _borderWidth is still 0 here!
            // cp.ExStyle |= _borderWidth;

            // ✅ CORRECT - Use const or literal
            cp.ExStyle |= 2;
            return cp;
        }
    }

    protected override Size DefaultSize
    {
        get
        {
            // ✅ CORRECT - Return const values
            return new Size(200, 100);

            // ❌ WRONG - Don't depend on fields
            // return new Size(_width, _height);
        }
    }
}
```

## Fullscreen Pattern (Presentations, Kiosk Mode)

### CRITICAL: State Initialization

**Initialize state variables BEFORE entering fullscreen!**

```csharp
public class PresentationForm : Form
{
    private bool _isFullscreen = false;
    private FormWindowState _previousWindowState;
    private FormBorderStyle _previousBorderStyle;

    public PresentationForm()
    {
        InitializeComponent();

        // CRITICAL: Store state BEFORE first fullscreen call
        _previousWindowState = WindowState;
        _previousBorderStyle = FormBorderStyle;

        // Now safe to enter fullscreen
        EnterFullscreen();
    }

    private void EnterFullscreen()
    {
        if (_isFullscreen) return;

        _previousWindowState = WindowState;
        _previousBorderStyle = FormBorderStyle;

        FormBorderStyle = FormBorderStyle.None;
        WindowState = FormWindowState.Maximized;
        _isFullscreen = true;
    }

    private void ExitFullscreen()
    {
        if (!_isFullscreen) return;

        FormBorderStyle = _previousBorderStyle;
        WindowState = _previousWindowState;
        _isFullscreen = false;
    }

    protected override bool ProcessCmdKey(ref Message msg, Keys keyData)
    {
        if (keyData == Keys.F11)
        {
            if (_isFullscreen)
                ExitFullscreen();
            else
                EnterFullscreen();
            return true;
        }

        if (keyData == Keys.Escape && _isFullscreen)
        {
            ExitFullscreen();
            return true;
        }

        return base.ProcessCmdKey(ref msg, keyData);
    }
}
```

**Without pre-initialization:** Form appears offset (approximately 1/8th screen) on first fullscreen.

## Modal Dialog Patterns

### Dialog Button Configuration

| Aspect | Rule |
|--------|------|
| Primary button (OK) | `AcceptButton` property, `DialogResult = OK` |
| Secondary button (Cancel) | `CancelButton` property, `DialogResult = Cancel` |
| Close strategy | `DialogResult` applied automatically, no additional code needed |
| Validation | Perform at Form level, never block focus change with `Cancel = true` |

### Example: Modal Dialog (Designer-Compatible)

```csharp
// InputDialog.cs (main file)
public partial class InputDialog : Form
{
    public string InputValue => _txtInput.Text;

    public InputDialog(string prompt)
    {
        InitializeComponent();
        _lblPrompt.Text = prompt;
    }
}

// InputDialog.Designer.cs
partial class InputDialog
{
    private void InitializeComponent()
    {
        _layoutPanel = new TableLayoutPanel();
        _lblPrompt = new Label();
        _txtInput = new TextBox();
        _buttonPanel = new FlowLayoutPanel();
        _btnOK = new Button();
        _btnCancel = new Button();

        SuspendLayout();
        _layoutPanel.SuspendLayout();

        // _layoutPanel
        _layoutPanel.ColumnCount = 1;
        _layoutPanel.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));
        _layoutPanel.Controls.Add(_lblPrompt, 0, 0);
        _layoutPanel.Controls.Add(_txtInput, 0, 1);
        _layoutPanel.Controls.Add(_buttonPanel, 0, 2);
        _layoutPanel.Dock = DockStyle.Fill;
        _layoutPanel.Location = new Point(0, 0);
        _layoutPanel.Name = "_layoutPanel";
        _layoutPanel.RowCount = 3;
        _layoutPanel.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        _layoutPanel.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        _layoutPanel.RowStyles.Add(new RowStyle(SizeType.Percent, 100F));
        _layoutPanel.Size = new Size(350, 150);
        _layoutPanel.TabIndex = 0;

        // _lblPrompt
        _lblPrompt.AutoSize = true;
        _lblPrompt.Location = new Point(3, 3);
        _lblPrompt.Margin = new Padding(3);
        _lblPrompt.Name = "_lblPrompt";
        _lblPrompt.Size = new Size(47, 15);
        _lblPrompt.TabIndex = 0;
        _lblPrompt.Text = "Prompt:";

        // _txtInput
        _txtInput.Anchor = AnchorStyles.Left | AnchorStyles.Right;
        _txtInput.Location = new Point(3, 24);
        _txtInput.Margin = new Padding(3);
        _txtInput.Name = "_txtInput";
        _txtInput.Size = new Size(344, 23);
        _txtInput.TabIndex = 1;

        // _buttonPanel
        _buttonPanel.Anchor = AnchorStyles.Bottom | AnchorStyles.Right;
        _buttonPanel.AutoSize = true;
        _buttonPanel.FlowDirection = FlowDirection.LeftToRight;
        _buttonPanel.Location = new Point(188, 118);
        _buttonPanel.Name = "_buttonPanel";
        _buttonPanel.Size = new Size(159, 29);
        _buttonPanel.TabIndex = 2;

        // _btnOK
        _btnOK.DialogResult = DialogResult.OK;
        _btnOK.Location = new Point(3, 3);
        _btnOK.Name = "_btnOK";
        _btnOK.Size = new Size(75, 23);
        _btnOK.TabIndex = 0;
        _btnOK.Text = "OK";
        _btnOK.UseVisualStyleBackColor = true;

        // _btnCancel
        _btnCancel.DialogResult = DialogResult.Cancel;
        _btnCancel.Location = new Point(84, 3);
        _btnCancel.Name = "_btnCancel";
        _btnCancel.Size = new Size(75, 23);
        _btnCancel.TabIndex = 1;
        _btnCancel.Text = "Cancel";
        _btnCancel.UseVisualStyleBackColor = true;

        // _buttonPanel - add buttons
        _buttonPanel.Controls.Add(_btnOK);
        _buttonPanel.Controls.Add(_btnCancel);

        // InputDialog
        AcceptButton = _btnOK;
        AutoScaleDimensions = new SizeF(7F, 15F);
        AutoScaleMode = AutoScaleMode.Font;
        CancelButton = _btnCancel;
        ClientSize = new Size(350, 150);
        Controls.Add(_layoutPanel);
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;
        Name = "InputDialog";
        StartPosition = FormStartPosition.CenterParent;
        Text = "Input";

        _layoutPanel.ResumeLayout(false);
        _layoutPanel.PerformLayout();
        ResumeLayout(false);
        PerformLayout();
    }

    private TableLayoutPanel _layoutPanel;
    private Label _lblPrompt;
    private TextBox _txtInput;
    private FlowLayoutPanel _buttonPanel;
    private Button _btnOK;
    private Button _btnCancel;
}
```

**Usage:**

```csharp
using InputDialog dialog = new InputDialog("Enter name:");
if (dialog.ShowDialog() == DialogResult.OK)
{
    string value = dialog.InputValue;
}
```

### .NET 8+ DataContext Pattern

```csharp
public partial class PersonEditDialog : Form
{
    private PersonViewModel _viewModel;

    public PersonEditDialog(PersonViewModel viewModel)
    {
        ArgumentNullException.ThrowIfNull(viewModel);
        _viewModel = viewModel;

        InitializeComponent();
        DataContext = _viewModel;
    }
}
```

## Button Layout Pattern (High-DPI Aware)

### Goal

Ensure buttons in a logical group (OK/Cancel or Yes/No/Cancel) have:

- Same size
- Never clip text
- Scale properly with DPI

### Case 1: Inside TableLayoutPanel

Buttons in the same row or column of a TableLayoutPanel can use AutoSize with cell anchoring:

```csharp
// Inside InitializeComponent (showing relevant properties)

// _btnOK
_btnOK.AutoSize = true;
_btnOK.AutoSizeMode = AutoSizeMode.GrowAndShrink;
_btnOK.Anchor = AnchorStyles.Left | AnchorStyles.Top | AnchorStyles.Right | AnchorStyles.Bottom;

// _btnCancel
_btnCancel.AutoSize = true;
_btnCancel.AutoSizeMode = AutoSizeMode.GrowAndShrink;
_btnCancel.Anchor = AnchorStyles.Left | AnchorStyles.Top | AnchorStyles.Right | AnchorStyles.Bottom;

// Row must be AutoSize
_tableLayoutPanel.RowStyles.Add(new RowStyle(SizeType.AutoSize));
```

### Case 2: Reusable ButtonContainer UserControl

For uniform button sizing across dialogs, create a reusable `ButtonContainer` as a proper UserControl or custom control (with its own Designer file):

```csharp
// ButtonContainer.cs
public class ButtonContainer : FlowLayoutPanel
{
    private bool _isInLayout = false;

    public ButtonContainer()
    {
        AutoSize = true;
        AutoSizeMode = AutoSizeMode.GrowAndShrink;
        FlowDirection = FlowDirection.LeftToRight;
        MinimumSize = new Size(300, 200);
    }

    protected override void OnControlAdded(ControlEventArgs e)
    {
        base.OnControlAdded(e);

        if (e.Control is not Button button)
        {
            Controls.Remove(e.Control);
            throw new InvalidOperationException(
                "ButtonContainer can only contain Button controls.");
        }

        button.AutoSize = true;
        button.AutoSizeMode = AutoSizeMode.GrowAndShrink;
        MinimumSize = Size.Empty;
    }

    protected override void OnLayout(LayoutEventArgs levent)
    {
        if (_isInLayout)
        {
            base.OnLayout(levent);
            return;
        }

        try
        {
            _isInLayout = true;

            int maxWidth = 0;
            int maxHeight = 0;

            foreach (Control control in Controls)
            {
                if (control is Button button)
                {
                    button.MinimumSize = Size.Empty;
                    button.PerformLayout();

                    Size preferred = button.PreferredSize;
                    maxWidth = Math.Max(maxWidth, preferred.Width);
                    maxHeight = Math.Max(maxHeight, preferred.Height);
                }
            }

            Size uniformSize = new Size(maxWidth, maxHeight);
            foreach (Control control in Controls)
            {
                if (control is Button button)
                {
                    if (button.MinimumSize != uniformSize)
                    {
                        button.MinimumSize = uniformSize;
                    }
                }
            }

            base.OnLayout(levent);
        }
        finally
        {
            _isInLayout = false;
        }
    }

    protected override void OnControlRemoved(ControlEventArgs e)
    {
        base.OnControlRemoved(e);

        if (Controls.Count == 0)
        {
            MinimumSize = new Size(300, 200);
        }
    }
}
```

**Critical Implementation Details:**

- Use `_isInLayout` flag to prevent recursion
- Use `Size.Empty` when clearing `MinimumSize` (not `new Size(0,0)`)
- Only update `MinimumSize` if value changed
- Call base methods FIRST in override methods

## Window Position Management

### Saving and Restoring

**CRITICAL:** Use `Form.RestoreBounds`, not `Location` or `Size`!

```csharp
public partial class MainForm : Form
{
    protected override void OnFormClosing(FormClosingEventArgs e)
    {
        base.OnFormClosing(e);

        // ✅ CORRECT - Use RestoreBounds
        Properties.Settings.Default.WindowX = RestoreBounds.X;
        Properties.Settings.Default.WindowY = RestoreBounds.Y;
        Properties.Settings.Default.WindowWidth = RestoreBounds.Width;
        Properties.Settings.Default.WindowHeight = RestoreBounds.Height;
        Properties.Settings.Default.WindowState = WindowState;
        Properties.Settings.Default.Save();
    }

    protected override void OnLoad(EventArgs e)
    {
        base.OnLoad(e);

        if (Properties.Settings.Default.WindowWidth > 0)
        {
            StartPosition = FormStartPosition.Manual;
            Location = new Point(
                Properties.Settings.Default.WindowX,
                Properties.Settings.Default.WindowY);
            Size = new Size(
                Properties.Settings.Default.WindowWidth,
                Properties.Settings.Default.WindowHeight);
            WindowState = Properties.Settings.Default.WindowState;
        }
    }
}
```

**Why RestoreBounds:**

- `Location` and `Size` return incorrect values when maximized/minimized
- `RestoreBounds` always contains last normal (non-maximized/minimized) position
- Read `RestoreBounds` no earlier than `Form.Closing` event

## Accessibility

### Essential Accessibility Features

Set these in `InitializeComponent` (Designer-compatible):

```csharp
// Inside InitializeComponent
_txtName.AccessibleName = "Name";
_txtName.AccessibleDescription = "Enter the person's full name";

// Maintain logical TabIndex
_txtName.TabIndex = 0;
_txtEmail.TabIndex = 1;
_btnOK.TabIndex = 2;
_btnCancel.TabIndex = 3;
```

Verify keyboard-only navigation works: Tab, Shift+Tab, Enter, Escape.

## Resources and Localization

### Layout Considerations for Localization

- Account for longer translations (German, Finnish typically longest)
- Use AutoSize where possible
- Test with longest expected translations
- Use TableLayoutPanel percentage columns for flexibility
- Avoid fixed-width columns for text content

## Best Practices Summary

### DO

✅ Use TableLayoutPanel for structured layouts
✅ Prefer AutoSize > Percent > Absolute sizing
✅ Set Anchor on controls in TableLayoutPanel cells
✅ Use nested TableLayoutPanels for complex layouts
✅ Set Margin on controls (min 3px)
✅ Use RestoreBounds for window position
✅ Initialize fullscreen state before first call
✅ Use GroupBoxes for visual grouping
✅ Implement proper accessibility features
✅ Keep all layout configuration in `InitializeComponent`
✅ Declare controls as backing fields, not local variables

### DON'T

❌ Dock controls in TableLayoutPanel cells
❌ Create one mega-grid for entire form
❌ Use Absolute sizing unless necessary
❌ Forget Padding doesn't work in TableLayoutPanel
❌ Save Location/Size when maximized
❌ Skip accessibility properties
❌ Design layouts that don't scale
❌ Extract control setup into helper methods (breaks Designer)
❌ Use object initializers for control properties
❌ Declare layout controls as local variables

## Troubleshooting

**Controls not sizing correctly:**

- Check AutoSize and AutoSizeMode settings
- Verify Anchor properties
- Ensure row/column SizeType is appropriate
- Check Margin values

**Layout not responsive:**

- Use Percent sizing instead of Absolute
- Verify Anchor includes all needed sides
- Check that parent containers allow growth

**DPI scaling issues:**

- Verify AutoScaleMode is set correctly
- Use percentage-based layouts
- Test on different DPI settings
- Avoid hard-coded pixel values

**Fullscreen appears offset:**

- Initialize state variables in constructor
- Store WindowState and FormBorderStyle before first fullscreen

## Summary

Effective WinForms High-DPI fluent layout requires:

- Strategic use of TableLayoutPanel and nesting
- Proper AutoSize/Percent/Absolute sizing decisions
- Correct Anchor settings on controls
- DPI awareness and testing
- All layout code inside `InitializeComponent` (Designer-compatible)
- Accessibility consideration

Follow these patterns for layouts that scale properly across DPI settings, support accessibility, and remain Designer-compatible.
