# Quality Checklist

A quick-reference checklist for skill authors. For the full validation rules with pass/fail criteria, see [validation-rules.md](validation-rules.md).

## Before you start

- [ ] Scanned existing skills for name conflicts and trigger overlaps
- [ ] No duplicate or substantially overlapping skill exists
- [ ] Identified a clear, repeatable workflow that benefits from codification
- [ ] Know who the audience is (developers? non-technical users? both?)
- [ ] Have at least one concrete use case in mind to test against

## Core quality

- [ ] Name starts with a gerund verb and is concise
- [ ] Description is specific, third-person, includes trigger phrases
- [ ] SKILL.md body is under 500 lines
- [ ] Only adds context Claude doesn't already have
- [ ] Explains WHY behind rules, not just WHAT
- [ ] Consistent terminology throughout
- [ ] Uses language-neutral terms ("project file" not ".csproj") when not language-specific
- [ ] Examples are concrete, not abstract
- [ ] Freedom level matches task fragility

## Structure

- [ ] File references are one level deep from SKILL.md
- [ ] Reference files >100 lines have a table of contents
- [ ] Progressive disclosure: SKILL.md is the overview, details in reference files
- [ ] All paths use forward slashes
- [ ] Custom `metadata` fields preserved (if present in original)
- [ ] No time-sensitive information (or in "old patterns" section)

## Code and scripts (if applicable)

- [ ] Scripts handle errors explicitly with helpful messages
- [ ] No magic numbers without explanation
- [ ] Required packages listed with install commands
- [ ] Scripts solve problems (don't punt to Claude)
- [ ] Validation loops for quality-critical operations

## Testing

- [ ] At least 2-3 realistic test prompts (not abstract)
- [ ] Tested by following the skill's own instructions
- [ ] Edge cases considered

## Ready to submit

- [ ] Zero blocking validation failures
- [ ] User has reviewed and approved
- [ ] Final directory structure is clean and well-organized
