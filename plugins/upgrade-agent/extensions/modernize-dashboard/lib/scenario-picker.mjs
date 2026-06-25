// Copyright (c) Microsoft Corporation. All rights reserved.

// Helpers for the Scenario picker card grid. Computes a display card per
// scenario summarizing the most useful fields, mirroring the dashboard's
// /scenarios picker page.

import { scenarioTargetFramework, scenarioPhases, phaseStateClass } from "./scenario.mjs";

// Build a flat scenario card descriptor from a raw scenario record. Returns
// { id, isActive, target, description, status, phases, mtime } where:
// - status is a short summary like "3 / 4 complete" or "2 / 4 in progress"
//   derived from properties.taskStates
// - target is the UpgradeTargetFramework string or null
// - description is the scenario.description string or null
// - phases is the same shape as scenarioPhases (id, state, label)
// - mtime is the original mtime for sorting
export function buildScenarioCard(scenario, activeScenarioId) {
	if (!scenario || typeof scenario !== "object") return null;
	const phases = scenarioPhases(scenario);
	const counts = countPhases(phases);
	let status;
	if (counts.total === 0) {
		status = "Not started";
	} else if (counts.complete === counts.total) {
		status = `Complete (${counts.complete} / ${counts.total})`;
	} else if (counts.failed > 0) {
		status = `${counts.failed} failed / ${counts.total}`;
	} else if (counts.inProgress > 0) {
		status = `${counts.complete} / ${counts.total} complete · ${counts.inProgress} in progress`;
	} else {
		status = `${counts.complete} / ${counts.total} complete`;
	}
	return {
		id: scenario.id,
		isActive: scenario.id === activeScenarioId,
		target: scenarioTargetFramework(scenario),
		description: typeof scenario.description === "string" ? scenario.description : null,
		phases,
		status,
		counts,
		mtime: scenario.mtime ?? 0,
	};
}

export function countPhases(phases) {
	const counts = { total: 0, complete: 0, inProgress: 0, failed: 0, skipped: 0, notStarted: 0 };
	if (!Array.isArray(phases)) return counts;
	for (const p of phases) {
		if (!p || typeof p !== "object") continue;
		counts.total++;
		const c = phaseStateClass(p.state);
		switch (c) {
			case "complete": counts.complete++; break;
			case "in-progress": counts.inProgress++; break;
			case "failed": counts.failed++; break;
			case "skipped": counts.skipped++; break;
			default: counts.notStarted++; break;
		}
	}
	return counts;
}

// Sort scenarios for the picker: active first, then most-recently-modified.
// Filters out non-object entries defensively.
export function sortScenariosForPicker(scenarios, activeId) {
	if (!Array.isArray(scenarios)) return [];
	const clean = scenarios.filter((s) => s && typeof s === "object");
	return clean.sort((a, b) => {
		const aActive = a.id === activeId ? 1 : 0;
		const bActive = b.id === activeId ? 1 : 0;
		if (aActive !== bActive) return bActive - aActive;
		return (b.mtime ?? 0) - (a.mtime ?? 0);
	});
}
