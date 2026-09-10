---
name: managing-dotnet-test-installation
description: >
  Installs the external dotnet-test plugin when its test-generation agent is unavailable. Use when a
  user selects AI test generation during an upgrade but code-testing-generator is not loaded.
metadata:
  traits: (CopilotCli|VsCode|GitHubCopilotApp) & (.NET|CSharp|VisualBasic|DotNetCore)
  discovery: lazy
  importance: high
  renderHostConditionals: true
---

# Installing the dotnet-test Plugin

The `dotnet-test` plugin must be loaded before the upgrade can generate a test baseline. Ask whether
the user wants to install it. If they decline, treat Test Coverage as **Skip**.

{{#if CopilotCli}}
Run:

```text
copilot plugin marketplace add dotnet/skills
copilot plugin install dotnet-test@dotnet-agent-skills
```

Then ask the user to restart the session (`/restart` or relaunch `copilot`) and re-run the upgrade.
Do not create test-baseline tasks in the current run because the plugin loads only after restart.
{{/if}}

{{#if VsCode}}
Ask the user to run **Chat: Install Plugin From Source** from the Command Palette and enter:

```text
https://github.com/dotnet/skills
```

When VS Code shows the plugins available from that source, ask the user to select `dotnet-test`.

Alternatively, add `dotnet/skills` to `chat.plugins.marketplaces`, then ask the user to install
`dotnet-test` from the `@agentPlugins` Extensions view. After installation, ask the user to continue
the current upgrade. Re-check that `code-testing-generator` is available, then resume planning.
{{/if}}

{{#if GitHubCopilotApp}}
Ask the user to open **Settings → Plugins** or use the **Extensions** menu in the GitHub Copilot App,
find the `dotnet-test` plugin from `dotnet/skills`, and install it. Then ask the user to continue the
current upgrade. Re-check that `code-testing-generator` is available before resuming planning.
{{/if}}
