// Copyright (c) Microsoft Corporation. All rights reserved.

// Project dependency graph model + a minimal SVG-friendly force layout.
// Mirrors the dashboard's Projects > Graph panel: nodes are projects, edges
// are <ProjectReference> relationships, status is color-coded against the
// active scenario's target framework.

// Build the graph from canvas state. Returns:
//   {
//     nodes: [{ id, label, status, framework, incidents, kind }],
//     edges: [{ source, target }],
//     target: string|null,
//   }
// `joinedProjects` is the output of joinProjectsWithAssessment (so we get
// `incidents` per project). `targetFramework` is the active scenario's TFM.
export function buildProjectsGraph(joinedProjects, rawProjects, targetFramework) {
	const target = typeof targetFramework === "string" ? targetFramework : null;
	const byPath = new Map();   // normalized path -> node id
	const nodes = [];
	const projs = Array.isArray(joinedProjects) ? joinedProjects : [];
	for (const p of projs) {
		if (!p) continue;
		const id = normalizePath(p.projectPath ?? p.path ?? p.name ?? "");
		if (!id || byPath.has(id)) continue;
		byPath.set(id, id);
		nodes.push({
			id,
			label: p.name ?? basename(id),
			status: classifyStatus(p.targetFrameworks ?? p.frameworks ?? [], target),
			framework: pickFramework(p.targetFrameworks ?? p.frameworks ?? []),
			incidents: typeof p.incidents === "number" ? p.incidents : 0,
			kind: p.kind ?? p.projectKind ?? null,
		});
	}

	const edges = [];
	const seenEdges = new Set();
	const rawList = Array.isArray(rawProjects) ? rawProjects : [];
	for (const r of rawList) {
		if (!r) continue;
		const fromId = normalizePath(r.projectPath ?? r.path ?? r.name ?? "");
		if (!fromId || !byPath.has(fromId)) continue;
		const refs = Array.isArray(r.projectReferences) ? r.projectReferences : [];
		const fromDir = dirname(fromId);
		for (const ref of refs) {
			const resolved = resolveReference(fromDir, ref);
			if (!resolved) continue;
			if (resolved === fromId || !byPath.has(resolved)) continue;
			const key = `${fromId}|${resolved}`;
			if (seenEdges.has(key)) continue;
			seenEdges.add(key);
			edges.push({ source: fromId, target: resolved });
		}
	}
	return { nodes, edges, target };
}

// Classify project status against a target TFM string. Comparison is
// case-insensitive (csproj TFM strings sometimes appear in mixed case) and
// platform-suffix tolerant: a project targeting "net10.0-windows" counts as
// matching when the scenario target is "net10.0".
//   "no-target"   – project has no frameworks listed
//   "matched"     – the target framework is the project's only framework
//                   (with platform-suffix tolerance)
//   "in-progress" – multi-targeted and includes the target
//   "not-started" – does not include the target
export function classifyStatus(frameworks, target) {
	const list = Array.isArray(frameworks) ? frameworks.filter((f) => typeof f === "string") : [];
	if (list.length === 0) return "no-target";
	if (!target || typeof target !== "string") return "not-started";
	const targetLc = target.toLowerCase();
	const matches = list.some((f) => tfmsEquivalent(f.toLowerCase(), targetLc));
	if (matches && list.length === 1) return "matched";
	if (matches) return "in-progress";
	return "not-started";
}

// Two TFMs are equivalent for upgrade-target purposes when one side is the
// unsuffixed base (e.g., "net10.0") and the other carries a platform suffix
// for the same base (e.g., "net10.0-windows"). We deliberately do NOT treat
// two platform-suffixed TFMs as equivalent to each other (net10.0-windows
// vs net10.0-android are different surfaces); only base-vs-suffixed pairs.
function tfmsEquivalent(a, b) {
	if (a === b) return true;
	const aDash = a.indexOf("-");
	const bDash = b.indexOf("-");
	// Both suffixed (or both unsuffixed and not equal): require exact match.
	if ((aDash >= 0) === (bDash >= 0)) return false;
	const baseA = aDash < 0 ? a : a.slice(0, aDash);
	const baseB = bDash < 0 ? b : b.slice(0, bDash);
	return baseA === baseB;
}

// A tiny deterministic Verlet-style layout. Returns a map nodeId -> {x, y}.
// Avoids any dependency on d3/canvas. The "physics" is simple:
//   - Each node gets an initial position via a deterministic hash so layouts
//     are stable across re-renders.
//   - For each iteration, edges pull connected nodes together, all nodes
//     repel each other, and a centering force keeps the graph in-bounds.
// `iterations` defaults to 200. Width/height default to 600/400. The result
// is suitable to drop into an SVG of those dimensions with a 30px margin.
export function layoutGraph(model, options = {}) {
	const width = Number.isFinite(options.width) ? options.width : 600;
	const height = Number.isFinite(options.height) ? options.height : 400;
	const iterations = Number.isFinite(options.iterations) ? options.iterations : 200;
	const margin = Number.isFinite(options.margin) ? options.margin : 30;
	const rawNodes = (model && Array.isArray(model.nodes)) ? model.nodes : [];
	const edges = (model && Array.isArray(model.edges)) ? model.edges : [];
	// Filter to valid nodes (defensive: callers shouldn't pass garbage but
	// we still don't want an `id.length` crash in deterministicPos).
	const nodes = rawNodes.filter((n) => n && typeof n.id === "string" && n.id);
	const positions = new Map();
	for (const n of nodes) {
		positions.set(n.id, deterministicPos(n.id, width, height));
	}
	if (positions.size === 0) return positions;

	const cx = width / 2;
	const cy = height / 2;
	const idealEdge = Math.min(width, height) / Math.max(3, Math.sqrt(nodes.length));
	const repulsion = idealEdge * idealEdge * 0.6;

	for (let iter = 0; iter < iterations; iter++) {
		const forces = new Map();
		for (const n of nodes) forces.set(n.id, { fx: 0, fy: 0 });
		// Repulsion between every pair.
		for (let i = 0; i < nodes.length; i++) {
			const a = positions.get(nodes[i].id);
			for (let j = i + 1; j < nodes.length; j++) {
				const b = positions.get(nodes[j].id);
				const dx = a.x - b.x;
				const dy = a.y - b.y;
				const distSq = Math.max(1, dx * dx + dy * dy);
				const force = repulsion / distSq;
				const fx = (dx / Math.sqrt(distSq)) * force;
				const fy = (dy / Math.sqrt(distSq)) * force;
				forces.get(nodes[i].id).fx += fx;
				forces.get(nodes[i].id).fy += fy;
				forces.get(nodes[j].id).fx -= fx;
				forces.get(nodes[j].id).fy -= fy;
			}
		}
		// Edge attraction.
		for (const e of edges) {
			const a = positions.get(e.source);
			const b = positions.get(e.target);
			if (!a || !b) continue;
			const dx = b.x - a.x;
			const dy = b.y - a.y;
			const dist = Math.max(0.01, Math.sqrt(dx * dx + dy * dy));
			const force = (dist - idealEdge) * 0.05;
			const fx = (dx / dist) * force;
			const fy = (dy / dist) * force;
			forces.get(e.source).fx += fx;
			forces.get(e.source).fy += fy;
			forces.get(e.target).fx -= fx;
			forces.get(e.target).fy -= fy;
		}
		// Centering tug to keep things on screen.
		for (const n of nodes) {
			const p = positions.get(n.id);
			const f = forces.get(n.id);
			f.fx += (cx - p.x) * 0.005;
			f.fy += (cy - p.y) * 0.005;
		}
		// Apply with cooling.
		const cooling = 1 - iter / iterations;
		const maxStep = idealEdge * 0.2 * cooling;
		for (const n of nodes) {
			const p = positions.get(n.id);
			const f = forces.get(n.id);
			const stepX = clamp(f.fx, -maxStep, maxStep);
			const stepY = clamp(f.fy, -maxStep, maxStep);
			p.x = clamp(p.x + stepX, margin, width - margin);
			p.y = clamp(p.y + stepY, margin, height - margin);
		}
	}
	return positions;
}

function deterministicPos(id, width, height) {
	let h = 0;
	for (let i = 0; i < id.length; i++) {
		h = ((h << 5) - h + id.charCodeAt(i)) | 0;
	}
	const hx = Math.abs(h) % 1000 / 1000;
	const hy = Math.abs((h * 1103515245 + 12345) | 0) % 1000 / 1000;
	return { x: 40 + hx * (width - 80), y: 40 + hy * (height - 80) };
}

function clamp(v, lo, hi) {
	if (v < lo) return lo;
	if (v > hi) return hi;
	return v;
}

function normalizePath(p) {
	if (typeof p !== "string") return "";
	return p.replace(/\\/g, "/").toLowerCase();
}

function dirname(p) {
	const i = p.lastIndexOf("/");
	return i < 0 ? "" : p.slice(0, i);
}

function basename(p) {
	const slash = p.lastIndexOf("/");
	const base = slash < 0 ? p : p.slice(slash + 1);
	return base.replace(/\.[a-z]+proj$/i, "");
}

function pickFramework(list) {
	if (!Array.isArray(list) || list.length === 0) return null;
	return typeof list[0] === "string" ? list[0] : null;
}

// Resolve a <ProjectReference Include="..."> path relative to the
// referencing project's directory. Handles ../ traversal. Returns null when
// the reference escapes the repo root — those refs point to projects we
// can't index, so we drop them rather than fabricate an in-repo edge.
function resolveReference(fromDir, ref) {
	if (typeof ref !== "string" || !ref) return null;
	const refNorm = ref.replace(/\\/g, "/").toLowerCase();
	const baseParts = fromDir ? fromDir.split("/").filter(Boolean) : [];
	const refParts = refNorm.split("/").filter(Boolean);
	const out = [...baseParts];
	for (const part of refParts) {
		if (part === "." || part === "") continue;
		if (part === "..") {
			if (out.length === 0) return null; // escapes above repo root
			out.pop();
			continue;
		}
		out.push(part);
	}
	return out.join("/");
}
