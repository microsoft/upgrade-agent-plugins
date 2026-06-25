// Copyright (c) Microsoft Corporation. All rights reserved.

// Helpers for the Scenario tab — source TFM detection, phase id humanization,
// task-state classification. Pure functions; used by the iframe but mirrored
// here for unit testing.

// Pick the most common (modal) target framework across the discovered projects.
// Falls back to the first TFM found if all projects have a different one.
// Returns null when no projects (or no TFMs) are known.
export function detectSourceFramework(projects) {
	if (!Array.isArray(projects) || projects.length === 0) return null;
	const counts = new Map();
	for (const p of projects) {
		for (const tfm of p.targetFrameworks ?? []) {
			counts.set(tfm, (counts.get(tfm) ?? 0) + 1);
		}
	}
	if (counts.size === 0) return null;
	let best = null;
	let bestCount = -1;
	for (const [tfm, n] of counts) {
		if (n > bestCount) {
			best = tfm;
			bestCount = n;
		}
	}
	return best;
}

// Read the target framework from a scenario record (the upgrade agent stores
// it under properties.UpgradeTargetFramework). Returns null if missing.
export function scenarioTargetFramework(scenario) {
	if (!scenario) return null;
	return scenario.properties?.UpgradeTargetFramework
		?? scenario.properties?.upgradeTargetFramework
		?? null;
}

// Read the phase entries from a scenario record. Returns an array of
// { id, state, label } in their declared order. `state` matches the C#
// TaskState enum values ("NotStarted" | "InProgress" | "Complete" | "Failed" | "Skipped").
export function scenarioPhases(scenario) {
	if (!scenario) return [];
	const states = scenario.properties?.taskStates
		?? scenario.properties?.TaskStates
		?? null;
	if (!states || typeof states !== "object") return [];
	const entries = Object.entries(states);
	return entries.map(([id, state]) => ({
		id,
		state: typeof state === "string" ? state : "NotStarted",
		label: humanizePhaseId(id),
	}));
}

// "01-prerequisites" -> "Prerequisites"
// "02-upgrade-tfms-and-packages" -> "Upgrade Tfms And Packages"
export function humanizePhaseId(id) {
	if (typeof id !== "string") return "";
	// Strip leading numeric + dash prefix(es).
	const stripped = id.replace(/^\d+(?:\.\d+)*-?/, "");
	const words = stripped.split(/[-_\s]+/).filter(Boolean);
	return words
		.map((w) => w.charAt(0).toUpperCase() + w.slice(1))
		.join(" ");
}

// Map a task/phase state to a CSS class suffix used in the stepper UI.
export function phaseStateClass(state) {
	switch (state) {
		case "Complete":
		case "Completed":
			return "complete";
		case "InProgress":
		case "In Progress":
		case "InProgres": // tolerate typos
			return "in-progress";
		case "Failed":
			return "failed";
		case "Skipped":
			return "skipped";
		case "NotStarted":
		case "Not Started":
		case "Pending":
			return "not-started";
		default:
			return "not-started";
	}
}
