# Pre-Initialization — MCP Apps Path

This file is loaded only when `confirm_options` is present in your tool list (i.e. the client
supports MCP Apps). Follow it instead of the text-based fallback.

## Call confirm_options

After `get_dotnet_upgrade_options` returns, build the options list and call `confirm_options`
immediately:

```
confirm_options(
  title: "Upgrade .NET projects to <suggested_tfm>",
  description: "Review and confirm your upgrade settings.",
  options: "<JSON string — see below>"
)
```

### Base options (always include)

```json
[
  {
    "id": "tfm",
    "type": "select",
    "label": "Target Framework",
    "value": "<suggested_tfm>",
    "description": "The .NET version to upgrade your projects to",
    "choices": [
      { "id": "net10.0", "label": ".NET 10", "hint": "LTS — Support ends Nov 2027", "badge": "LTS" },
      { "id": "net9.0",  "label": ".NET 9",  "hint": "STS — Support ends May 2026", "badge": "STS" }
    ]
  },
  {
    "id": "flowMode",
    "type": "select",
    "label": "Flow Mode",
    "value": "automatic",
    "description": "How the agent pauses during execution",
    "choices": [
      { "id": "automatic", "label": "Automatic", "hint": "Run end-to-end, pause only when blocked" },
      { "id": "guided",    "label": "Guided",    "hint": "Pause after each stage for review" }
    ]
  },
  {
    "id": "solution",
    "type": "readonly",
    "label": "Solution",
    "value": "<solution file path, if present>"
  }
]
```

### Git repo additions (insert before the `solution` entry when in a git repo)

```json
  { "id": "workingBranch", "type": "text", "label": "Working Branch", "value": "<suggestedWorkingBranch>" },
  { "id": "commitStrategy", "type": "select", "label": "Commit Strategy", "value": "after-each-task",
    "choices": [
      { "id": "after-each-task",  "label": "After Each Task",  "hint": "default" },
      { "id": "after-each-phase", "label": "After Each Phase" },
      { "id": "single",           "label": "Single Commit at End" },
      { "id": "manual",           "label": "Manual" }
    ]
  },
```

### Building choices from get_dotnet_upgrade_options

Use the framework list returned by `get_dotnet_upgrade_options` for `choices`. For each entry:

| Field   | How to set it |
|---------|---------------|
| `id`    | TFM moniker — e.g. `"net10.0"` |
| `label` | Clean short name — e.g. `.NET 10` (no support tier in label) |
| `hint`  | Support tier + end-of-support date — e.g. `"LTS — Support ends Nov 2027"` |
| `badge` | Support tier tag: `"LTS"`, `"STS"`, or `"PREVIEW"` (rendered as an amber pill) |

For preview/RC frameworks: use `badge: "PREVIEW"` and note "not for production" in `hint`.

## After confirm_options returns

When `confirm_options` returns `{ confirmed: true, values }`:

- `values.tfm` → confirmed target framework; pass as `targetFramework` to `initialize_scenario`
- `values.flowMode` → flow mode for execution stage
- `values.workingBranch` + `values.commitStrategy` → git settings (if present)
