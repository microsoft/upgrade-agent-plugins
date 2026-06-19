# Validation Rules

## Contents
- Structure Validation
- Description Quality
- Content Quality
- Progressive Disclosure
- Workflows and Feedback Loops
- Code Quality
- Anti-Patterns
- Overlap Detection
- Scoring

Run every rule against the skill being validated. Report results as ✅ pass, ⚠️ warning, or ❌ fail.

## 1. Structure Validation

### 1.1 Frontmatter (❌ if any fail)
- [ ] SKILL.md exists at the skill root
- [ ] YAML frontmatter is present (delimited by `---`)
- [ ] `name` field exists and is non-empty
- [ ] `name` is ≤64 characters
- [ ] `name` contains only lowercase letters, numbers, hyphens
- [ ] `name` does not contain "anthropic" or "claude"
- [ ] `description` field exists and is non-empty
- [ ] `description` is ≤1024 characters
- [ ] Neither `name` nor `description` contains XML tags
- [ ] Custom `metadata` fields (if present) are preserved — these are project-specific extensions for skill routing (e.g., `metadata.traits`, `metadata.discovery`)

### 1.2 File organization (⚠️ if fail)
- [ ] SKILL.md body is under 500 lines
- [ ] Reference files are max one level deep from SKILL.md (no chain: SKILL.md → A.md → B.md)
- [ ] Reference files over 100 lines include a table of contents
- [ ] All file paths use forward slashes (no backslashes)
- [ ] Files and directories are named descriptively (not `doc2.md` or `file1.md`)

### 1.3 Directory conventions (⚠️ if fail)
- [ ] Scripts in `scripts/` directory
- [ ] Reference docs in `references/` directory
- [ ] Templates in `templates/` or `assets/` directory
- [ ] No unnecessary nesting of directories

## 2. Description Quality

### 2.1 Effectiveness (❌ if any fail)
- [ ] `name` starts with a gerund verb (e.g., `migrating-`, `converting-`, `managing-`)
- [ ] `name` is concise — omits redundant words (no `-migration` suffix when name starts with `migrating-`)
- [ ] Written in third person ("Processes files" not "I can help you" or "You can use")
- [ ] Describes WHAT the skill does
- [ ] Describes WHEN to use it (trigger contexts)
- [ ] Includes specific trigger terms and phrases
- [ ] Specific enough to differentiate from other skills

### 2.2 Trigger coverage (⚠️ if fail)
- [ ] Mentions relevant file types or extensions
- [ ] Mentions key user phrases that should trigger it
- [ ] Mentions adjacent contexts where the skill should still trigger
- [ ] Slightly "pushy" — errs toward triggering rather than missing

### 2.3 Anti-patterns in descriptions
- [ ] Not vague ("Helps with documents", "Processes data", "Does stuff")
- [ ] Not a wall of text — stays focused and scannable
- [ ] Doesn't duplicate SKILL.md body content

## 3. Content Quality

### 3.1 Conciseness (⚠️ if fail)
- [ ] No explanations of things Claude already knows (what PDFs are, how libraries work, basic programming concepts)
- [ ] No filler paragraphs or unnecessary background
- [ ] Each section justifies its token cost
- [ ] Examples are concrete and minimal, not padded

### 3.2 Freedom calibration (⚠️ if fail)
- [ ] High-freedom (guidelines) used for tasks where multiple approaches work
- [ ] Low-freedom (exact scripts) used for fragile/order-dependent operations
- [ ] Not everything is locked down with rigid MUST/NEVER rules
- [ ] Reasoning is explained rather than enforced by fiat

### 3.3 Terminology (⚠️ if fail)
- [ ] One term per concept used consistently throughout
- [ ] No mixing synonyms (e.g., "endpoint" / "URL" / "route" / "path" for the same thing)
- [ ] Technical terms are appropriate for the skill's audience
- [ ] Uses "project file" generically instead of `.csproj` when context applies to multiple .NET languages (C#, VB.NET, F#)

### 3.4 Instruction style (⚠️ if fail)
- [ ] Uses imperative form ("Extract the text" not "You should extract the text")
- [ ] Explains WHY behind important rules rather than just stating them
- [ ] No excessive ALL CAPS or bold for emphasis — reasoning beats shouting
- [ ] Uses theory of mind — generalizes rather than overfitting to examples

## 4. Progressive Disclosure

### 4.1 Architecture (⚠️ if fail)
- [ ] SKILL.md serves as an overview/table of contents for complex skills
- [ ] Detailed domain-specific content is in separate reference files
- [ ] SKILL.md tells Claude when to read each reference file
- [ ] Reference files are organized by domain or feature, not arbitrarily

### 4.2 Loading efficiency (⚠️ if fail)
- [ ] Large reference content isn't in SKILL.md body
- [ ] Scripts are designed to be executed, not loaded into context (unless reading is specifically needed)
- [ ] Clear instructions on whether to execute or read each script

## 5. Workflows and Feedback Loops

### 5.1 Complex tasks (⚠️ if fail, when applicable)
- [ ] Multi-step operations have clear sequential steps
- [ ] Complex workflows include a progress checklist Claude can track
- [ ] Decision points are explicit ("Creating new? → do X. Editing? → do Y.")

### 5.2 Validation loops (⚠️ if fail, when applicable)
- [ ] Quality-critical operations include a validate → fix → retry loop
- [ ] Validation scripts produce specific, actionable error messages
- [ ] The skill says when to validate, not just how

## 6. Code Quality (skip if skill has no scripts)

### 6.1 Error handling (❌ if fail)
- [ ] Scripts handle errors explicitly (try/catch, specific error types)
- [ ] No bare `open(path).read()` without error handling
- [ ] Errors produce helpful messages, not silent failures

### 6.2 Constants and configuration (⚠️ if fail)
- [ ] No unexplained constants — all magic numbers are explained
- [ ] Configuration values have comments explaining their rationale
- [ ] Default values are justified

### 6.3 Dependencies (❌ if fail)
- [ ] Required packages are listed with install commands
- [ ] No assumption that packages are pre-installed
- [ ] Dependencies are verified as available in the target runtime

### 6.4 Script patterns (⚠️ if fail)
- [ ] Scripts solve problems rather than punting to Claude
- [ ] Intermediate outputs are verifiable (plan-validate-execute pattern)
- [ ] MCP tool references use fully qualified names (`ServerName:tool_name`)

## 7. Anti-Patterns

### 7.1 Critical anti-patterns (❌ if found)
- [ ] No Windows-style backslash paths
- [ ] No time-sensitive information without being in an "old patterns" section
- [ ] No deeply nested reference chains (A → B → C)
- [ ] No assumptions about tools being installed without checking

### 7.2 Quality anti-patterns (⚠️ if found)
- [ ] Doesn't offer too many equivalent options without a clear default
- [ ] Doesn't include information that will become outdated
- [ ] No first-person or second-person language in the description
- [ ] No duplicate content between SKILL.md and reference files

## 8. Overlap Detection

### 8.1 Name uniqueness (❌ if fail)
- [ ] No other skill in the repository has the same `name`
- [ ] No other skill has a name that differs only by word order (e.g., `pdf-processing` vs `processing-pdfs`)

### 8.2 Trigger overlap (⚠️ if fail)
- [ ] Description trigger phrases don't substantially overlap with another skill's triggers
- [ ] If overlap exists, the skills are differentiated by scope or approach
- [ ] Cross-references are added when skills are related but distinct (e.g., "For X, see [other-skill]")

---

## Scoring

Count the results:

| Category | Weight | Scoring |
|----------|--------|---------|
| ❌ Fail | Blocking | Must fix before the skill is ready |
| ⚠️ Warning | Important | Should fix; may pass review with justification |
| ✅ Pass | Good | No action needed |

**Ready for review:** Zero ❌ fails and at most 2 ⚠️ warnings with documented justification.
