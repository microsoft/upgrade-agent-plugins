// Copyright (c) Microsoft Corporation. All rights reserved.

// Provider host lifecycle management. Spawns the Dashboard ServiceHost
// process to watch for file/git/build changes and write activity.jsonl.
// Started when the canvas opens, stopped when it closes.

import { spawn } from "node:child_process";
import { existsSync, readdirSync } from "node:fs";
import { homedir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { activityLogDir } from "./repo.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const SERVICE_HOST_NAME = "Microsoft.Upgrade.Dashboard.ServiceHost";
const CORE_PROVIDERS_DLL = "Microsoft.Upgrade.Dashboard.Core.dll";

// Search for the ServiceHost binary and core providers DLL.
//
// Search order:
// 1. DASHBOARD_SERVICE_HOST_DIR env var (set by install-local.ps1 for dev testing)
// 2. NuGet global packages cache: the MCP nupkg is installed by the Copilot app
//    via `dnx` into ~/.nuget/packages/<packageId>/<version>/tools/<tfm>/any/Dashboard/

// NuGet package ID that contains the Dashboard binaries.
const NUPKG_ID = "microsoft.githubcopilot.upgrade.mcp";

function findDashboardDir() {
	const isWindows = process.platform === "win32";

	// Candidate directories, searched in order.
	const candidates = [];

	// 1. Dev override via env var.
	if (process.env.DASHBOARD_SERVICE_HOST_DIR) {
		candidates.push(process.env.DASHBOARD_SERVICE_HOST_DIR);
	}

	// 2. NuGet global packages cache — pick the newest installed version.
	for (const dir of findDashboardDirsInNuGetCache()) {
		candidates.push(dir);
	}

	for (const dir of candidates) {
		const exeName = SERVICE_HOST_NAME + (isWindows ? ".exe" : "");
		if (existsSync(path.join(dir, exeName))) {
			return { dir, exe: path.join(dir, exeName), useDotnet: false };
		}
		const dllName = SERVICE_HOST_NAME + ".dll";
		if (existsSync(path.join(dir, dllName))) {
			return { dir, exe: path.join(dir, dllName), useDotnet: true };
		}
	}

	return null;
}

/**
 * Search the NuGet global packages cache for Dashboard directories inside
 * known MCP nupkg IDs. Returns paths sorted newest-version-first.
 */
function findDashboardDirsInNuGetCache() {
	const nugetRoot = process.env.NUGET_PACKAGES || path.join(homedir(), ".nuget", "packages");
	const results = [];

	const pkgDir = path.join(nugetRoot, NUPKG_ID);
	if (!existsSync(pkgDir)) {
		return results;
	}

	let versions;
	try {
		versions = readdirSync(pkgDir, { withFileTypes: true })
			.filter((d) => d.isDirectory() && d.name !== ".stage")
			.map((d) => d.name);
	} catch {
		return results;
	}

	// Sort versions descending so the newest is tried first.
	// NuGet versions are SemVer — lexicographic sort fails on multi-digit
	// components (e.g. "1.0.10" vs "1.0.2"), so we compare numerically.
	versions.sort((a, b) => compareSemVerDesc(a, b));

	for (const ver of versions) {
		const toolsDir = path.join(pkgDir, ver, "tools");
		if (!existsSync(toolsDir)) {
			continue;
		}

		let tfms;
		try {
			tfms = readdirSync(toolsDir, { withFileTypes: true })
				.filter((d) => d.isDirectory())
				.map((d) => d.name);
		} catch {
			continue;
		}

		for (const tfm of tfms) {
			const dashDir = path.join(toolsDir, tfm, "any", "Dashboard");
			if (existsSync(dashDir)) {
				results.push(dashDir);
			}
		}
	}

	return results;
}

/**
 * Compare two SemVer-ish version strings in descending order.
 * Splits on "." and compares each segment numerically. Prerelease
 * suffixes (after "-") are compared segment-by-segment as well,
 * with numeric segments compared numerically and string segments
 * compared lexicographically. A version with no prerelease suffix
 * is considered newer than one with a suffix (per SemVer rules).
 */
function compareSemVerDesc(a, b) {
	const [coreA, preA] = a.split("-", 2);
	const [coreB, preB] = b.split("-", 2);

	const partsA = coreA.split(".").map(Number);
	const partsB = coreB.split(".").map(Number);

	for (let i = 0; i < Math.max(partsA.length, partsB.length); i++) {
		const n1 = partsA[i] || 0;
		const n2 = partsB[i] || 0;
		if (n1 !== n2) {
			return n2 - n1; // descending
		}
	}

	// Same core version — compare prerelease. No prerelease > has prerelease.
	if (!preA && preB) return -1; // a is newer (no prerelease)
	if (preA && !preB) return 1;  // b is newer
	if (!preA && !preB) return 0;

	// Both have prerelease — compare dot-separated segments.
	const segsA = preA.split(".");
	const segsB = preB.split(".");
	for (let i = 0; i < Math.max(segsA.length, segsB.length); i++) {
		const sa = segsA[i];
		const sb = segsB[i];
		if (sa === undefined) return 1;  // b has more segments → b is newer
		if (sb === undefined) return -1; // a has more segments → a is newer
		const na = Number(sa);
		const nb = Number(sb);
		if (!isNaN(na) && !isNaN(nb)) {
			if (na !== nb) return nb - na; // descending numeric
		} else {
			const cmp = sa.localeCompare(sb);
			if (cmp !== 0) return -cmp; // descending lexicographic
		}
	}

	return 0;
}

function findCoreProvidersDll(dashboardDir) {
	// The core providers DLL is typically in the same directory as the ServiceHost
	if (existsSync(path.join(dashboardDir, CORE_PROVIDERS_DLL))) {
		return path.join(dashboardDir, CORE_PROVIDERS_DLL);
	}

	return null;
}

/**
 * Start the Dashboard ServiceHost process to produce activity.jsonl.
 *
 * @param {string} repoRoot - Absolute path to the repository root.
 * @param {object} [options]
 * @param {string} [options.scenarioPath] - Optional scenario folder path.
 * @param {string} [options.upgradesRoot] - Optional upgrades artifact root.
 * @returns {{ process, journalPath, kill } | null} Handle, or null if binaries not found.
 */
export function startProviderHost(repoRoot, options = {}) {
	const dashboard = findDashboardDir();
	if (!dashboard) {
		console.error("[providers] ServiceHost binary not found — activity.jsonl will not be produced.");
		return null;
	}

	const providersDll = findCoreProvidersDll(dashboard.dir);
	if (!providersDll) {
		console.error("[providers] Core providers DLL not found — activity.jsonl will not be produced.");
		return null;
	}

	const journalDir = activityLogDir(repoRoot);
	const journalPath = path.join(journalDir, "activity.jsonl");
	const mutexName = `Global\\Dashboard_Journal_Canvas_${hashCode(repoRoot)}`;

	const args = [
		"--dll", providersDll,
		"--journal", journalPath,
		"--mutex", mutexName,
		"--repo", repoRoot,
		"--parent-pid", String(process.pid),
	];

	if (options.scenarioPath) {
		args.push("--scenario", options.scenarioPath);
	}
	if (options.upgradesRoot) {
		args.push("--upgrades-root", options.upgradesRoot);
	}

	let child;
	if (dashboard.useDotnet) {
		child = spawn("dotnet", [dashboard.exe, ...args], {
			stdio: "ignore",
			detached: false,
		});
	} else {
		child = spawn(dashboard.exe, args, {
			stdio: "ignore",
			detached: false,
		});
	}

	child.on("error", (err) => {
		console.error(`[providers] ServiceHost spawn error: ${err.message}`);
	});

	child.on("exit", (code) => {
		if (code !== 0 && code !== null) {
			console.error(`[providers] ServiceHost exited with code ${code}`);
		}
	});

	console.error(`[providers] Started ServiceHost (PID ${child.pid}) from ${dashboard.dir}`);
	console.error(`[providers] Journal → ${journalPath}`);

	return {
		process: child,
		journalPath,
		kill() {
			try {
				if (child && !child.killed) {
					child.kill();
				}
			} catch {
				// ignore — process may have already exited
			}
		},
	};
}

/**
 * Stop a previously started provider host.
 * @param {object|null} handle - The handle returned by startProviderHost.
 */
export function stopProviderHost(handle) {
	if (!handle) return;
	try {
		if (typeof handle.kill === "function") {
			handle.kill();
		}
	} catch {
		// ignore — process may have already exited or handle is unexpected shape
	}
	console.error("[providers] Stopped ServiceHost.");
}

// Simple string hash matching the C# GetHashCode(StringComparison.OrdinalIgnoreCase)
// pattern used by the dashboard for mutex naming. Not cryptographic — just avoids
// collisions for different repo paths.
function hashCode(str) {
	let hash = 0;
	const upper = str.toUpperCase();
	for (let i = 0; i < upper.length; i++) {
		hash = ((hash << 5) - hash + upper.charCodeAt(i)) | 0;
	}
	return (hash >>> 0).toString(16).padStart(8, "0");
}
