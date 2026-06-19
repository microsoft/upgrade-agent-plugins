# Anthropic Skill Authoring Best Practices

Condensed from https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices

This is a reference for understanding the principles behind the validation rules. Read this if you want the "why" behind each rule.

## Contents
- Core principles
- Skill structure
- Workflows and feedback loops
- Content guidelines
- Common patterns
- Evaluation and iteration
- Anti-patterns
- Advanced: executable code

---

## Core Principles

### Conciseness

The context window is a public good. Your skill shares it with the system prompt, conversation history, other skills' metadata, and the user's actual request.

Only metadata (name + description) is pre-loaded. SKILL.md loads when triggered. Reference files load on demand. But once loaded, every token competes for space.

**Default assumption: Claude is already very smart.** Challenge each piece of information: Does Claude really need this? Can I assume Claude knows this? Does this paragraph justify its token cost?

### Degrees of Freedom

Match specificity to the task's fragility:

- **High freedom** (text guidelines): Multiple approaches valid, context-dependent decisions. Example: code review criteria.
- **Medium freedom** (pseudocode/parameterized scripts): Preferred pattern exists but variation is acceptable. Example: report generation with format options.
- **Low freedom** (exact scripts, no parameters): Operations are fragile, consistency is critical, sequence matters. Example: database migrations.

Think of it as a robot on a path: narrow bridge with cliffs needs guardrails (low freedom); open field needs general direction (high freedom).

### Test across models

Skills effectiveness depends on the underlying model. What works for Opus might need more detail for Haiku. If targeting multiple models, aim for instructions that work across all of them.

---

## Skill Structure

### Frontmatter

Required fields in YAML frontmatter:
- `name`: ≤64 chars, lowercase letters/numbers/hyphens only, no XML tags, no "anthropic" or "claude"
- `description`: ≤1024 chars, non-empty, no XML tags

### Naming

**The gerund verb must be the first word** in the skill name. This makes names scannable and consistent across a large skill library.

| Action type | Pattern | Examples |
|-------------|---------|----------|
| Migration (A→B) | `migrating-{source}-to-{target}` | `migrating-wcf-to-corewcf` |
| Migration (general) | `migrating-{what}` | `migrating-aspnet-identity` |
| Conversion | `converting-to-{target}` | `converting-to-sdk-style` |
| Management | `managing-{what}` | `managing-target-frameworks` |

Acceptable but less preferred: noun phrases (`pdf-processing`) or imperative (`process-pdfs`).
Avoid: `helper`, `utils`, `tools`, `documents`, `data`, `files`.
Avoid redundant suffixes: don't add `-migration` when the name already starts with `migrating-`.

### Descriptions

Always third person. The description is injected into the system prompt.

Include both WHAT the skill does and WHEN to use it with specific trigger terms. The description is Claude's primary mechanism for choosing skills from potentially 100+ options.

### Progressive Disclosure

Three-level loading:
1. **Metadata** (name + description) — always in context (~100 words)
2. **SKILL.md body** — loaded when triggered (<500 lines ideal)
3. **Bundled resources** — loaded as needed (unlimited size)

Keep references one level deep from SKILL.md. No A → B → C chains. Reference files >100 lines should have a table of contents.

Organize by domain when supporting multiple areas:
```
bigquery-skill/
├── SKILL.md (overview + navigation)
└── reference/
    ├── finance.md
    ├── sales.md
    └── product.md
```

---

## Workflows and Feedback Loops

### Complex tasks

Break into clear sequential steps. For particularly complex workflows, provide a checklist Claude can track.

### Feedback loops

The pattern: run validator → fix errors → repeat. This greatly improves output quality. Works for both code (run validation script) and non-code (check against style guide) skills.

---

## Content Guidelines

### Avoid time-sensitive information

Don't include dates or "if before/after X" logic. Use an "old patterns" section for deprecated approaches.

### Use consistent terminology

Pick one term per concept and use it everywhere. Don't mix "API endpoint" / "URL" / "API route" / "path" for the same thing.

---

## Common Patterns

### Template pattern
Provide output format templates. Match strictness to requirements: exact template for API responses, flexible guidance for analytical reports.

### Examples pattern
Input/output pairs, just like in regular prompting. Especially valuable when output quality depends on seeing the desired style.

### Conditional workflow pattern
Guide through decision points: "Creating new? → Creation workflow. Editing? → Editing workflow."

---

## Evaluation and Iteration

### Build evaluations first

Create evaluations BEFORE writing extensive docs. This ensures the skill solves real problems, not imagined ones.

1. Run Claude on tasks without a skill. Document failures.
2. Create 3+ evaluation scenarios testing those gaps.
3. Measure baseline.
4. Write minimal instructions to address gaps.
5. Iterate: evaluate, compare, refine.

### Iterative development with Claude

Work with Claude A (the expert) to create/refine skills, test with Claude B (fresh instance with skill loaded). Observe Claude B's behavior, bring insights back to Claude A.

### Observe navigation patterns

Watch how Claude actually uses the skill: unexpected exploration paths, missed connections, overreliance on certain sections, ignored content. Iterate based on observation, not assumptions.

---

## Anti-Patterns

- **Windows paths**: Always use forward slashes
- **Too many options**: Provide a default with escape hatch, not a menu of equivalent choices
- **Assuming tools installed**: List dependencies with install commands
- **Vague names/descriptions**: Be specific and trigger-oriented
- **Nested references**: Keep one level deep
- **Time-sensitive info**: Use "old patterns" sections

---

## Advanced: Executable Code

### Solve, don't punt
Handle errors in scripts rather than letting them fail for Claude to figure out. Provide explicit error messages.

### No magic numbers
Every constant should have a comment explaining its rationale.

### Utility scripts
Pre-made scripts are more reliable than generated code, save tokens, save time, and ensure consistency. Make clear whether Claude should execute or read each script.

### Verifiable intermediate outputs
For complex operations, use plan-validate-execute: create a structured plan file, validate it with a script, then execute. Catches errors before they cascade.

### MCP tool references
Always use fully qualified names: `ServerName:tool_name`.

### Dependencies
List required packages with install commands. Verify availability in the target runtime.
