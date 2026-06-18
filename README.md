# Upgrade

A GitHub Copilot CLI plugin marketplace for AI-assisted application upgrades.

This repository will host plugins that help you upgrade, migrate, and modernize applications across languages, frameworks, and platforms. It is published as a [Copilot CLI plugin marketplace](https://docs.github.com/en/copilot/github-copilot-cli) — as plugins are added here, you can install them into your Copilot CLI with a single command.

## Install in the GitHub Copilot App

If you have the [GitHub Copilot desktop app](https://docs.github.com/en/copilot) installed, you can add this marketplace and install the upgrade agent with one click. Each link opens a confirmation in the app and pre-fills the Plugins settings form — just click **Add** / **Install** to finish.

**1. Add this marketplace** (one-time):

[Add `upgrade-agent-plugins` marketplace](https://github.com/copilot/app/launch?entry_point=upgrade_agent_plugins_readme&open=ghapp%3A%2F%2Fplugins%2Fmarketplace%2Fadd%3Fsource%3Dmicrosoft%2Fupgrade-agent-plugins)

**2. Install the upgrade agent:**

[Install `upgrade-agent`](https://github.com/copilot/app/launch?entry_point=upgrade_agent_plugins_readme&open=ghapp%3A%2F%2Fplugins%2Finstall%3Fsource%3Dupgrade-agent%40upgrade-agent-plugins)

> [!NOTE]
> Add the marketplace **before** installing — the install link only works once `upgrade-agent-plugins` is registered.

<details>
<summary>Direct CLI commands</summary>

Prefer the command line? Run these in the Copilot CLI:

```text
/plugin marketplace add microsoft/upgrade-agent-plugins
/plugin install upgrade-agent@upgrade-agent-plugins
```

</details>
