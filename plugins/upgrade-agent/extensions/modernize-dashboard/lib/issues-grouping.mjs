// Copyright (c) Microsoft Corporation. All rights reserved.

// Issues grouping for the Assessment > Issues sub-tab. Mirrors the dashboard's
// AssessmentExplorerPanel: takes raw projects + rules and produces a flat
// incident list plus a grouped view filtered by a search query.

// Severity ordering (matches the dashboard).
export const SEVERITY_ORDER = ["Mandatory", "Optional", "Potential", "Information"];

// Derive a category from a rule object. Prefer the explicit rule.category
// field; otherwise infer from the ruleId prefix (e.g., "NuGet.0002" → "NuGet").
function deriveCategory(rule, ruleId) {
	if (rule && typeof rule.category === "string" && rule.category) return rule.category;
	if (typeof ruleId === "string" && ruleId.includes(".")) {
		return ruleId.slice(0, ruleId.indexOf("."));
	}
	return "Uncategorized";
}

// Pull a short project name out of a path.
function projectName(p) {
	if (typeof p !== "string" || !p) return "(unknown project)";
	const normalized = p.replace(/\\/g, "/");
	const base = normalized.split("/").pop() ?? normalized;
	return base.replace(/\.[a-z]+proj$/i, "");
}

// Flatten projects[i].ruleInstances[] into a single list of incident records
// joined with rule metadata. Each incident has:
//   { incidentId, ruleId, ruleLabel, ruleDescription, severity, category,
//     mandatory, isFeature, project, projectPath, location, description, state }
export function flattenIncidents(projects, rules) {
	const out = [];
	if (!Array.isArray(projects)) return out;
	const ruleMap = rules && typeof rules === "object" ? rules : {};
	for (const p of projects) {
		if (!p || typeof p !== "object") continue;
		const instances = Array.isArray(p.ruleInstances) ? p.ruleInstances : [];
		const projPath = p.path ?? null;
		const projDisplay = p.appName ?? projectName(projPath);
		for (const ri of instances) {
			if (!ri || typeof ri !== "object") continue;
			const ruleId = typeof ri.ruleId === "string" ? ri.ruleId : "(unknown)";
			const rule = ruleMap[ruleId] ?? null;
			const severity = (rule && typeof rule.severity === "string") ? rule.severity : "Information";
			out.push({
				incidentId: typeof ri.incidentId === "string" ? ri.incidentId : null,
				ruleId,
				ruleLabel: (rule && typeof rule.label === "string") ? rule.label : ruleId,
				ruleDescription: (rule && typeof rule.description === "string") ? rule.description : null,
				severity,
				category: deriveCategory(rule, ruleId),
				mandatory: severity === "Mandatory",
				isFeature: !!(rule && rule.isFeature),
				project: projDisplay,
				projectPath: ri.projectPath ?? projPath,
				location: ri.location && typeof ri.location === "object" ? ri.location : null,
				description: typeof ri.description === "string" ? ri.description : null,
				state: typeof ri.state === "string" ? ri.state : null,
			});
		}
	}
	return out;
}

// Lower-case helper used for case-insensitive search; safe for non-strings.
function lc(s) {
	return typeof s === "string" ? s.toLowerCase() : "";
}

// Returns true if the incident matches the search query against ruleId,
// ruleLabel, project, projectPath, location.path/label/snippet, description.
export function incidentMatchesSearch(incident, query) {
	const q = typeof query === "string" ? query.toLowerCase() : "";
	if (!q) return true;
	if (lc(incident.ruleId).includes(q)) return true;
	if (lc(incident.ruleLabel).includes(q)) return true;
	if (lc(incident.project).includes(q)) return true;
	if (lc(incident.projectPath).includes(q)) return true;
	if (lc(incident.description).includes(q)) return true;
	const loc = incident.location ?? {};
	if (lc(loc.path).includes(q)) return true;
	if (lc(loc.label).includes(q)) return true;
	if (lc(loc.snippet).includes(q)) return true;
	if (lc(incident.severity).includes(q)) return true;
	if (lc(incident.category).includes(q)) return true;
	return false;
}

// Group incidents by one of: "rule", "category", "severity", "project".
// `search` (string) optionally narrows by case-insensitive substring.
// Returns sorted groups: [{ key, label, severity, count, incidents: [...] }].
// For "severity" grouping, groups are ordered by SEVERITY_ORDER; otherwise
// groups are sorted by descending incident count, then alphabetical label.
export function groupIncidents(incidents, groupBy, search) {
	if (!Array.isArray(incidents)) return [];
	const filtered = incidents.filter((i) => i && incidentMatchesSearch(i, search ?? ""));
	const buckets = new Map();
	const groupKey = (i) => {
		switch (groupBy) {
			case "category": return i.category ?? "Uncategorized";
			case "severity": return i.severity ?? "Information";
			case "project": return i.project ?? "(unknown project)";
			case "rule":
			default: return i.ruleId;
		}
	};
	const groupLabel = (i, key) => {
		if (groupBy === "rule") return i.ruleLabel ? `${key} — ${i.ruleLabel}` : key;
		return String(key);
	};
	for (const inc of filtered) {
		const key = groupKey(inc);
		let g = buckets.get(key);
		if (!g) {
			g = { key, label: groupLabel(inc, key), severity: null, count: 0, incidents: [] };
			buckets.set(key, g);
		}
		g.incidents.push(inc);
		g.count++;
		// Track the most-severe incident in the group for badge purposes.
		if (g.severity === null || severityRank(inc.severity) < severityRank(g.severity)) {
			g.severity = inc.severity;
		}
	}
	const groups = [...buckets.values()];
	if (groupBy === "severity") {
		groups.sort((a, b) => severityRank(a.key) - severityRank(b.key));
	} else {
		groups.sort((a, b) => (b.count - a.count) || a.label.localeCompare(b.label));
	}
	return groups;
}

function severityRank(s) {
	const i = SEVERITY_ORDER.indexOf(s);
	return i < 0 ? SEVERITY_ORDER.length : i;
}
