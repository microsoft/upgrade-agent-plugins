// Copyright (c) Microsoft Corporation. All rights reserved.

// Artifact discovery and snapshot construction. This module is the single
// source of truth for "what's the dashboard state right now?" — used by both
// the canvas extension (extension.mjs) and the standalone CLI (bin/cli.mjs).
// All file I/O lives here so the consumers can stay thin.

import { promises as fs } from "node:fs";
import { existsSync, statSync } from "node:fs";
import path from "node:path";

import { resolveGitDir, resolveActivityLog, resolveActivityArchives } from "./repo.mjs";
import { formatActivityEntry } from "./activity.mjs";
import { parseTasksMd } from "./tasks.mjs";
import { readTargetFrameworks, readProjectKind, isSdkStyle, readProjectReferences, SKIP_DIRS } from "./projects.mjs";
import { pick, countIncompatible } from "./deps.mjs";
import { aggregateFeatures } from "./assessment.mjs";

const SCENARIOS_REL = path.join(".github", "upgrades", "scenarios");

// --- Activity ----------------------------------------------------------------

async function readActivityTail(repoRoot, activeScenario, maxLines = 200) {
	const sources = [];
	const activityFile = resolveActivityLog(repoRoot);
	if (existsSync(activityFile)) sources.push({ file: activityFile, kind: "activity" });
	for (const archive of resolveActivityArchives(repoRoot)) {
		sources.push({ file: archive, kind: "activity" });
	}
	if (activeScenario?.scenarioPath) {
		const changelog = path.join(activeScenario.scenarioPath, "changelog.jsonl");
		if (existsSync(changelog)) sources.push({ file: changelog, kind: "changelog" });
	}

	const entries = [];
	for (const source of sources) {
		try {
			const raw = await fs.readFile(source.file, "utf8");
			const lines = raw.split(/\r?\n/).filter(Boolean);
			for (const line of lines) {
				let entry;
				try {
					entry = formatActivityEntry(JSON.parse(line));
				} catch {
					entry = { event: "unparseable", label: "unparseable", kind: "other", detail: line };
				}
				entry.source = source.kind;
				entries.push(entry);
			}
		} catch {
			// ignore unreadable files
		}
	}

	entries.sort((a, b) => {
		const ta = a.timestamp ? Date.parse(a.timestamp) : NaN;
		const tb = b.timestamp ? Date.parse(b.timestamp) : NaN;
		if (!Number.isNaN(ta) && !Number.isNaN(tb)) return tb - ta;
		if (!Number.isNaN(ta)) return -1;
		if (!Number.isNaN(tb)) return 1;
		return 0;
	});
	return entries.slice(0, maxLines);
}

// --- Scenarios ----------------------------------------------------------------

const SCENARIO_ARTIFACT_FILES = ["scenario.json", "assessment.json", "changelog.jsonl", "plan.json", "plan.md"];

export async function readScenarios(repoRoot) {
	const dir = path.join(repoRoot, SCENARIOS_REL);
	let entries;
	try {
		entries = await fs.readdir(dir, { withFileTypes: true });
	} catch {
		return [];
	}
	const scenarios = [];
	for (const entry of entries) {
		if (!entry.isDirectory()) continue;
		const scenarioPath = path.join(dir, entry.name);
		let hasArtifacts = false;
		for (const file of SCENARIO_ARTIFACT_FILES) {
			if (existsSync(path.join(scenarioPath, file))) {
				hasArtifacts = true;
				break;
			}
		}
		if (!hasArtifacts) continue;
		// Tiebreak on the scenario directory's mtime to match the .NET
		// ScenarioDiscovery (Directory.GetLastWriteTimeUtc) so both readers
		// select the same active scenario.
		let mtime = 0;
		try {
			mtime = (await fs.stat(scenarioPath)).mtimeMs;
		} catch {
			// leave mtime at 0
		}
		let body = {};
		try {
			body = JSON.parse(await fs.readFile(path.join(scenarioPath, "scenario.json"), "utf8"));
		} catch {
			body = { error: "could not read scenario.json" };
		}
		scenarios.push({ id: entry.name, scenarioPath, mtime, ...body });
	}
	scenarios.sort((a, b) => (b.mtime ?? 0) - (a.mtime ?? 0));
	return scenarios;
}

export function getActiveScenario(scenarios) {
	return scenarios.length > 0 ? scenarios[0] : null;
}

// --- Projects ----------------------------------------------------------------

async function readProjects(repoRoot) {
	const projects = [];
	const MAX_PROJECTS = 500;
	async function walk(dir) {
		if (projects.length >= MAX_PROJECTS) return;
		let entries;
		try {
			entries = await fs.readdir(dir, { withFileTypes: true });
		} catch {
			return;
		}
		for (const entry of entries) {
			if (projects.length >= MAX_PROJECTS) return;
			if (SKIP_DIRS.has(entry.name)) continue;
			const full = path.join(dir, entry.name);
			if (entry.isDirectory()) {
				await walk(full);
				continue;
			}
			if (!/\.(cs|fs)proj$/i.test(entry.name)) continue;
			const relativePath = path.relative(repoRoot, full);
			let xml = "";
			try {
				xml = await fs.readFile(full, "utf8");
			} catch {
				// ignore
			}
			projects.push({
				name: path.basename(entry.name, path.extname(entry.name)),
				projectPath: relativePath,
				directoryPath: path.dirname(relativePath),
				targetFrameworks: readTargetFrameworks(xml),
				kind: readProjectKind(xml),
				isSdk: isSdkStyle(xml),
				projectReferences: readProjectReferences(xml),
			});
		}
	}
	await walk(repoRoot);
	projects.sort((a, b) => a.projectPath.localeCompare(b.projectPath));
	return projects;
}

// --- Assessment --------------------------------------------------------------

async function findAssessmentJson(repoRoot, activeScenario) {
	const candidates = [];
	if (activeScenario?.scenarioPath) {
		candidates.push(path.join(activeScenario.scenarioPath, "assessment.json"));
		candidates.push(path.join(activeScenario.scenarioPath, "assessment", "assessment.json"));
	}
	candidates.push(path.join(repoRoot, ".vs", "upgrade", "assessment", "assessment.json"));
	for (const candidate of candidates) {
		if (existsSync(candidate)) return candidate;
	}
	return null;
}

async function readAssessment(repoRoot, activeScenario) {
	const file = await findAssessmentJson(repoRoot, activeScenario);
	if (!file) return null;
	try {
		const data = JSON.parse(await fs.readFile(file, "utf8"));
		const stats = data.stats ?? {};
		const summary = stats.summary ?? {};
		const charts = stats.charts ?? {};
		const projects = Array.isArray(data.projects) ? data.projects : [];
		const features = aggregateFeatures(projects);
		return {
			path: file,
			settings: data.settings ?? null,
			analysisStartTime: data.analysisStartTime ?? null,
			analysisEndTime: data.analysisEndTime ?? null,
			counts: {
				projects: summary.projects ?? projects.length,
				issues: summary.issues ?? 0,
				incidents: summary.incidents ?? 0,
				effort: summary.effort ?? 0,
				mandatory: charts.severity?.Mandatory ?? 0,
			},
			severity: charts.severity ?? {},
			category: charts.category ?? {},
			features,
			projects: projects
				.filter((p) => p && typeof p === "object")
				.map((p) => ({
					path: p.path,
					startingProject: !!p.startingProject,
					issues: p.issues ?? 0,
					storyPoints: p.storyPoints ?? 0,
					appName: p.properties?.appName ?? null,
					frameworks: p.properties?.frameworks ?? [],
					projectKind: p.properties?.projectKind ?? null,
					isSdk: !!p.properties?.isSdkStyle,
					ruleInstances: Array.isArray(p.ruleInstances)
						? p.ruleInstances.filter((ri) => ri && typeof ri === "object")
						: [],
				})),
			rules: (data.rules && typeof data.rules === "object") ? data.rules : {},
			markdown: await readAssessmentMarkdown(activeScenario),
		};
	} catch {
		return null;
	}
}

// Looks for assessment.md alongside assessment.json (most teams keep both).
// Returns { path, content } when found, else null. The markdown is what the
// agent surfaces in chat; users expect it to be the primary "what does the
// assessment say?" surface.
async function readAssessmentMarkdown(activeScenario) {
	if (!activeScenario?.scenarioPath) return null;
	const candidates = [
		path.join(activeScenario.scenarioPath, "assessment.md"),
		path.join(activeScenario.scenarioPath, "assessment", "assessment.md"),
	];
	for (const candidate of candidates) {
		if (existsSync(candidate)) {
			try {
				const content = await fs.readFile(candidate, "utf8");
				return { path: candidate, content };
			} catch {
				return null;
			}
		}
	}
	return null;
}

// --- Dependencies health -----------------------------------------------------

async function findDependencyHealthJson(repoRoot, activeScenario) {
	const candidates = [];
	if (activeScenario?.scenarioPath) {
		candidates.push(path.join(activeScenario.scenarioPath, "dependencies-health.json"));
		candidates.push(path.join(activeScenario.scenarioPath, "assessment", "dependencies-health.json"));
	}
	candidates.push(path.join(repoRoot, ".vs", "upgrade", "assessment", "dependencies-health.json"));
	for (const candidate of candidates) {
		if (existsSync(candidate)) return candidate;
	}
	return null;
}

async function readDependencyHealth(repoRoot, activeScenario) {
	const file = await findDependencyHealthJson(repoRoot, activeScenario);
	if (!file) return null;
	try {
		const data = JSON.parse(await fs.readFile(file, "utf8"));
		const gov = pick(data, "packageGovernance", "PackageGovernance") ?? {};
		const packages = Array.isArray(pick(gov, "packages", "Packages")) ? pick(gov, "packages", "Packages") : [];
		const projects = Array.isArray(pick(data, "projects", "Projects")) ? pick(data, "projects", "Projects") : [];
		return {
			path: file,
			targetFramework: pick(gov, "targetFramework", "TargetFramework") ?? null,
			counts: {
				distinctPackages: pick(gov, "totalDistinctPackages", "TotalDistinctPackages") ?? packages.length,
				versionDrift: pick(gov, "totalVersionDriftInstances", "TotalVersionDriftInstances") ?? 0,
				projects: projects.length,
			},
			packages: packages.map((p) => ({
				name: pick(p, "name", "Name") ?? "",
				totalProjectCount: pick(p, "totalProjectCount", "TotalProjectCount") ?? 0,
				distinctVersionCount: pick(p, "distinctVersionCount", "DistinctVersionCount") ?? 0,
				recommendedVersion: pick(p, "recommendedVersion", "RecommendedVersion") ?? null,
				isCompatible: pick(p, "isCompatible", "IsCompatible") ?? null,
				versions: (pick(p, "versions", "Versions") ?? []).map((v) => ({
					version: pick(v, "version", "Version") ?? "",
					projectCount: (pick(v, "projects", "Projects") ?? []).length,
					isRecommended: !!pick(v, "isRecommended", "IsRecommended"),
				})),
				upgrade: pick(p, "upgrade", "Upgrade") ?? null,
			})),
			projects: projects.map((proj) => {
				const deps = pick(proj, "dependencies", "Dependencies");
				const imports = pick(proj, "imports", "Imports");
				return {
					name: pick(proj, "name", "Name") ?? "",
					path: pick(proj, "path", "Path") ?? "",
					isSdk: !!pick(proj, "isSdk", "IsSdk"),
					currentFrameworks: pick(proj, "currentFrameworks", "CurrentFrameworks") ?? [],
					targetFramework: pick(proj, "targetFramework", "TargetFramework") ?? null,
					packageCount: (pick(deps, "packages", "Packages") ?? []).length,
					assemblyCount: (pick(deps, "assemblies", "Assemblies") ?? []).length,
					projectRefCount: (pick(deps, "projectReferences", "ProjectReferences") ?? []).length,
					frameworkRefCount: (pick(deps, "frameworkReferences", "FrameworkReferences") ?? []).length,
					importsCount: Array.isArray(imports) ? imports.length : 0,
					incompatible: countIncompatible(deps),
					dependencies: deps ?? null,
				};
			}),
		};
	} catch {
		return null;
	}
}

// --- Tasks (tasks.md) --------------------------------------------------------

async function readTasks(repoRoot, activeScenario) {
	if (!activeScenario?.scenarioPath) return null;
	const tasksPath = path.join(activeScenario.scenarioPath, "tasks.md");
	if (!existsSync(tasksPath)) return null;
	try {
		const content = await fs.readFile(tasksPath, "utf8");
		const { tasks, overview } = parseTasksMd(content);
		const tasksDir = path.join(activeScenario.scenarioPath, "tasks");
		await Promise.all(
			tasks.map(async (task) => {
				const taskDir = path.join(tasksDir, task.id);
				const detailsPath = path.join(taskDir, "progress-details.md");
				const taskMdPath = path.join(taskDir, "task.md");
				try {
					task.progressDetails = await fs.readFile(detailsPath, "utf8");
					task.progressDetailsPath = detailsPath;
				} catch {
					task.progressDetails = null;
				}
				try {
					task.taskBlurb = (await fs.readFile(taskMdPath, "utf8")).trim();
				} catch {
					task.taskBlurb = null;
				}
			})
		);
		return { path: tasksPath, scenarioId: activeScenario.id, overview, tasks };
	} catch {
		return null;
	}
}

// --- Diagnostics -------------------------------------------------------------

async function buildDiagnostics(repoRoot, resolution, activeScenario) {
	const candidates = [];
	function probe(label, p) {
		let exists = false;
		let isFile = false;
		let size;
		try {
			const st = statSync(p);
			exists = true;
			isFile = st.isFile();
			size = st.size;
		} catch {
			// not found
		}
		candidates.push({ label, path: p, exists, isFile, size });
	}
	const git = resolveGitDir(repoRoot);
	probe("repoRoot", repoRoot);
	probe(`.git (${git.kind})`, path.join(repoRoot, ".git"));
	if (git.gitDir && git.kind === "worktree") {
		probe("resolved gitdir", git.gitDir);
		probe("activity.jsonl (resolved gitdir)", path.join(git.gitDir, "upgrade", "activity.jsonl"));
	}
	probe("activity.jsonl (literal .git)", path.join(repoRoot, ".git", "upgrade", "activity.jsonl"));
	probe("activity.jsonl (.vs)", path.join(repoRoot, ".vs", "upgrade", "activity.jsonl"));
	probe("scenarios dir", path.join(repoRoot, SCENARIOS_REL));
	if (activeScenario?.scenarioPath) {
		probe("active scenario", activeScenario.scenarioPath);
		probe("scenario.json", path.join(activeScenario.scenarioPath, "scenario.json"));
		probe("changelog.jsonl", path.join(activeScenario.scenarioPath, "changelog.jsonl"));
		probe("tasks.md", path.join(activeScenario.scenarioPath, "tasks.md"));
		probe("assessment.json (scenario)", path.join(activeScenario.scenarioPath, "assessment.json"));
		probe("assessment.json (scenario/assessment)", path.join(activeScenario.scenarioPath, "assessment", "assessment.json"));
		probe("dependencies-health.json (scenario)", path.join(activeScenario.scenarioPath, "dependencies-health.json"));
		probe("dependencies-health.json (scenario/assessment)", path.join(activeScenario.scenarioPath, "assessment", "dependencies-health.json"));
	}
	probe("assessment.json (.vs)", path.join(repoRoot, ".vs", "upgrade", "assessment", "assessment.json"));
	probe("dependencies-health.json (.vs)", path.join(repoRoot, ".vs", "upgrade", "assessment", "dependencies-health.json"));
	return {
		resolvedRepoRoot: repoRoot,
		resolutionSource: resolution?.source ?? "unknown",
		processCwd: process.cwd(),
		envRepoOverride: process.env.MODERNIZE_DASHBOARD_REPO ?? null,
		extensionPath: process.env.EXTENSION_PATH ?? null,
		sessionId: process.env.SESSION_ID ?? null,
		gitKind: git.kind,
		gitDir: git.gitDir,
		paths: candidates,
		generatedAt: new Date().toISOString(),
	};
}

// --- Snapshot ----------------------------------------------------------------

export async function snapshot(repoRoot, resolution) {
	const scenarios = await readScenarios(repoRoot);
	const activeScenario = getActiveScenario(scenarios);
	const [activity, projects, assessment, dependencies, tasks, diagnostics, scenarioInstructions] = await Promise.all([
		readActivityTail(repoRoot, activeScenario),
		readProjects(repoRoot),
		readAssessment(repoRoot, activeScenario),
		readDependencyHealth(repoRoot, activeScenario),
		readTasks(repoRoot, activeScenario),
		buildDiagnostics(repoRoot, resolution, activeScenario),
		readScenarioInstructions(activeScenario),
	]);
	const activitySources = [];
	const envelope = resolveActivityLog(repoRoot);
	if (existsSync(envelope)) activitySources.push(envelope);
	if (activeScenario?.scenarioPath) {
		const cl = path.join(activeScenario.scenarioPath, "changelog.jsonl");
		if (existsSync(cl)) activitySources.push(cl);
	}
	return {
		repoRoot,
		activityLog: activitySources[0] ?? envelope,
		activitySources,
		activeScenarioId: activeScenario?.id ?? null,
		activity,
		scenarios,
		projects,
		assessment,
		dependencies,
		tasks,
		diagnostics,
		scenarioInstructions,
		generatedAt: new Date().toISOString(),
	};
}

// scenario-instructions.md captures the user's choices made during the
// pre-assessment options step (strategy, target framework, project approach,
// package management, security vulns, source/working branches, commit
// strategy, etc.). It's the source of truth for the Options tab.
async function readScenarioInstructions(activeScenario) {
	if (!activeScenario?.scenarioPath) return null;
	const candidates = [
		path.join(activeScenario.scenarioPath, "scenario-instructions.md"),
		path.join(activeScenario.scenarioPath, "scenario", "scenario-instructions.md"),
	];
	for (const candidate of candidates) {
		if (existsSync(candidate)) {
			try {
				const content = await fs.readFile(candidate, "utf8");
				return { path: candidate, content };
			} catch {
				return null;
			}
		}
	}
	return null;
}

// --- Repo path resolution (disk-walk only — session-aware resolution lives in extension.mjs) ---

export function resolveRepoRootFromDisk(startDir = process.cwd()) {
	if (process.env.MODERNIZE_DASHBOARD_REPO) {
		return { path: process.env.MODERNIZE_DASHBOARD_REPO, source: "MODERNIZE_DASHBOARD_REPO env var" };
	}
	let dir = startDir;
	while (true) {
		if (existsSync(path.join(dir, ".git"))) {
			return { path: dir, source: `walked up from ${startDir} to .git` };
		}
		const parent = path.dirname(dir);
		if (parent === dir) break;
		dir = parent;
	}
	dir = startDir;
	while (true) {
		if (existsSync(path.join(dir, ".github", "upgrades", "scenarios"))) {
			return { path: dir, source: `walked up from ${startDir} to .github/upgrades/scenarios` };
		}
		const parent = path.dirname(dir);
		if (parent === dir) break;
		dir = parent;
	}
	return { path: startDir, source: `process.cwd() fallback (no .git or .github/upgrades found): ${startDir}` };
}
