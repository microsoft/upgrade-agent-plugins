// Copyright (c) Microsoft Corporation. All rights reserved.

// Helpers for the Assessment tab. Aggregates per-project features into a flat
// per-feature view for the Features sub-tab. Mirrors what the dashboard's
// Assessment "Features" tab shows.

// aggregateFeatures(rawProjects) → [
//   { featureId: "Remoting", totalIncidents: 4, projects: [
//     { projectPath, projectName, incidentCount }, ...
//   ] },
//   ...
// ]
// Sorted by totalIncidents descending. Input is the raw assessment.json
// projects array (each item has `features: [{ featureId, incidents: [...] }]`).
export function aggregateFeatures(projects) {
	if (!Array.isArray(projects)) return [];
	const map = new Map();
	for (const proj of projects) {
		if (!proj || typeof proj !== "object") continue;
		const projFeatures = Array.isArray(proj.features) ? proj.features : [];
		const projPath = typeof proj.path === "string" ? proj.path : "";
		const projName = proj.properties?.appName
			?? proj.properties?.AppName
			?? projPath;
		for (const f of projFeatures) {
			if (!f || typeof f !== "object" || typeof f.featureId !== "string") continue;
			const incidents = Array.isArray(f.incidents) ? f.incidents.length : 0;
			const entry = map.get(f.featureId) ?? {
				featureId: f.featureId,
				totalIncidents: 0,
				projects: [],
			};
			entry.totalIncidents += incidents;
			entry.projects.push({
				projectPath: projPath,
				projectName: projName,
				incidentCount: incidents,
			});
			map.set(f.featureId, entry);
		}
	}
	return [...map.values()].sort((a, b) => b.totalIncidents - a.totalIncidents);
}
