// Copyright (c) Microsoft Corporation. All rights reserved.

// Builds the Projects table rows from the assessment's project list, matching
// the .NET dashboard (whose Projects page is assessment-derived). Before an
// assessment exists the list is empty. The discovered .csproj list is kept as
// a fallback for disk-only signal (SDK-style flag, kind, frameworks) and is
// also used by the graph for <ProjectReference> edges.
//
// "Incidents" maps to `ruleInstances.length` per project (matching the
// dashboard's `Project.RuleInstances.Count`), NOT the per-project `issues`
// field which counts distinct rules triggered.

function normalizePath(p) {
	if (typeof p !== "string") return "";
	return p.replace(/\\/g, "/").replace(/^\.\//, "").toLowerCase();
}

function basename(p) {
	if (typeof p !== "string") return "";
	const norm = p.replace(/\\/g, "/");
	const slash = norm.lastIndexOf("/");
	const base = slash < 0 ? norm : norm.slice(slash + 1);
	return base.replace(/\.[a-z]+proj$/i, "");
}

function dirname(p) {
	if (typeof p !== "string") return "";
	const norm = p.replace(/\\/g, "/");
	const slash = norm.lastIndexOf("/");
	return slash < 0 ? "" : norm.slice(0, slash);
}

function ruleInstanceCount(ap) {
	if (!ap) return 0;
	if (Array.isArray(ap.ruleInstances)) return ap.ruleInstances.length;
	if (Array.isArray(ap.RuleInstances)) return ap.RuleInstances.length;
	if (typeof ap.issues === "number") return ap.issues;
	return 0;
}

// Treat platform-suffixed TFMs (e.g., net10.0-windows) as matching the base
// scenario target (net10.0). Case-insensitive. Two suffixed TFMs (like
// net10.0-windows vs net10.0-android) are *not* equivalent to each other —
// only the base-vs-suffixed pair counts.
function tfmsEquivalent(a, b) {
	if (typeof a !== "string" || typeof b !== "string") return false;
	const la = a.toLowerCase();
	const lb = b.toLowerCase();
	if (la === lb) return true;
	const aDash = la.indexOf("-");
	const bDash = lb.indexOf("-");
	if ((aDash >= 0) === (bDash >= 0)) return false;
	const baseA = aDash < 0 ? la : la.slice(0, aDash);
	const baseB = bDash < 0 ? lb : lb.slice(0, bDash);
	return baseA === baseB;
}

// `diskProjects` is the discovered .csproj list (used only as a fallback for
// disk-only signal). `assessment` is the source of truth for the row set.
export function joinProjectsWithAssessment(diskProjects, assessment, scenarioTarget) {
	const disk = Array.isArray(diskProjects) ? diskProjects : [];
	const diskByPath = new Map();
	for (const p of disk) {
		if (p && typeof p === "object" && typeof p.projectPath === "string") {
			diskByPath.set(normalizePath(p.projectPath), p);
		}
	}

	const assessProjects = Array.isArray(assessment?.projects) ? assessment.projects : [];
	const enriched = [];
	for (const ap of assessProjects) {
		if (!ap || typeof ap !== "object") continue;
		const projectPath = typeof ap.path === "string" ? ap.path : "";
		const diskMatch = diskByPath.get(normalizePath(projectPath)) ?? null;
		const frameworks = Array.isArray(ap.frameworks)
			? ap.frameworks.filter((f) => typeof f === "string")
			: (Array.isArray(diskMatch?.targetFrameworks) ? diskMatch.targetFrameworks : []);
		const projectKind = typeof ap.projectKind === "string" ? ap.projectKind : null;
		const onTarget = scenarioTarget != null && frameworks.some((f) => tfmsEquivalent(f, scenarioTarget));
		enriched.push({
			name: (typeof ap.appName === "string" && ap.appName) ? ap.appName : basename(projectPath),
			projectPath,
			directoryPath: dirname(projectPath),
			targetFrameworks: frameworks,
			kind: projectKind ?? diskMatch?.kind ?? null,
			assessmentKind: projectKind,
			isSdk: typeof ap.isSdk === "boolean" ? ap.isSdk : !!diskMatch?.isSdk,
			incidents: ruleInstanceCount(ap),
			issues: typeof ap.issues === "number" ? ap.issues : 0,
			storyPoints: typeof ap.storyPoints === "number" ? ap.storyPoints : 0,
			startingProject: !!ap.startingProject,
			onTarget,
		});
	}

	const projectsCount = enriched.length;
	const tfmUpgraded = enriched.filter((p) => p.onTarget).length;
	const totalIncidents = enriched.reduce((sum, p) => sum + (p.incidents ?? 0), 0);

	return {
		summary: { projectsCount, tfmUpgraded, totalIncidents },
		projects: enriched,
	};
}

