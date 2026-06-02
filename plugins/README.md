# Plugins

Each subdirectory of `plugins/` is a single Copilot CLI plugin published by this marketplace. There are no plugins here yet — this document describes the expected layout so contributors can add one.

## Expected layout

```
plugins/<plugin-name>/
├── .github/
│   └── plugin/
│       └── plugin.json         # Plugin manifest (required)
├── agents/
│   └── <plugin-name>.agent.md  # Agent definition(s) the plugin contributes
├── hooks/                      # Optional: lifecycle hook scripts
│   └── scripts/
├── hooks.json                  # Optional: hook registrations
└── README.md                   # Plugin-specific overview and usage
```

## `plugin.json`

Minimum fields:

```json
{
  "name": "<plugin-name>",
  "version": "0.1.0",
  "description": "Short, user-facing description of what the plugin does.",
  "author": { "name": "Microsoft" },
  "keywords": ["modernization"],
  "repository": "https://github.com/microsoft/modernize",
  "license": "MIT"
}
```

Add `"hooks": "hooks.json"` only if the plugin ships hook scripts.

## Installation (from this marketplace)

```
/plugin marketplace add microsoft/modernize
/plugin install <plugin-name>@modernize
```

## Naming

- Use lowercase, hyphen-separated names that match the folder name.
- Names must be unique within this marketplace.

## Proposing a new plugin

See [`../CONTRIBUTING.md`](../CONTRIBUTING.md). Open a **Plugin proposal** issue before sending a PR.
