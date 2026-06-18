# dotnet format — IDE Analyzer Rules for C# Modernization

## Contents
- [How dotnet format works](#how-dotnet-format-works)
- [Recommended workflow](#recommended-workflow)
- [Rules by C# version](#rules-by-c-version)
- [Features WITHOUT dotnet format fixers (LLM-only)](#features-without-dotnet-format-fixers-llm-only)
- [Generating an .editorconfig snippet](#generating-an-editorconfig-snippet)

This file maps `dotnet format`-fixable IDE analyzer rules to the C# language features they
modernize. Use this to build an `.editorconfig` snippet and run `dotnet format` for mechanical
🟢 ALWAYS-APPLY transformations, saving LLM tokens for judgment-heavy work.

## How dotnet format works

`dotnet format` reads `.editorconfig` rules and applies Roslyn-based code fixers. To auto-fix:

```bash
# Fix specific diagnostics (preferred — surgical)
dotnet format <solution.sln> --diagnostics IDE0090 IDE0063 IDE0161 --severity info

# Fix all style diagnostics at info severity or above
dotnet format style --severity info
```

Key flags:
- `--diagnostics <IDs>` — space-separated list of specific IDE rules to fix
- `--severity info` — required, otherwise most rules are skipped (default threshold is `warn`)
- `--verify-no-changes` — dry-run mode, exits non-zero if changes would be made
- `--include <paths>` — limit to specific files/folders
- `--exclude <paths>` — skip files/folders

## Recommended workflow

1. Generate `.editorconfig` entries for the target version (see below)
2. Run `dotnet format --verify-no-changes --severity info` to preview what would change
3. Run `dotnet format --severity info` to apply
4. Build and test to confirm no regressions
5. Commit the mechanical changes separately from LLM-driven changes

## Rules by C# version

### C# 7.x rules

| IDE Rule | Feature | .editorconfig option | Value |
|----------|---------|---------------------|-------|
| IDE0018 | Inline out variable declaration | `csharp_style_inlined_variable_declaration` | `true` |
| IDE0016 | Use throw expression | `csharp_style_throw_expression` | `true` |
| IDE0019 | Pattern matching: `as` + null check → `is` | `csharp_style_pattern_matching_over_as_with_null_check` | `true` |
| IDE0020 | Pattern matching: `is` + cast → type pattern | `csharp_style_pattern_matching_over_is_with_cast_check` | `true` |
| IDE0034 | Simplify `default(T)` → `default` | `csharp_prefer_simple_default_expression` | `true` |
| IDE0037 | Use inferred tuple element names | `dotnet_style_prefer_inferred_tuple_names` | `true` |
| IDE0021–IDE0027 | Expression-bodied members | `csharp_style_expression_bodied_*` | `when_on_single_line` |

### C# 8.0 rules

| IDE Rule | Feature | .editorconfig option | Value |
|----------|---------|---------------------|-------|
| IDE0063 | `using` statement → `using` declaration | `csharp_prefer_simple_using_statement` | `true` |
| IDE0066 | Switch statement → switch expression | `csharp_style_prefer_switch_expression` | `true` |
| IDE0054 | Use compound assignment (`+=`, etc.) | `dotnet_style_prefer_compound_assignment` | `true` |
| IDE0074 | Use coalescing compound assignment (`??=`) | `dotnet_style_prefer_compound_assignment` | `true` |
| IDE0056 | Use index operator (`^1`) | `csharp_style_prefer_index_operator` | `true` |
| IDE0057 | Use range operator (`..`) | `csharp_style_prefer_range_operator` | `true` |
| IDE0044 | Add `readonly` modifier to fields | `dotnet_style_readonly_field` | `true` |
| IDE0041 | Use `is null` check | `dotnet_style_prefer_is_null_check_over_reference_equality_method` | `true` |
| IDE0031 | Use null propagation (`?.`) | `dotnet_style_null_propagation` | `true` |
| IDE0062 | Make local function static | `csharp_prefer_static_local_function` | `true` |

### C# 9.0 rules

| IDE Rule | Feature | .editorconfig option | Value |
|----------|---------|---------------------|-------|
| IDE0083 | Use `not` pattern (`is not null`) | `csharp_style_prefer_not_pattern` | `true` |
| IDE0078 | Use pattern matching | `csharp_style_prefer_pattern_matching` | `true` |
| IDE0090 | Simplify `new` → target-typed `new` | `csharp_style_implicit_object_creation_when_type_is_apparent` | `true` |
| IDE0210 | Convert to top-level statements | `csharp_style_prefer_top_level_statements` | `true` |

### C# 10.0 rules

| IDE Rule | Feature | .editorconfig option | Value |
|----------|---------|---------------------|-------|
| IDE0161 | File-scoped namespace | `csharp_style_namespace_declarations` | `file_scoped` |
| IDE0170 | Simplify property pattern (extended) | `csharp_style_prefer_extended_property_pattern` | `true` |

### C# 11.0 rules

| IDE Rule | Feature | .editorconfig option | Value |
|----------|---------|---------------------|-------|
| IDE0230 | Use UTF-8 string literal (`u8`) | `csharp_style_prefer_utf8_string_literals` | `true` |
| IDE0250 | Struct can be made `readonly` | `csharp_style_prefer_readonly_struct` | `true` |
| IDE0251 | Member can be made `readonly` | `csharp_style_prefer_readonly_struct_member` | `true` |

### C# 12.0 rules

| IDE Rule | Feature | .editorconfig option | Value |
|----------|---------|---------------------|-------|
| IDE0300 | Collection expression for array | `dotnet_style_prefer_collection_expression` | `true` |
| IDE0301 | Collection expression for empty | `dotnet_style_prefer_collection_expression` | `true` |
| IDE0302 | Collection expression for stackalloc | `dotnet_style_prefer_collection_expression` | `true` |
| IDE0303 | Collection expression for `Create()` | `dotnet_style_prefer_collection_expression` | `true` |
| IDE0304 | Collection expression for builder | `dotnet_style_prefer_collection_expression` | `true` |
| IDE0305 | Collection expression for fluent | `dotnet_style_prefer_collection_expression` | `true` |
| IDE0306 | Collection expression for `new` | `dotnet_style_prefer_collection_expression` | `true` |
| IDE0290 | Use primary constructor | `csharp_style_prefer_primary_constructors` | `true` |

### C# 13.0 rules

| IDE Rule | Feature | .editorconfig option | Value |
|----------|---------|---------------------|-------|
| IDE0330 | Prefer `System.Threading.Lock` | `csharp_style_prefer_system_threading_lock` | `true` |
| IDE0320 | Make anonymous function static | `csharp_style_prefer_static_anonymous_function` | `true` |

### C# 14.0 rules

| IDE Rule | Feature | .editorconfig option | Value |
|----------|---------|---------------------|-------|
| IDE0340 | Use unbound generic type in `nameof` | `csharp_style_prefer_unbound_generic_type_in_nameof` | `true` |
| IDE0350 | Use implicitly typed lambda | `csharp_style_prefer_implicit_lambda` | `true` |
| IDE0360 | Simplify property accessor (`field` keyword) | `csharp_style_prefer_simplified_property_accessor` | `true` |

### C# 15.0 rules

No new IDE analyzer rules with auto-fixers have been added for C# 15 features at this time.
Collection expression arguments (`with(...)`) require LLM judgment to apply.

## Features WITHOUT dotnet format fixers (LLM-only)

These features have no IDE analyzer rule or no auto-fixer. The LLM must handle them:

| C# Version | Feature | Why no fixer |
|-------------|---------|-------------|
| 7.0 | Tuple return types (replacing result classes) | Semantic — requires understanding intent |
| 7.0 | Local function extraction | IDE0039 exists but fixer is limited |
| 8.0 | Nullable reference types (NRT) | Project-wide, requires annotation strategy |
| 8.0 | Async streams conversion | API change — breaks callers |
| 8.0 | Default interface members | Architectural decision |
| 9.0 | `record` type conversion | Semantic — must judge if class is data-only |
| 9.0 | `init`-only setter conversion | Semantic — must judge mutability intent |
| 9.0 | Covariant return types | Requires inheritance analysis |
| 10.0 | Global using directives | Cross-file analysis needed |
| 10.0 | Record struct conversion | Semantic — must judge value-type suitability |
| 10.0 | `CallerArgumentExpression` adoption | API design choice |
| 11.0 | Raw string literal conversion | No fixer — pattern detection works but rewrite is complex |
| 11.0 | `required` members | Contract change — must verify framework support |
| 11.0 | List patterns | No auto-fixer for converting `if`/`Length` chains |
| 11.0 | Generic math / static abstract interfaces | Architectural — reshapes type hierarchy |
| 12.0 | Alias any type | Style choice — no automatic detection of "complex enough" |
| 13.0 | `params` Span migration | API change — may break callers |
| 13.0 | Partial properties | Only useful with source generators |
| 14.0 | Extension blocks (new syntax) | Major rewrite — no fixer exists yet |
| 14.0 | Null-conditional assignment | No fixer yet (new in C# 14) |
| 14.0 | `field` keyword (complex cases) | IDE0360 covers simple cases only |
| 15.0 | Collection expression arguments (`with(...)`) | No fixer — requires understanding constructor intent |

## Generating an .editorconfig snippet

Build the snippet by including only rules for versions in the upgrade range. Example for
upgrading from C# 8 → C# 12:

```ini
# Auto-generated for C# modernization: C# 8 → C# 12
# Apply with: dotnet format --severity info

[*.cs]
# C# 9 features
csharp_style_prefer_not_pattern = true:info
csharp_style_prefer_pattern_matching = true:info
csharp_style_implicit_object_creation_when_type_is_apparent = true:info

# C# 10 features
csharp_style_namespace_declarations = file_scoped:info
csharp_style_prefer_extended_property_pattern = true:info

# C# 11 features
csharp_style_prefer_utf8_string_literals = true:info

# C# 12 features
dotnet_style_prefer_collection_expression = true:info
```

Note: Rules from the source version and below are excluded — the code already uses that version's
features (or the user has consciously opted out of them).
