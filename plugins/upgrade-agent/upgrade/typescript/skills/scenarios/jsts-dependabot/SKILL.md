---
name: jsts-dependabot
description: >
  Validate and repair a JavaScript or TypeScript dependency update that
  Dependabot has already selected and applied. Use when a Dependabot update
  requires JSTS install, compile, build, test, or runtime validation before
  Dependabot creates its pull request.
requires-extension: upgrade-typescript
metadata:
  discovery: scenario
  importance: default
  weight: 0
  traits: NodeJs|TypeScript|JavaScript
  scenarioTraitsSet: [NodeJs, TypeScript, JavaScript]
---

# JSTS Dependabot Validation Scenario

Use this scenario when Dependabot has already selected and applied a JavaScript
or TypeScript dependency update and now needs that update validated before it
opens its pull request.

You are the upgrade orchestrator. Do not validate the update yourself and do not
reopen the dependency decision: Dependabot owns which version to install and
owns creating the pull request. This scenario's only job is to hand the
already-applied update to the JSTS validation agent and relay that agent's
result back to Dependabot.

## Scope

- Do not select a different upgrade merely because a newer version exists.
- Do not run broad dependency modernization.
- Preserve the minimum secure version Dependabot selected.
- Limit changes to the compatibility repairs the existing update requires.
- Do not push, create a pull request, or otherwise take over Dependabot's PR flow.

## Validation

Before dispatch, call `Upgrade/get_instructions` with `kind='skill'` and each
exact skill name below as `query`. Pass the returned absolute skill directories
to the worker as `guidancePaths`; each response's `path` is the installed
directory, not a SKILL.md filename. Do not infer paths from the host's
environment or plugin layout. If any exact skill or absolute directory is
unavailable, report `upgrade_guidance_unavailable` without dispatching.

```json
{
  "guidancePaths": {
    "typescript-dependencies-upgrade": "<returned absolute skill directory>",
    "typescript-compiler-upgrade": "<returned absolute skill directory>",
    "typescript-runtime-validation": "<returned absolute skill directory>"
  }
}
```

Invoke agent `jsts-dependabot-validator` using the `agent` tool. Invoke it
exactly once and let it drive install, compile, build, test, and runtime
validation through the JSTS Upgrade Assistant tools.

Pass the agent:

- the installed skill directories in `guidancePaths`;
- the repository root and package directory;
- the package manager;
- the affected dependency;
- its previous, selected, and minimum secure versions;
- the Dependabot alert metadata;
- the source and target branch information;
- the current Git status and any changes Dependabot has already applied;
- the artifact output path;
- the instruction to return control to Dependabot once validation finishes.

Require the agent to report back:

- the validation status;
- the initial failures and any that remain;
- the authentication outcome;
- the compatibility repairs it made;
- any unavoidable change to Dependabot's dependency selection;
- the validation artifact paths;
- the local commit SHA, if it changed files;
- confirmation that it did not push and did not create a pull request.

If agent `jsts-dependabot-validator` is unavailable, report a blocked
integration. Do not silently fall back to generic static validation in place of
the JSTS runtime validation this scenario requires.
