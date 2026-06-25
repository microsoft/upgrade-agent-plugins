// Copyright (c) Microsoft Corporation. All rights reserved.

// Repo / git-dir / activity-log path resolution.
// `resolveGitDir` follows the worktree `.git`-file pointer (used for the
// diagnostics tab and the reported git "kind"). Activity-log resolution,
// however, deliberately mirrors the .NET writer (ActivityLogDiscovery): the
// log lives under `.git/upgrade` only when `.git` is a real directory; in a
// worktree `.git` is a *file*, so the runtime writes to `.vs/upgrade` instead.
// Matching the writer keeps reader and writer pointed at the same file.

import { statSync, readFileSync, readdirSync } from "node:fs";
import path from "node:path";

export function resolveGitDir(repoRoot) {
	const candidate = path.join(repoRoot, ".git");
	let stat;
	try {
		stat = statSync(candidate);
	} catch {
		return { gitDir: null, kind: "missing" };
	}
	if (stat.isDirectory()) {
		return { gitDir: candidate, kind: "directory" };
	}
	if (stat.isFile()) {
		try {
			const body = readFileSync(candidate, "utf8");
			const match = /^gitdir:\s*(.+?)\s*$/m.exec(body);
			if (match) {
				const target = path.isAbsolute(match[1])
					? match[1]
					: path.resolve(repoRoot, match[1]);
				return { gitDir: target, kind: "worktree" };
			}
		} catch {
			// fall through
		}
		return { gitDir: null, kind: "worktree-unresolved" };
	}
	return { gitDir: null, kind: "unknown" };
}

export function activityLogDir(repoRoot) {
	const dotGit = path.join(repoRoot, ".git");
	let isDir = false;
	try {
		isDir = statSync(dotGit).isDirectory();
	} catch {
		isDir = false;
	}
	return isDir ? path.join(dotGit, "upgrade") : path.join(repoRoot, ".vs", "upgrade");
}

export function resolveActivityLog(repoRoot) {
	return path.join(activityLogDir(repoRoot), "activity.jsonl");
}

// Rotated archives (activity-*.jsonl) in the same directory, newest-first —
// mirrors ActivityLogDiscovery.DiscoverArchives so history survives rotation.
export function resolveActivityArchives(repoRoot) {
	const dir = activityLogDir(repoRoot);
	let names;
	try {
		names = readdirSync(dir);
	} catch {
		return [];
	}
	return names
		.filter((name) => /^activity-.*\.jsonl$/i.test(name))
		.sort((a, b) => b.localeCompare(a))
		.map((name) => path.join(dir, name));
}
