// Copyright (c) Microsoft Corporation. All rights reserved.

// Overview helpers. Computes summary KPIs and shortlists for the landing
// Overview tab that mixes data from scenario, tasks, assessment, deps, and
// activity into a single at-a-glance view.

import { scenarioTargetFramework, scenarioPhases, phaseStateClass, humanizePhaseId } from "./scenario.mjs";
import { countPhases } from "./scenario-picker.mjs";

// Build a flat overview model from the full canvas state. Returns:
//   {
//     scenario: { id, target, source, phases, counts } | null,
//     tasks: { total, complete, inProgress, failed, pct } | null,
//     assessment: { projects, incidents, mandatory } | null,
//     dependencies: { packages, drift, incompatible } | null,
//     activity: [ ...recentEntries ],   // last N
//     activitySources: string[],
//   }
export function buildOverview(state, options = {}) {
	const s = state ?? {};
	const o = options ?? {};
	const rawLimit = o.activityLimit;
	const limit = Number.isFinite(rawLimit) ? Math.max(0, Math.trunc(rawLimit)) : 8;
	const scenario = pickActiveScenarioOverview(s);
	const tasks = computeTaskSummary(s.tasks);
	const assessment = pickAssessmentSummary(s.assessment);
	const dependencies = pickDepsSummary(s.dependencies);
	const activity = Array.isArray(s.activity) ? s.activity.slice(0, limit) : [];
	const activitySources = Array.isArray(s.activitySources) ? s.activitySources : [];
	return { scenario, tasks, assessment, dependencies, activity, activitySources };
}

function pickActiveScenarioOverview(state) {
	const list = Array.isArray(state.scenarios) ? state.scenarios : [];
	const active = list.find((s) => s && s.id === state.activeScenarioId) ?? null;
	if (!active) return null;
	// Prefer the authoritative task list (tasks.md) over the scenario's taskStates
	// map. taskStates is populated lazily by workflow tools, so tasks that have not
	// started yet are absent and the total under-counts. tasks.md lists every task
	// (including NotStarted ones), so building the progress from it keeps the
	// Scenario progress bar consistent with the header + At-a-glance counts.
	const taskList = Array.isArray(state.tasks?.tasks) ? state.tasks.tasks : null;
	const phases = taskList && taskList.length > 0
		? phasesFromTasks(taskList)
		: scenarioPhases(active);
	const counts = countPhases(phases);
	const target = scenarioTargetFramework(active);
	return {
		id: active.id,
		target,
		source: detectSourceFromProjects(state.projects),
		phases,
		counts,
		description: typeof active.description === "string" ? active.description : null,
		allOnTarget: allProjectsOnTarget(state.projects, target),
	};
}

// Map the parsed tasks.md task records into the { id, state, label } phase shape
// used by the scenario progress bar and phase dots.
function phasesFromTasks(tasks) {
	return tasks.map((t) => {
		const id = typeof t?.id === "string" ? t.id : "";
		return {
			id,
			state: typeof t?.state === "string" ? t.state : "NotStarted",
			label: (typeof t?.displayName === "string" && t.displayName)
				? t.displayName
				: humanizePhaseId(id),
		};
	});
}

// True when every project's framework list includes the target (platform-suffix
// tolerant: net10.0-windows counts as net10.0, but two suffixed TFMs are NOT
// treated as equivalent to each other).
function allProjectsOnTarget(projects, target) {
	if (!Array.isArray(projects) || projects.length === 0) return false;
	if (typeof target !== "string" || !target) return false;
	const tLc = target.toLowerCase();
	const tDash = tLc.indexOf("-");
	const tBase = tDash < 0 ? tLc : tLc.slice(0, tDash);
	const tHasSuffix = tDash >= 0;
	return projects.every((p) => {
		const list = Array.isArray(p?.targetFrameworks) ? p.targetFrameworks
			: Array.isArray(p?.frameworks) ? p.frameworks
			: [];
		if (list.length === 0) return false;
		return list.some((f) => {
			if (typeof f !== "string") return false;
			const fLc = f.toLowerCase();
			if (fLc === tLc) return true;
			const fDash = fLc.indexOf("-");
			const fHasSuffix = fDash >= 0;
			if (tHasSuffix === fHasSuffix) return false;
			const fBase = fDash < 0 ? fLc : fLc.slice(0, fDash);
			return fBase === tBase;
		});
	});
}

// Best-effort source TFM (most common across project frameworks list).
function detectSourceFromProjects(projects) {
	if (!Array.isArray(projects)) return null;
	const counts = new Map();
	for (const p of projects) {
		const frameworks = Array.isArray(p?.targetFrameworks) ? p.targetFrameworks
			: Array.isArray(p?.frameworks) ? p.frameworks
			: [];
		for (const f of frameworks) {
			if (typeof f === "string" && f) counts.set(f, (counts.get(f) ?? 0) + 1);
		}
	}
	let best = null; let bestCount = 0;
	for (const [k, v] of counts) {
		if (v > bestCount) { best = k; bestCount = v; }
	}
	return best;
}

function computeTaskSummary(t) {
	if (!t || !Array.isArray(t.tasks)) return null;
	const counts = { Complete: 0, InProgress: 0, NotStarted: 0, Skipped: 0, Failed: 0 };
	for (const task of t.tasks) {
		const k = typeof task?.state === "string" ? task.state : "NotStarted";
		counts[k] = (counts[k] ?? 0) + 1;
	}
	const total = t.tasks.length;
	const pct = total ? Math.round((counts.Complete / total) * 100) : 0;
	return {
		total,
		complete: counts.Complete,
		inProgress: counts.InProgress,
		failed: counts.Failed,
		pct,
	};
}

function pickAssessmentSummary(a) {
	if (!a || !a.counts) return null;
	return {
		projects: a.counts.projects ?? 0,
		incidents: a.counts.incidents ?? 0,
		mandatory: a.counts.mandatory ?? 0,
	};
}

function pickDepsSummary(d) {
	if (!d) return null;
	const c = d.counts ?? {};
	// Count incompatible packages where possible (mirrors the dashboard).
	let incompatible = 0;
	if (Array.isArray(d.packages)) {
		for (const p of d.packages) {
			if (p && p.isCompatible === false) incompatible++;
		}
	}
	return {
		packages: c.distinctPackages ?? (Array.isArray(d.packages) ? d.packages.length : 0),
		drift: c.versionDrift ?? 0,
		incompatible,
		targetFramework: d.targetFramework ?? null,
	};
}

// Reuses scenario-picker semantics for naming consistency.
export { phaseStateClass };
