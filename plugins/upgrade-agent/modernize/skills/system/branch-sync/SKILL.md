---
name: branch-sync
description: >
  On-demand sync of the upgrade working branch with its source branch (typically main) using merge
  or rebase. Detects divergence, resolves conflicts using upgrade context (prefer upgraded code in
  files we changed, prefer source elsewhere), validates with a build, and rolls back on any failure.
  Trigger phrases: "sync", "sync with main", "merge from main", "pull from main", "rebase on main",
  "branch sync", "catch up with source".
metadata:
  discovery: system
---

# Branch Sync Guide

Keeps the upgrade working branch close to its source branch so merge-back at the end of a long
upgrade is incremental rather than catastrophic. The skill is invoked two ways:

- **On demand** \u2014 when the user says "sync with main", "merge from main", "rebase on main", etc.
- **Automatically between tasks** \u2014 by the `task-execution` skill (\u00a76.5) when the persisted
  `Branch Sync` strategy in `scenario-instructions.md` is `Auto (Merge)` or `Auto (Rebase)`.

Both paths run the same lifecycle below.

## Safety invariants (read before any git command)

- **No push, ever.** This skill never executes `git push` in any form (`push`, `push --force`, `push --force-with-lease`). Pushing the working branch — especially after a rebase, which rewrites history — is the user's decision and tooling. If a future change appears to require pushing, **stop and surface the situation to the user** instead.
- **Source-branch refs are read-only.** The skill only updates the working branch's HEAD. It must never run `git branch -f`, `git update-ref refs/heads/{source}`, `git reset` while checked out on the source branch, or any other operation that writes to the source ref (`master` / `main`). `git fetch` is allowed (it writes only `refs/remotes/...`).
- **Pre-existing commits are never destroyed.** The only state a rollback can discard is the in-progress sync's own provisional work (the merge commit and any one-shot fix commit produced **after** `pre_sync_commit` was captured). Anything that existed before the sync started is preserved.

> **9 sections — read all before running a sync.**
>
> | # | Section | Key content |
> |---|---------|-------------|
> | 1 | When to invoke | Trigger phrases, agent-initiated cases, when to refuse |
> | 2 | Pre-flight guards | Dirty tree, same-branch, no remote |
> | 3 | Strategy selection | Merge (default) vs Rebase, ask once per session |
> | 4 | Divergence detection | Fetch + commits-behind |
> | 5 | Sync execution | Capture rollback point, run merge/rebase |
> | 6 | Conflict resolution | Ours/theirs heuristic, abort criteria |
> | 7 | Build validation | What to build, what failure means |
> | 8 | Rollback | When and how |
> | 9 | User communication | Exact messages per outcome |

## 1. When to invoke

Invoke this skill when:

- The user says "sync", "merge from main", "pull from main", "rebase on main", "catch up with
  source", "branch sync", or any close paraphrase.
- The user asks how far the working branch has drifted (run §4 and report; do not sync without
  confirmation).

Do **not** invoke this skill:

- During scenario initialization or assessment — only meaningful once tasks have produced commits.
- On the very last task of a scenario — the user will do the final merge/PR.
- When a sync at the same task boundary already failed in this session — wait for the next user
  request.

## 2. Pre-flight guards

Run these checks first; abort with a single clear message if any fails. Do not attempt a fix
silently — surface the situation so the user can decide.

| Guard | Check | If fails |
|-------|-------|----------|
| Working tree clean | `git status --porcelain` returns empty | Tell the user there are uncommitted changes; ask whether to commit, stash, or cancel. |
| Source ≠ working | `Source Branch` from `scenario-instructions.md` differs from `git branch --show-current` | No-op; report "Already on the source branch — nothing to sync." |
| Inside a git repo | `git rev-parse --is-inside-work-tree` | Report "Not a git repository — sync not applicable." |
| Remote exists for source | `git ls-remote --exit-code origin {source_branch}` (or whatever remote tracks it) | If no remote, fall back to local source branch only and tell the user fetch was skipped. |

`Source Branch`, `Working Branch`, `Branch Sync` (strategy), and `Last Sync Commit` come from
the `## Source Control` block of `scenario-instructions.md`. They are written there during
scenario initialization and updated by this skill on every successful sync. If a field is
missing (older scenario file), fall back: missing strategy → ask once and remember in
conversation context; missing `Last Sync Commit` → use `git merge-base HEAD {source_branch}`.

## 3. Strategy selection

The strategy is normally read from `Branch Sync` in `scenario-instructions.md` — do **not**
re-prompt when it is already persisted. Only ask the user when the field is missing entirely
(legacy scenario files) or when the user explicitly says "sync with rebase" / "sync with merge"
and wants to override the persisted choice for this one invocation.

| Strategy persisted | Behavior |
|---|---|
| `Auto (Merge)` or `Manual` | Use Merge for this sync. |
| `Auto (Rebase)` | Use Rebase for this sync. |
| `Disabled` | Reaching this skill from auto-trigger should not happen. If reached via on-demand request, ask the user to confirm Merge or Rebase. |
| Not present | Ask the user once: Merge or Rebase. Remember in conversation context. Recommend persisting via the next initialization. |

If the user picks Rebase, surface this warning verbatim before proceeding:

> ⚠️ Rebase rewrites commit history. If this branch has been pushed to a remote or shared with
> others, choose Merge instead. Continue with rebase?

## 4. Divergence detection

> **Critical:** `git fetch {remote} {source_branch}` updates `refs/remotes/{remote}/{source_branch}`
> — it does **not** advance the local `{source_branch}` ref. Comparing against the local ref
> after a fetch will silently miss every commit pushed by other contributors. Always compare
> against the **remote-tracking ref** when a remote exists.

```bash
# 1. Refresh the source branch ref from the remote (skip if §2 said no remote).
git fetch {remote} {source_branch}

# 2. Pick the ref to compare against.
#    - Remote exists: use the remote-tracking ref (just-fetched, fresh).
#    - No remote (§2 fallback): use the local source branch.
compare_ref={remote}/{source_branch}    # or {source_branch} when no remote

# 3. Determine the comparison base.
#    Prefer `Last Sync Commit` from scenario-instructions.md; fall back to merge-base.
base=${last_sync_commit:-$(git merge-base HEAD ${compare_ref})}

# 4. Count incoming commits.
git log --oneline ${base}..${compare_ref}
```

Empty output → no divergence → tell the user "Already up to date with `{source_branch}`." and stop.
Otherwise, report the count and the short list (first 10) before running §5.

## 5. Sync execution

**Always capture the rollback point first** — every other step depends on it being recorded.

```bash
pre_sync_commit=$(git rev-parse HEAD)
```

Then run the chosen strategy against the **same `${compare_ref}` from §4** (the remote-tracking
ref when a remote exists, else the local source branch). Merging or rebasing onto the local
source ref would re-introduce the stale-ref bug from §4.

- Merge: `git merge ${compare_ref} --no-edit`
- Rebase: `git rebase ${compare_ref}`

If the command exits 0 with no conflicts → skip §6, go to §7.
If the command reports conflicts → §6.
If the command fails for any other reason (network, corrupt index, etc.) → §8 rollback, report.

## 6. Conflict resolution

> **Do NOT prompt the user for per-file resolution.** No "keep ours / take theirs / abort"
> prompts, no "which version do you want?" questions. Apply the rules below mechanically. The
> only escape hatch is §8 rollback — and that is taken without asking. The user will see one
> summary message at the end (§9), not a dialog per file.

Identify the set of files this upgrade has touched (the "ours" set):

```bash
git diff --name-only ${base}...HEAD   # files changed on the working branch since divergence
```

Then for each conflicted file from `git diff --name-only --diff-filter=U`, apply exactly one rule:

| File status | Action | Why |
|-------------|--------|-----|
| In the ours set | `git checkout --ours -- {file}` then `git add {file}` | We intentionally upgraded this file; source has the old-framework version. The upgrade always wins. |
| **Not** in the ours set | `git checkout --theirs -- {file}` then `git add {file}` | We have not touched this file yet; source's version is more current. A future upgrade task will handle it. |

**That is the entire rule set. Two rows. No third option.** Every conflicted file is in exactly
one of those two states — file is either in the ours set or it is not. There is no "ambiguous"
bucket and no "ask the user" bucket in Phase 1.

If `git checkout --ours/--theirs` itself fails for any reason (file missing on one side, git
error, etc.) → §8 rollback. Do not improvise.

After all conflicted files are resolved and staged, run `git diff --name-only --diff-filter=U`
again to confirm zero remaining conflicts before proceeding.

Run **one pass per file**. Do not loop or retry — if any file is unresolvable after one pass, abort.

After all files are resolved and staged:

- Merge path: `git commit --no-edit` (the merge commit message is fine).
- Rebase path: `git rebase --continue`. Rebase may surface conflicts again on the next replayed
  commit — repeat §6 for each round. If any round is unresolvable, `git rebase --abort` and §8.

## 7. Build validation

After §5/§6 produce a clean working tree, validate before declaring success.

1. Get the solution path via the `get_solution_path` tool.
2. Run `dotnet build {solution_path}`.
3. **Pass** → **persist** the new `Last Sync Commit` (the source-branch HEAD that was merged/rebased) into the `## Source Control` block of `scenario-instructions.md`, then send the §9 success message.
4. **Fail** → the source branch likely introduced code that needs the same upgrade pattern. Make
   one focused attempt to fix the build errors (e.g., update a TFM reference, adapt to a renamed
   API). If that single attempt succeeds, commit the fix on top with message
   `sync: fix build after merging {source_branch}` and report success (also update `Last Sync Commit`). If the attempt fails or
   would require open-ended work, go to §8.

Do not iterate fixes. One attempt, then rollback.

## 8. Rollback

```bash
git reset --hard ${pre_sync_commit}
```

For an in-progress rebase that has not been continued past the failure, run `git rebase --abort`
**before** the reset (the abort restores HEAD to the pre-rebase commit, making the reset a no-op
verification).

After rollback, send the appropriate §9 failure message and stop. Do not auto-retry.

**Recovery note.** Any commit this rollback discards remains reachable via `git reflog` for ~90 days (default git retention). If a user reports lost work after a rollback, walk them through `git reflog` to find the SHA, then `git reset --hard {sha}` to restore it. In practice this should never be needed because the only commits a rollback can discard are the merge commit and one-shot fix commit produced by this skill itself — but the safety net exists.

## 9. User communication

Use these messages verbatim (substitute `{...}` placeholders). Pick the one that matches the
outcome.

| Outcome | Message |
|---------|---------|
| Starting | 🔄 Syncing with `{source_branch}` ({N} new commits since {base_short_sha})... |
| Already up to date | ✅ Already up to date with `{source_branch}` — nothing to sync. |
| Clean sync, build passed | ✅ Synced with `{source_branch}` (merged {N} commits). Build verified. |
| Conflicts auto-resolved, build passed | ⚠️ Synced with `{source_branch}`. Resolved conflicts in {K} files (kept upgrade changes in upgraded files, accepted source changes in untouched files). Build verified. |
| Conflicts auto-resolved, build fixed | ⚠️ Synced with `{source_branch}`. Resolved {K} conflicts and fixed {M} build errors introduced by source. |
| Aborted — unresolvable conflicts | ❌ Could not sync — conflicts in `{files}` couldn't be auto-resolved. Rolled back to {pre_sync_short_sha}. The branch is unchanged; you can resolve manually or ask me again later. |
| Aborted — build failed | ❌ Sync merged cleanly but caused build failures I couldn't fix in one attempt. Rolled back to {pre_sync_short_sha}. |
| Aborted — pre-flight | ❌ Can't sync right now: {reason from §2}. |
| Rebase warning | ⚠️ Rebase rewrites commit history. If this branch has been pushed to a remote or shared with others, choose Merge instead. Continue with rebase? |
| Manual mode — diverged | ℹ️ `{source_branch}` has {N} new commits since last sync. Reply "sync" when you'd like to merge them in. |
| Manual mode — no divergence | *(silent)* |
| Disabled | *(silent — should not reach this skill from auto-trigger)* |

## Notes

- This skill is invoked both **on demand** (user says "sync with main") and **automatically**
  between tasks by the `task-execution` skill (§6.5) when `Branch Sync` is `Auto (Merge)` or
  `Auto (Rebase)`.
- All git operations shell out via the standard process runner. A future change may add
  `MergeAsync` / `RebaseAsync` / `FetchAsync` to `IGit` and route through there — the skill
  contract stays the same.
