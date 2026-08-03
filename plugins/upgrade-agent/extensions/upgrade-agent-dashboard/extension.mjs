// extension.ts
import { existsSync as existsSync2 } from "node:fs";
import { appendFile, mkdir } from "node:fs/promises";
import path5 from "node:path";
import { CanvasError, createCanvas, joinSession } from "@github/copilot-sdk/extension";

// lib/snapshot.ts
import { promises as fs } from "node:fs";
import { existsSync, statSync as statSync2 } from "node:fs";
import path2 from "node:path";

// lib/repo.ts
import { statSync, readFileSync, readdirSync } from "node:fs";
import path from "node:path";
function resolveGitDir(repoRoot) {
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
        const target = path.isAbsolute(match[1]) ? match[1] : path.resolve(repoRoot, match[1]);
        return { gitDir: target, kind: "worktree" };
      }
    } catch {
    }
    return { gitDir: null, kind: "worktree-unresolved" };
  }
  return { gitDir: null, kind: "unknown" };
}
function activityLogDir(repoRoot) {
  const dotGit = path.join(repoRoot, ".git");
  let isDir = false;
  try {
    isDir = statSync(dotGit).isDirectory();
  } catch {
    isDir = false;
  }
  return isDir ? path.join(dotGit, "upgrade") : path.join(repoRoot, ".vs", "upgrade");
}
function resolveActivityLog(repoRoot) {
  return path.join(activityLogDir(repoRoot), "activity.jsonl");
}
function resolveActivityArchives(repoRoot) {
  const dir = activityLogDir(repoRoot);
  let names;
  try {
    names = readdirSync(dir);
  } catch {
    return [];
  }
  return names.filter((name) => /^activity-.*\.jsonl$/i.test(name)).sort((a, b) => b.localeCompare(a)).map((name) => path.join(dir, name));
}

// lib/activity.ts
var ACTIVITY_EVENT_LABELS = {
  task_started: { label: "Task started", kind: "task" },
  task_completed: { label: "Task completed", kind: "task" },
  task_failed: { label: "Task failed", kind: "task-failed" },
  file_modified: { label: "File modified", kind: "file" },
  file_created: { label: "File created", kind: "file" },
  file_deleted: { label: "File deleted", kind: "file" },
  file_renamed: { label: "File renamed", kind: "file" },
  commit_created: { label: "Commit", kind: "commit" },
  commit_amended: { label: "Commit amended", kind: "commit" },
  build_completed: { label: "Build completed", kind: "build" },
  build_session_completed: { label: "Build session completed", kind: "build" },
  phase_entered: { label: "Phase entered", kind: "phase" },
  branch_changed: { label: "Branch changed", kind: "branch" }
};
function formatActivityEntry(raw) {
  const payload = raw && typeof raw.payload === "object" && raw.payload !== null ? raw.payload : null;
  const fields = payload ? { ...raw, ...payload } : raw;
  const ts = fields.timestamp ?? fields.ts ?? fields.time ?? null;
  const eventName = fields.event ?? fields.type ?? "unknown";
  const meta = ACTIVITY_EVENT_LABELS[eventName] ?? { label: eventName, kind: "other" };
  const detail = buildActivityDetail(eventName, fields);
  const entry = {
    timestamp: ts,
    event: eventName,
    label: meta.label,
    kind: meta.kind,
    taskId: fields.taskId ?? fields.task_id ?? null,
    detail
  };
  if (meta.kind === "file") {
    entry.filePath = fields.path ?? fields.filePath ?? null;
    entry.linesAdded = fields.linesAdded ?? fields.lines_added ?? null;
    entry.linesRemoved = fields.linesRemoved ?? fields.lines_removed ?? null;
    entry.patchFile = fields.patchFile ?? fields.patch_file ?? null;
  }
  if (meta.kind === "commit") {
    entry.commitHash = fields.commitHash ?? fields.hash ?? null;
    entry.commitMessage = fields.commitMessage ?? fields.message ?? null;
    entry.commitFiles = fields.files ?? null;
  }
  return entry;
}
function buildActivityDetail(eventName, e) {
  switch (eventName) {
    case "task_started":
    case "task_completed":
    case "task_failed": {
      const parts = [];
      const name = e.displayName ?? e.taskName ?? e.name;
      if (name) parts.push(name);
      else if (e.taskId) parts.push(e.taskId);
      if (e.reason) parts.push(`\u2014 ${e.reason}`);
      return parts.join(" ");
    }
    case "file_modified":
    case "file_created":
    case "file_deleted":
    case "file_renamed": {
      const p = e.path ?? e.filePath ?? "";
      const adds = e.linesAdded ?? e.lines_added;
      const dels = e.linesRemoved ?? e.lines_removed;
      let suffix = "";
      if (adds != null || dels != null) {
        suffix = ` (+${adds ?? 0} / -${dels ?? 0})`;
      }
      return `${p}${suffix}`;
    }
    case "commit_created":
    case "commit_amended": {
      const hash = (e.commitHash ?? e.hash ?? "").slice(0, 7);
      const msg = e.commitMessage ?? e.message ?? "";
      return hash ? `${hash} ${msg}` : msg;
    }
    case "build_completed": {
      const errs = e.errorCount ?? e.errors ?? 0;
      const warns = e.warningCount ?? e.warnings ?? 0;
      const total = e.totalProjects ?? e.total ?? null;
      const ok = errs === 0;
      const tail = total != null ? ` across ${total} project${total === 1 ? "" : "s"}` : "";
      return `${ok ? "succeeded" : "failed"} \u2014 ${errs} error${errs === 1 ? "" : "s"}, ${warns} warning${warns === 1 ? "" : "s"}${tail}`;
    }
    case "build_session_completed": {
      const total = e.totalProjects ?? null;
      const succeeded = e.succeededProjects ?? null;
      const failed = e.failedProjects ?? 0;
      const ok = failed === 0 && (total ?? 0) > 0;
      const tally = total != null ? ` (${succeeded ?? 0}/${total} ok${failed ? `, ${failed} failed` : ""})` : failed ? ` \u2014 ${failed} failed` : "";
      return `${ok ? "succeeded" : "failed"}${tally}`;
    }
    case "phase_entered": {
      return e.phase ?? e.name ?? "";
    }
    case "branch_changed": {
      const from = e.oldBranch ?? e.from ?? "?";
      const to = e.newBranch ?? e.to ?? "?";
      return `${from} \u2192 ${to}`;
    }
    default: {
      const { timestamp, ts, time, event, type, taskId, task_id, ...rest } = e;
      const keys = Object.keys(rest);
      if (keys.length === 0) return "";
      if (keys.length <= 3) {
        return keys.map((k) => `${k}=${formatScalar(rest[k])}`).join(" ");
      }
      return JSON.stringify(rest);
    }
  }
}
function formatScalar(v) {
  if (v == null) return "";
  if (typeof v === "string") return v;
  if (typeof v === "number" || typeof v === "boolean") return String(v);
  return JSON.stringify(v);
}

// lib/tasks.ts
var SPACES_PER_INDENT_LEVEL = 2;
var MAX_NESTING_DEPTH = 64;
var TASK_EMOJI_MAP = [
  ["\u2705", "Complete"],
  ["\u{1F504}", "InProgress"],
  ["\u{1F532}", "NotStarted"],
  ["\u26A0\uFE0F", "Skipped"],
  ["\u274C", "Failed"]
];
var TASK_LINKS_TRAILING_RE = /\s*\(\[(?:Content|Progress)\]\([^)]+\)(?:,\s*\[(?:Content|Progress)\]\([^)]+\))*\)\s*$/;
function isParseableTaskId(id) {
  if (!id || !/^[\p{L}\p{N}]/u.test(id)) return false;
  return !/[\s:]/u.test(id);
}
function parseTaskLine(line) {
  if (!line || !line.trim()) return null;
  let leadingSpaces = 0;
  for (const c of line) {
    if (c === " ") {
      leadingSpaces++;
    } else if (c === "	") {
      leadingSpaces += SPACES_PER_INDENT_LEVEL;
    } else {
      break;
    }
  }
  let trimmed = line.trimStart();
  if (trimmed.startsWith("- ")) {
    trimmed = trimmed.slice(2);
  }
  let state = null;
  let afterEmoji = null;
  for (const [emoji, st] of TASK_EMOJI_MAP) {
    if (trimmed.startsWith(emoji)) {
      state = st;
      afterEmoji = trimmed.slice(emoji.length).trimStart();
      break;
    }
  }
  if (!state || afterEmoji == null) return null;
  const colon = afterEmoji.indexOf(":");
  if (colon <= 0) return null;
  const id = afterEmoji.slice(0, colon).trim();
  let description = afterEmoji.slice(colon + 1).trim();
  description = description.replace(TASK_LINKS_TRAILING_RE, "");
  if (!description || !isParseableTaskId(id)) return null;
  return { id, displayName: description, state, leadingSpaces };
}
function parseTasksOverview(content) {
  const lines = content.split(/\r?\n/);
  let inOverview = false;
  const out = [];
  for (const line of lines) {
    if (line.startsWith("## ")) {
      if (inOverview) break;
      if (/^##\s+Overview/i.test(line)) {
        inOverview = true;
        continue;
      }
    } else if (inOverview) {
      if (/\*\*Progress\*\*/i.test(line) || /<progress/i.test(line)) {
        continue;
      }
      out.push(line);
    }
  }
  const text = out.join("\n").trim();
  return text.length > 0 ? text : null;
}
function parseTasksMd(content) {
  const tasks = [];
  let order = 0;
  const parentStack = [];
  for (const line of content.split(/\r?\n/)) {
    const parsed = parseTaskLine(line);
    if (!parsed) continue;
    const { leadingSpaces, ...task } = parsed;
    while (parentStack.length > 0 && parentStack[parentStack.length - 1][0] >= leadingSpaces) {
      parentStack.pop();
    }
    const parentId = parentStack.length > 0 ? parentStack[parentStack.length - 1][1] : null;
    tasks.push({ ...task, order, parentId });
    order++;
    if (parentStack.length < MAX_NESTING_DEPTH) {
      parentStack.push([leadingSpaces, task.id]);
    }
  }
  return { tasks, overview: parseTasksOverview(content) };
}

// lib/projects.ts
var TARGET_FRAMEWORKS_RE = /<TargetFrameworks>(.*?)<\/TargetFrameworks>/s;
var TARGET_FRAMEWORK_RE = /<TargetFramework>(.*?)<\/TargetFramework>/s;
var OUTPUT_TYPE_RE = /<OutputType>(.*?)<\/OutputType>/s;
var SDK_ATTR_RE = /<Project[^>]*\sSdk="([^"]+)"/i;
var PROJECT_REF_RE = /<ProjectReference[^>]*\sInclude="([^"]+)"/gi;
var SKIP_DIRS = /* @__PURE__ */ new Set([".git", "node_modules", "bin", "obj"]);
function readTargetFrameworks(xml) {
  const multi = TARGET_FRAMEWORKS_RE.exec(xml);
  if (multi) {
    return multi[1].split(";").map((s) => s.trim()).filter(Boolean);
  }
  const single = TARGET_FRAMEWORK_RE.exec(xml);
  if (single) {
    const v = single[1].trim();
    return v ? [v] : [];
  }
  return [];
}
function readProjectKind(xml) {
  const sdk = SDK_ATTR_RE.exec(xml);
  if (sdk) return sdk[1].trim();
  const out = OUTPUT_TYPE_RE.exec(xml);
  if (out) return out[1].trim();
  return null;
}
function isSdkStyle(xml) {
  return SDK_ATTR_RE.test(xml);
}
function readProjectReferences(xml) {
  if (typeof xml !== "string" || !xml) return [];
  const stripped = xml.replace(/<!--[\s\S]*?-->/g, "");
  const out = [];
  let m;
  PROJECT_REF_RE.lastIndex = 0;
  while ((m = PROJECT_REF_RE.exec(stripped)) !== null) {
    const path6 = m[1].trim();
    if (path6) out.push(path6);
  }
  return out;
}

// lib/deps.ts
function pick(obj, ...names) {
  if (!obj || typeof obj !== "object") return void 0;
  for (const name of names) {
    if (Object.prototype.hasOwnProperty.call(obj, name)) {
      return obj[name];
    }
  }
  const lower = /* @__PURE__ */ new Map();
  for (const key of Object.keys(obj)) {
    lower.set(key.toLowerCase(), key);
  }
  for (const name of names) {
    const k = lower.get(name.toLowerCase());
    if (k !== void 0) return obj[k];
  }
  return void 0;
}
var INCOMPAT_VALUES = /* @__PURE__ */ new Set([
  "newVersionNeeded",
  "NewVersionNeeded",
  "notSupported",
  "NotSupported"
]);
function countIncompatible(deps) {
  if (!deps) return 0;
  let count = 0;
  for (const key of ["packages", "assemblies", "projectReferences", "frameworkReferences"]) {
    const upper = key.charAt(0).toUpperCase() + key.slice(1);
    const arr = pick(deps, key, upper);
    if (!Array.isArray(arr)) continue;
    for (const entry of arr) {
      const c = pick(entry, "compatibility", "Compatibility", "targetCompatibility", "TargetCompatibility");
      if (INCOMPAT_VALUES.has(c)) {
        count++;
      }
    }
  }
  return count;
}

// lib/paths.ts
function normalizePathSeparators(p) {
  if (typeof p !== "string" || p === "") return "";
  const slashed = p.replace(/\\/g, "/");
  return slashed.length > 1 ? slashed.replace(/\/+$/, "") : slashed;
}
function projectNameFromPath(p) {
  if (typeof p !== "string" || !p) return "(unknown project)";
  const base = normalizePathSeparators(p).split("/").pop() ?? "";
  return base.replace(/\.[a-z]+proj$/i, "");
}

// lib/assessment.ts
function aggregateFeatures(projects) {
  if (!Array.isArray(projects)) return [];
  const map = /* @__PURE__ */ new Map();
  for (const proj of projects) {
    if (!proj || typeof proj !== "object") continue;
    const projFeatures = Array.isArray(proj.features) ? proj.features : [];
    const projPath = typeof proj.path === "string" ? proj.path : "";
    const projName = proj.properties?.appName ?? proj.properties?.AppName ?? projectNameFromPath(projPath);
    for (const f of projFeatures) {
      if (!f || typeof f !== "object" || typeof f.featureId !== "string") continue;
      const incidents = Array.isArray(f.incidents) ? f.incidents.length : 0;
      const entry = map.get(f.featureId) ?? {
        featureId: f.featureId,
        totalIncidents: 0,
        projects: []
      };
      entry.totalIncidents += incidents;
      entry.projects.push({
        projectPath: projPath,
        projectName: projName,
        incidentCount: incidents
      });
      map.set(f.featureId, entry);
    }
  }
  return [...map.values()].sort((a, b) => b.totalIncidents - a.totalIncidents);
}

// lib/snapshot.ts
var SCENARIOS_REL = path2.join(".github", "upgrades", "scenarios");
async function readActivityTail(repoRoot, maxLines = 200) {
  const sources = [];
  const activityFile = resolveActivityLog(repoRoot);
  if (existsSync(activityFile)) sources.push(activityFile);
  sources.push(...resolveActivityArchives(repoRoot));
  const entries = [];
  for (const source of sources) {
    try {
      const raw = await fs.readFile(source, "utf8");
      const lines = raw.split(/\r?\n/).filter(Boolean);
      for (const line of lines) {
        try {
          entries.push(formatActivityEntry(JSON.parse(line)));
        } catch {
          entries.push({ event: "unparseable", label: "unparseable", kind: "other", detail: line });
        }
      }
    } catch {
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
var SCENARIO_ARTIFACT_FILES = ["scenario.json", "assessment.json", "plan.md"];
async function readScenarios(repoRoot) {
  const dir = path2.join(repoRoot, SCENARIOS_REL);
  let entries;
  try {
    entries = await fs.readdir(dir, { withFileTypes: true });
  } catch {
    return [];
  }
  const scenarios = [];
  for (const entry of entries) {
    if (!entry.isDirectory()) continue;
    const scenarioPath = path2.join(dir, entry.name);
    let hasArtifacts = false;
    for (const file of SCENARIO_ARTIFACT_FILES) {
      if (existsSync(path2.join(scenarioPath, file))) {
        hasArtifacts = true;
        break;
      }
    }
    if (!hasArtifacts) continue;
    let mtime = 0;
    try {
      mtime = (await fs.stat(scenarioPath)).mtimeMs;
    } catch {
    }
    let body = {};
    try {
      body = JSON.parse(await fs.readFile(path2.join(scenarioPath, "scenario.json"), "utf8"));
    } catch {
      body = { error: "could not read scenario.json" };
    }
    scenarios.push({ id: entry.name, scenarioPath, mtime, ...body });
  }
  scenarios.sort((a, b) => (b.mtime ?? 0) - (a.mtime ?? 0));
  return scenarios;
}
function getActiveScenario(scenarios) {
  return scenarios.length > 0 ? scenarios[0] : null;
}
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
      const full = path2.join(dir, entry.name);
      if (entry.isDirectory()) {
        await walk(full);
        continue;
      }
      if (!/\.(cs|fs)proj$/i.test(entry.name)) continue;
      const relativePath = path2.relative(repoRoot, full);
      let xml = "";
      try {
        xml = await fs.readFile(full, "utf8");
      } catch {
      }
      projects.push({
        name: path2.basename(entry.name, path2.extname(entry.name)),
        projectPath: relativePath,
        directoryPath: path2.dirname(relativePath),
        targetFrameworks: readTargetFrameworks(xml),
        kind: readProjectKind(xml),
        isSdk: isSdkStyle(xml),
        projectReferences: readProjectReferences(xml)
      });
    }
  }
  await walk(repoRoot);
  projects.sort((a, b) => a.projectPath.localeCompare(b.projectPath));
  return projects;
}
function findAssessmentJson(activeScenario) {
  if (!activeScenario?.scenarioPath) return null;
  const file = path2.join(activeScenario.scenarioPath, "assessment.json");
  return existsSync(file) ? file : null;
}
async function readAssessment(activeScenario) {
  const file = findAssessmentJson(activeScenario);
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
        mandatory: charts.severity?.Mandatory ?? 0
      },
      severity: charts.severity ?? {},
      category: charts.category ?? {},
      features,
      projects: projects.filter((p) => p && typeof p === "object").map((p) => ({
        path: p.path,
        startingProject: !!p.startingProject,
        issues: p.issues ?? 0,
        storyPoints: p.storyPoints ?? 0,
        appName: p.properties?.appName ?? null,
        frameworks: p.properties?.frameworks ?? [],
        projectKind: p.properties?.projectKind ?? null,
        isSdk: !!p.properties?.isSdkStyle,
        ruleInstances: Array.isArray(p.ruleInstances) ? p.ruleInstances.filter((ri) => ri && typeof ri === "object") : []
      })),
      rules: data.rules && typeof data.rules === "object" ? data.rules : {},
      markdown: await readAssessmentMarkdown(activeScenario)
    };
  } catch {
    return null;
  }
}
async function readAssessmentMarkdown(activeScenario) {
  if (!activeScenario?.scenarioPath) return null;
  const file = path2.join(activeScenario.scenarioPath, "assessment.md");
  if (!existsSync(file)) return null;
  try {
    return { path: file, content: await fs.readFile(file, "utf8") };
  } catch {
    return null;
  }
}
function findDependencyHealthJson(activeScenario) {
  if (!activeScenario?.scenarioPath) return null;
  const file = path2.join(activeScenario.scenarioPath, "dependencies-health.json");
  return existsSync(file) ? file : null;
}
async function readDependencyHealth(activeScenario) {
  const file = findDependencyHealthJson(activeScenario);
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
        projects: projects.length
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
          isRecommended: !!pick(v, "isRecommended", "IsRecommended")
        })),
        upgrade: pick(p, "upgrade", "Upgrade") ?? null
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
          dependencies: deps ?? null
        };
      })
    };
  } catch {
    return null;
  }
}
async function readTasks(repoRoot, activeScenario) {
  if (!activeScenario?.scenarioPath) return null;
  const tasksPath = path2.join(activeScenario.scenarioPath, "tasks.md");
  if (!existsSync(tasksPath)) return null;
  try {
    const content = await fs.readFile(tasksPath, "utf8");
    const { tasks, overview } = parseTasksMd(content);
    const tasksDir = path2.join(activeScenario.scenarioPath, "tasks");
    await Promise.all(
      tasks.map(async (task) => {
        const taskDir = path2.join(tasksDir, task.id);
        const detailsPath = path2.join(taskDir, "progress-details.md");
        const taskMdPath = path2.join(taskDir, "task.md");
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
async function buildDiagnostics(repoRoot, resolution, activeScenario) {
  const candidates = [];
  function probe(label, p) {
    let exists = false;
    let isFile = false;
    let size;
    try {
      const st = statSync2(p);
      exists = true;
      isFile = st.isFile();
      size = st.size;
    } catch {
    }
    candidates.push({ label, path: p, exists, isFile, size });
  }
  const git = resolveGitDir(repoRoot);
  probe("repoRoot", repoRoot);
  probe(`.git (${git.kind})`, path2.join(repoRoot, ".git"));
  if (git.gitDir && git.kind === "worktree") {
    probe("resolved gitdir", git.gitDir);
  }
  probe("activity.jsonl (literal .git)", path2.join(repoRoot, ".git", "upgrade", "activity.jsonl"));
  probe("activity.jsonl (.vs)", path2.join(repoRoot, ".vs", "upgrade", "activity.jsonl"));
  probe("scenarios dir", path2.join(repoRoot, SCENARIOS_REL));
  if (activeScenario?.scenarioPath) {
    probe("active scenario", activeScenario.scenarioPath);
    probe("scenario.json", path2.join(activeScenario.scenarioPath, "scenario.json"));
    probe("tasks.md", path2.join(activeScenario.scenarioPath, "tasks.md"));
    probe("assessment.json", path2.join(activeScenario.scenarioPath, "assessment.json"));
    probe("dependencies-health.json", path2.join(activeScenario.scenarioPath, "dependencies-health.json"));
  }
  return {
    resolvedRepoRoot: repoRoot,
    resolutionSource: resolution?.source ?? "unknown",
    processCwd: process.cwd(),
    envRepoOverride: process.env.UPGRADE_AGENT_DASHBOARD_REPO ?? null,
    extensionPath: process.env.EXTENSION_PATH ?? null,
    sessionId: process.env.SESSION_ID ?? null,
    gitKind: git.kind,
    gitDir: git.gitDir,
    paths: candidates,
    generatedAt: (/* @__PURE__ */ new Date()).toISOString()
  };
}
async function snapshot(repoRoot, resolution) {
  const scenarios = await readScenarios(repoRoot);
  const activeScenario = getActiveScenario(scenarios);
  const [activity, projects, assessment, dependencies, tasks, diagnostics, scenarioInstructions] = await Promise.all([
    readActivityTail(repoRoot),
    readProjects(repoRoot),
    readAssessment(activeScenario),
    readDependencyHealth(activeScenario),
    readTasks(repoRoot, activeScenario),
    buildDiagnostics(repoRoot, resolution, activeScenario),
    readScenarioInstructions(activeScenario)
  ]);
  const activityLog = resolveActivityLog(repoRoot);
  return {
    repoRoot,
    activitySources: existsSync(activityLog) ? [activityLog] : [],
    activeScenarioId: activeScenario?.id ?? null,
    activity,
    scenarios,
    projects,
    assessment,
    dependencies,
    tasks,
    diagnostics,
    scenarioInstructions,
    generatedAt: (/* @__PURE__ */ new Date()).toISOString()
  };
}
async function readScenarioInstructions(activeScenario) {
  if (!activeScenario?.scenarioPath) return null;
  const file = path2.join(activeScenario.scenarioPath, "scenario-instructions.md");
  if (!existsSync(file)) return null;
  try {
    return { path: file, content: await fs.readFile(file, "utf8") };
  } catch {
    return null;
  }
}
function resolveRepoRootFromDisk(startDir = process.cwd()) {
  if (process.env.UPGRADE_AGENT_DASHBOARD_REPO) {
    return { path: process.env.UPGRADE_AGENT_DASHBOARD_REPO, source: "UPGRADE_AGENT_DASHBOARD_REPO env var" };
  }
  let dir = startDir;
  while (true) {
    if (existsSync(path2.join(dir, ".git"))) {
      return { path: dir, source: `walked up from ${startDir} to .git` };
    }
    const parent = path2.dirname(dir);
    if (parent === dir) break;
    dir = parent;
  }
  dir = startDir;
  while (true) {
    if (existsSync(path2.join(dir, ".github", "upgrades", "scenarios"))) {
      return { path: dir, source: `walked up from ${startDir} to .github/upgrades/scenarios` };
    }
    const parent = path2.dirname(dir);
    if (parent === dir) break;
    dir = parent;
  }
  return { path: startDir, source: `process.cwd() fallback (no .git or .github/upgrades found): ${startDir}` };
}

// lib/server.ts
import http from "node:http";
import { execFile } from "node:child_process";
import { promises as fs2 } from "node:fs";
import path3 from "node:path";

// lib/state-hash.ts
function sortedKeysReplacer(_key, value) {
  if (value && typeof value === "object" && !Array.isArray(value)) {
    const sorted = {};
    for (const k of Object.keys(value).sort()) {
      sorted[k] = value[k];
    }
    return sorted;
  }
  return value;
}
function hashState(state) {
  const { generatedAt, diagnostics, ...rest } = state;
  const diagKey = diagnostics ? {
    paths: diagnostics.paths,
    resolutionSource: diagnostics.resolutionSource,
    resolvedRepoRoot: diagnostics.resolvedRepoRoot,
    gitKind: diagnostics.gitKind,
    gitDir: diagnostics.gitDir
  } : null;
  return JSON.stringify({ ...rest, diagnostics: diagKey }, sortedKeysReplacer);
}

// lib/server.ts
var STATIC_CONTENT_TYPES = /* @__PURE__ */ new Map([
  [".css", "text/css; charset=utf-8"],
  [".gif", "image/gif"],
  [".ico", "image/x-icon"],
  [".jpeg", "image/jpeg"],
  [".jpg", "image/jpeg"],
  [".js", "text/javascript; charset=utf-8"],
  [".json", "application/json; charset=utf-8"],
  [".png", "image/png"],
  [".svg", "image/svg+xml; charset=utf-8"],
  [".webp", "image/webp"]
]);
async function tryServeStaticAsset(staticRoot, pathname, res) {
  if (pathname === "/" || pathname === "/index.html" || pathname === "/events" || pathname === "/action" || pathname.startsWith("/api/")) {
    return false;
  }
  let decodedPath;
  try {
    decodedPath = decodeURIComponent(pathname);
  } catch {
    res.writeHead(400, { "content-type": "text/plain; charset=utf-8" });
    res.end("invalid path");
    return true;
  }
  const assetPath = path3.resolve(staticRoot, `.${decodedPath}`);
  const relativePath = path3.relative(staticRoot, assetPath);
  if (relativePath.startsWith("..") || path3.isAbsolute(relativePath)) {
    res.writeHead(404, { "content-type": "text/plain; charset=utf-8" });
    res.end("not found");
    return true;
  }
  try {
    const asset = await fs2.readFile(assetPath);
    const contentType = STATIC_CONTENT_TYPES.get(path3.extname(assetPath).toLowerCase()) ?? "application/octet-stream";
    res.writeHead(200, { "content-type": contentType });
    res.end(asset);
    return true;
  } catch (error) {
    if (error?.code === "ENOENT" || error?.code === "EISDIR") {
      return false;
    }
    throw error;
  }
}
var COMMIT_HASH_RE = /^[a-f0-9]{4,64}$/i;
function isValidCommitHash(value) {
  return COMMIT_HASH_RE.test(value);
}
function getCommitFiles(repoRoot, commitHash) {
  return new Promise((resolve, reject) => {
    if (!isValidCommitHash(commitHash)) {
      reject(new Error("invalid commit hash"));
      return;
    }
    execFile(
      "git",
      ["diff-tree", "--root", "--no-commit-id", "-r", "--numstat", "--diff-filter=ACDMRT", commitHash],
      { cwd: repoRoot, maxBuffer: 2 * 1024 * 1024 },
      (err, stdout) => {
        if (err) {
          reject(err);
          return;
        }
        const files = [];
        for (const line of stdout.trim().split("\n")) {
          if (!line.trim()) continue;
          const [added, removed, ...pathParts] = line.split("	");
          const filePath = pathParts.length > 1 ? pathParts[pathParts.length - 1] : pathParts[0];
          files.push({
            filePath,
            linesAdded: added === "-" ? 0 : parseInt(added, 10),
            linesRemoved: removed === "-" ? 0 : parseInt(removed, 10)
          });
        }
        resolve(files);
      }
    );
  });
}
function getCommitFileDiff(repoRoot, commitHash, filePath) {
  const gitPath = filePath.replace(/\\/g, "/");
  return new Promise((resolve, reject) => {
    if (!isValidCommitHash(commitHash)) {
      reject(new Error("invalid commit hash"));
      return;
    }
    execFile(
      "git",
      ["diff", `${commitHash}~1`, commitHash, "--", gitPath],
      { cwd: repoRoot, maxBuffer: 2 * 1024 * 1024 },
      (err, stdout) => {
        if (err) {
          execFile(
            "git",
            ["diff-tree", "--root", "-p", commitHash, "--", gitPath],
            { cwd: repoRoot, maxBuffer: 2 * 1024 * 1024 },
            (err2, stdout2) => {
              if (err2) {
                reject(err2);
                return;
              }
              resolve(stdout2 || "");
            }
          );
          return;
        }
        resolve(stdout || "");
      }
    );
  });
}
function createDashboardServer(options) {
  const {
    port = 0,
    host = "127.0.0.1",
    indexHtmlPath,
    getResolution,
    snapshot: snapshot2,
    getActionHandler,
    onTelemetry,
    pollIntervalMs = 5e3
  } = options;
  if (!indexHtmlPath) throw new Error("createDashboardServer: indexHtmlPath is required");
  if (typeof getResolution !== "function") throw new Error("createDashboardServer: getResolution is required");
  if (typeof snapshot2 !== "function") throw new Error("createDashboardServer: snapshot is required");
  if (typeof getActionHandler !== "function") throw new Error("createDashboardServer: getActionHandler is required");
  const staticRoot = path3.dirname(indexHtmlPath);
  const instanceMeta = /* @__PURE__ */ new Map();
  const instanceSubscribers = /* @__PURE__ */ new Map();
  function getInstanceMeta(instanceId) {
    let meta = instanceMeta.get(instanceId);
    if (!meta) {
      meta = { resolution: null, lastStateHash: null };
      instanceMeta.set(instanceId, meta);
    }
    return meta;
  }
  function getInstanceSubscribers(instanceId) {
    let subs = instanceSubscribers.get(instanceId);
    if (!subs) {
      subs = /* @__PURE__ */ new Set();
      instanceSubscribers.set(instanceId, subs);
    }
    return subs;
  }
  async function broadcastToInstance(instanceId, { force = false } = {}) {
    const subs = instanceSubscribers.get(instanceId);
    if (!subs || subs.size === 0) return;
    const meta = getInstanceMeta(instanceId);
    const resolution = meta.resolution ?? await getResolution(instanceId);
    if (!resolution) return;
    meta.resolution = resolution;
    const state = await snapshot2(resolution.path, resolution);
    const hash = hashState(state);
    if (!force && hash === meta.lastStateHash) return;
    meta.lastStateHash = hash;
    const payload = `data: ${JSON.stringify(state)}

`;
    for (const res of subs) {
      try {
        res.write(payload);
      } catch {
      }
    }
  }
  function sendEventToInstance(instanceId, event, data) {
    const subs = instanceSubscribers.get(instanceId);
    if (!subs || subs.size === 0) return false;
    const payload = `event: ${event}
data: ${JSON.stringify(data)}

`;
    let delivered = false;
    for (const res of subs) {
      try {
        res.write(payload);
        delivered = true;
      } catch {
      }
    }
    return delivered;
  }
  async function broadcastAll({ force = false } = {}) {
    for (const instanceId of instanceSubscribers.keys()) {
      try {
        await broadcastToInstance(instanceId, { force });
      } catch {
      }
    }
  }
  function closeInstance(instanceId) {
    const subs = instanceSubscribers.get(instanceId);
    if (subs) {
      for (const res of subs) {
        try {
          res.end();
        } catch {
        }
      }
      instanceSubscribers.delete(instanceId);
    }
    instanceMeta.delete(instanceId);
    if (instanceSubscribers.size === 0) stopPolling();
  }
  let pollTimer = null;
  function startPollingIfNeeded() {
    if (pollTimer) return;
    pollTimer = setInterval(() => {
      broadcastAll().catch(() => {
      });
    }, pollIntervalMs);
  }
  function stopPolling() {
    if (pollTimer) {
      clearInterval(pollTimer);
      pollTimer = null;
    }
  }
  async function handleRequest(req, res) {
    const url = new URL(req.url ?? "/", `http://${host}`);
    const instanceId = url.searchParams.get("instanceId") ?? "default";
    if (req.method === "GET" && (url.pathname === "/" || url.pathname === "/index.html")) {
      const html = await fs2.readFile(indexHtmlPath);
      res.writeHead(200, { "content-type": "text/html; charset=utf-8" });
      res.end(html);
      return;
    }
    if (req.method === "GET" && await tryServeStaticAsset(staticRoot, url.pathname, res)) {
      return;
    }
    if (req.method === "GET" && url.pathname === "/api/state") {
      const meta = getInstanceMeta(instanceId);
      const resolution = meta.resolution ?? await getResolution(instanceId);
      if (!resolution) {
        res.writeHead(503);
        res.end("repo not resolved");
        return;
      }
      meta.resolution = resolution;
      const state = await snapshot2(resolution.path, resolution);
      meta.lastStateHash = hashState(state);
      res.writeHead(200, { "content-type": "application/json; charset=utf-8" });
      res.end(JSON.stringify(state));
      return;
    }
    if (req.method === "GET" && url.pathname === "/api/diff") {
      const meta = getInstanceMeta(instanceId);
      const resolution = meta.resolution ?? await getResolution(instanceId);
      if (!resolution) {
        res.writeHead(503);
        res.end("repo not resolved");
        return;
      }
      meta.resolution = resolution;
      const filePath = url.searchParams.get("file");
      if (!filePath) {
        res.writeHead(400, { "content-type": "application/json" });
        res.end(JSON.stringify({ error: "file query parameter is required" }));
        return;
      }
      try {
        const diff = await getGitDiff(resolution.path, filePath);
        res.writeHead(200, { "content-type": "text/plain; charset=utf-8" });
        res.end(diff);
      } catch (err) {
        res.writeHead(500, { "content-type": "application/json" });
        res.end(JSON.stringify({ error: err.message }));
      }
      return;
    }
    if (req.method === "GET" && url.pathname === "/api/patch-file") {
      const meta = getInstanceMeta(instanceId);
      const resolution = meta.resolution ?? await getResolution(instanceId);
      if (!resolution) {
        res.writeHead(503);
        res.end("repo not resolved");
        return;
      }
      meta.resolution = resolution;
      const patchRef = url.searchParams.get("file");
      if (!patchRef) {
        res.writeHead(400, { "content-type": "application/json" });
        res.end(JSON.stringify({ error: "file query parameter is required" }));
        return;
      }
      const journalDir = activityLogDir(resolution.path);
      const abs = path3.resolve(journalDir, patchRef);
      const rel = path3.relative(journalDir, abs);
      if (rel.startsWith("..") || path3.isAbsolute(rel)) {
        res.writeHead(400, { "content-type": "application/json" });
        res.end(JSON.stringify({ error: "invalid patch file path" }));
        return;
      }
      try {
        const content = await fs2.readFile(abs, "utf8");
        res.writeHead(200, { "content-type": "text/plain; charset=utf-8" });
        res.end(content);
      } catch {
        res.writeHead(404, { "content-type": "application/json" });
        res.end(JSON.stringify({ error: "patch file not found" }));
      }
      return;
    }
    if (req.method === "GET" && url.pathname === "/api/commit-files") {
      const meta = getInstanceMeta(instanceId);
      const resolution = meta.resolution ?? await getResolution(instanceId);
      if (!resolution) {
        res.writeHead(503);
        res.end("repo not resolved");
        return;
      }
      meta.resolution = resolution;
      const commitHash = url.searchParams.get("commit");
      if (!commitHash) {
        res.writeHead(400, { "content-type": "application/json" });
        res.end(JSON.stringify({ error: "commit query parameter is required" }));
        return;
      }
      if (!isValidCommitHash(commitHash)) {
        res.writeHead(400, { "content-type": "application/json" });
        res.end(JSON.stringify({ error: "invalid commit hash" }));
        return;
      }
      try {
        const files = await getCommitFiles(resolution.path, commitHash);
        res.writeHead(200, { "content-type": "application/json; charset=utf-8" });
        res.end(JSON.stringify(files));
      } catch (err) {
        res.writeHead(500, { "content-type": "application/json" });
        res.end(JSON.stringify({ error: err.message }));
      }
      return;
    }
    if (req.method === "GET" && url.pathname === "/api/commit-diff") {
      const meta = getInstanceMeta(instanceId);
      const resolution = meta.resolution ?? await getResolution(instanceId);
      if (!resolution) {
        res.writeHead(503);
        res.end("repo not resolved");
        return;
      }
      meta.resolution = resolution;
      const commitHash = url.searchParams.get("commit");
      const filePath = url.searchParams.get("file");
      if (!commitHash || !filePath) {
        res.writeHead(400, { "content-type": "application/json" });
        res.end(JSON.stringify({ error: "commit and file query parameters are required" }));
        return;
      }
      if (!isValidCommitHash(commitHash)) {
        res.writeHead(400, { "content-type": "application/json" });
        res.end(JSON.stringify({ error: "invalid commit hash" }));
        return;
      }
      try {
        const diff = await getCommitFileDiff(resolution.path, commitHash, filePath);
        res.writeHead(200, { "content-type": "text/plain; charset=utf-8" });
        res.end(diff);
      } catch (err) {
        res.writeHead(500, { "content-type": "application/json" });
        res.end(JSON.stringify({ error: err.message }));
      }
      return;
    }
    if (req.method === "GET" && url.pathname === "/events") {
      res.writeHead(200, {
        "content-type": "text/event-stream",
        "cache-control": "no-cache",
        connection: "keep-alive"
      });
      res.write(": connected\n\n");
      const subs = getInstanceSubscribers(instanceId);
      subs.add(res);
      const keepalive = setInterval(() => {
        try {
          res.write(": ping\n\n");
        } catch {
        }
      }, 2e4);
      const cleanup = () => {
        clearInterval(keepalive);
        subs.delete(res);
      };
      req.on("close", cleanup);
      res.on("close", cleanup);
      const meta = getInstanceMeta(instanceId);
      const resolution = meta.resolution ?? await getResolution(instanceId);
      if (resolution) {
        meta.resolution = resolution;
        const state = await snapshot2(resolution.path, resolution);
        meta.lastStateHash = hashState(state);
        try {
          res.write(`data: ${JSON.stringify(state)}

`);
        } catch {
        }
      }
      startPollingIfNeeded();
      return;
    }
    if (req.method === "POST" && url.pathname === "/action") {
      let body = "";
      req.on("data", (chunk) => {
        body += chunk;
      });
      req.on("end", async () => {
        try {
          const payload = JSON.parse(body || "{}");
          const actionName = typeof payload.actionName === "string" ? payload.actionName : "";
          const handler = getActionHandler(actionName);
          if (!handler) {
            res.writeHead(404, { "content-type": "application/json" });
            res.end(JSON.stringify({ error: `Unknown action: ${actionName}` }));
            return;
          }
          const ctx = {
            sessionId: "",
            extensionId: "",
            canvasId: "dashboard",
            instanceId: typeof payload.instanceId === "string" ? payload.instanceId : instanceId,
            actionName,
            input: payload.input,
            broadcastToInstance
          };
          const result = await handler(ctx);
          const meta = getInstanceMeta(ctx.instanceId);
          const resolution = meta.resolution ?? await getResolution(ctx.instanceId);
          if (resolution) {
            meta.resolution = resolution;
            const state = await snapshot2(resolution.path, resolution);
            meta.lastStateHash = hashState(state);
            res.writeHead(200, { "content-type": "application/json" });
            res.end(JSON.stringify({ result, state }));
          } else {
            res.writeHead(200, { "content-type": "application/json" });
            res.end(JSON.stringify({ result, state: null }));
          }
        } catch (err) {
          res.writeHead(400, { "content-type": "application/json" });
          res.end(JSON.stringify({ error: err instanceof Error ? err.message : "Unknown error" }));
        }
      });
      return;
    }
    if (req.method === "POST" && url.pathname === "/telemetry") {
      let body = "";
      let overflow = false;
      req.on("data", (chunk) => {
        if (overflow) return;
        body += chunk;
        if (body.length > 10240) {
          overflow = true;
          res.writeHead(413);
          res.end();
        }
      });
      req.on("end", () => {
        if (overflow) return;
        try {
          const payload = JSON.parse(body || "{}");
          if (typeof onTelemetry === "function") onTelemetry(payload);
        } catch {
        }
        res.writeHead(204);
        res.end();
      });
      return;
    }
    res.writeHead(404);
    res.end("not found");
  }
  const server = http.createServer((req, res) => {
    handleRequest(req, res).catch((err) => {
      try {
        res.writeHead(500);
        res.end(err?.message ?? "internal error");
      } catch {
      }
    });
  });
  return {
    server,
    broadcastAll,
    broadcastToInstance,
    sendEventToInstance,
    closeInstance,
    stopPolling,
    async listen() {
      await new Promise((resolve) => server.listen(port, host, resolve));
      const addr = server.address();
      const resolvedPort = typeof addr === "object" && addr ? addr.port : port;
      return {
        port: resolvedPort,
        url: `http://${host}:${resolvedPort}`
      };
    },
    async close() {
      stopPolling();
      for (const subs of instanceSubscribers.values()) {
        for (const res of subs) {
          try {
            res.end();
          } catch {
          }
        }
      }
      instanceSubscribers.clear();
      instanceMeta.clear();
      await new Promise((resolve) => server.close(() => resolve()));
    }
  };
}
function getGitDiff(repoRoot, filePath) {
  return new Promise((resolve, reject) => {
    execFile("git", ["diff", "HEAD", "--", filePath], { cwd: repoRoot, maxBuffer: 1024 * 1024 }, (err, stdout, stderr) => {
      if (err) {
        execFile("git", ["diff", "--", filePath], { cwd: repoRoot, maxBuffer: 1024 * 1024 }, (err2, stdout2) => {
          if (err2) {
            reject(new Error(stderr || err2.message));
          } else {
            resolve(stdout2);
          }
        });
      } else {
        resolve(stdout);
      }
    });
  });
}

// lib/canvas-path.ts
import path4 from "node:path";
import { fileURLToPath } from "node:url";
var entryDirectories = /* @__PURE__ */ new Set(["bin", "dist"]);
function resolveCanvasIndexHtml(moduleUrl) {
  const moduleDirectory = path4.dirname(fileURLToPath(moduleUrl));
  const extensionRoot = entryDirectories.has(path4.basename(moduleDirectory)) ? path4.dirname(moduleDirectory) : moduleDirectory;
  return path4.join(extensionRoot, "canvas", "app", "index.html");
}

// extension.ts
var INDEX_HTML_PATH = resolveCanvasIndexHtml(import.meta.url);
var VALID_PANELS = /* @__PURE__ */ new Set([
  "overview",
  "activity",
  "scenario",
  "projects",
  "assessment",
  "dependencies",
  "tasks",
  "options",
  "diagnostics"
]);
function resolveRepo(workingDirectory) {
  if (process.env.UPGRADE_AGENT_DASHBOARD_REPO) {
    return { path: process.env.UPGRADE_AGENT_DASHBOARD_REPO, source: "UPGRADE_AGENT_DASHBOARD_REPO env var", confident: true };
  }
  if (workingDirectory && existsSync2(workingDirectory)) {
    return { path: workingDirectory, source: "session.workingDirectory", confident: true };
  }
  return { ...resolveRepoRootFromDisk(), confident: false };
}
var session = null;
var resolvedRepo = null;
async function ensureResolvedRepo(workingDirectory) {
  if (resolvedRepo?.confident) {
    return resolvedRepo;
  }
  const next = resolveRepo(workingDirectory);
  if (next.confident || !resolvedRepo) {
    resolvedRepo = next;
  }
  return resolvedRepo;
}
function requireSession() {
  if (!session) {
    throw new CanvasError(
      "session_unavailable",
      "Copilot session is not yet available; try again shortly."
    );
  }
  return session;
}
function requireSendSession() {
  const currentSession = requireSession();
  if (typeof currentSession.send !== "function") {
    throw new CanvasError(
      "session_send_unavailable",
      "This Copilot CLI build does not expose session.send; agent-relay actions are unavailable."
    );
  }
  return currentSession;
}
var actionHandlers = /* @__PURE__ */ new Map();
async function getSnapshotForResolution(context) {
  const resolution = await ensureResolvedRepo(context.session?.workingDirectory);
  return await snapshot(resolution.path, resolution);
}
actionHandlers.set("refresh", async ({ instanceId }) => {
  await dashboardServer.broadcastToInstance(instanceId, { force: true });
  return { ok: true, generatedAt: (/* @__PURE__ */ new Date()).toISOString() };
});
actionHandlers.set("set_panel", async ({ instanceId, input }) => {
  const panel = input?.panel;
  if (typeof panel !== "string" || !VALID_PANELS.has(panel)) {
    throw new CanvasError("canvas_invalid_panel", `Unknown panel: ${panel}`);
  }
  const delivered = dashboardServer.sendEventToInstance(instanceId, "panel", { panel });
  if (!delivered) {
    throw new CanvasError(
      "canvas_not_connected",
      "The dashboard canvas is not currently connected; open it before switching panels."
    );
  }
  return { ok: true, panel };
});
actionHandlers.set("switch_mode", async ({ input }) => {
  const currentSession = requireSendSession();
  const mode = input?.mode;
  if (mode !== "guided" && mode !== "automatic") {
    throw new CanvasError("invalid_mode", "mode must be 'guided' or 'automatic'.");
  }
  await currentSession.send(
    `Please switch the upgrade mode to ${mode}. (Requested from the Upgrade Agent Dashboard canvas.)`
  );
  return { ok: true, status: `Asked the agent to switch to ${mode} mode.` };
});
actionHandlers.set("share_assessment_as_gist", async (context) => {
  const currentSession = requireSendSession();
  const state = await getSnapshotForResolution(context);
  const assessment = state.assessment;
  if (!assessment?.path) {
    throw new CanvasError(
      "no_assessment",
      "No assessment.json detected for the current scenario \u2014 nothing to share."
    );
  }
  if (!existsSync2(assessment.path)) {
    throw new CanvasError(
      "assessment_missing_on_disk",
      `assessment.json was indexed at ${assessment.path} but is no longer on disk.`
    );
  }
  await currentSession.send(
    `Create a *private* GitHub gist from the upgrade assessment at \`${assessment.path}\`. Use the gh CLI: \`gh gist create --private --filename assessment.json '${assessment.path}'\`. Report the resulting gist URL back when done. (Requested from the Upgrade Agent Dashboard canvas.)`
  );
  return { ok: true, assessmentPath: assessment.path };
});
actionHandlers.set("explain_dependency", async (context) => {
  const currentSession = requireSendSession();
  const packageName = (context.input?.packageName ?? "").toString().trim();
  if (!packageName) {
    throw new CanvasError("invalid_package", "packageName is required.");
  }
  const state = await getSnapshotForResolution(context);
  const dependency = state.dependencies?.packages?.find((candidate) => candidate.name === packageName);
  const targetFramework = state.dependencies?.targetFramework ?? "(unknown)";
  const compatibility = dependency?.isCompatible === false ? "incompatible" : dependency?.isCompatible === true ? "compatible" : "unknown";
  const recommendation = dependency?.recommendedVersion ? ` Recommended version: ${dependency.recommendedVersion}.` : "";
  await currentSession.send(
    `Explain why the NuGet package \`${packageName}\` is reported as ${compatibility} for target framework \`${targetFramework}\` in the upgrade dependency report.${recommendation} Suggest concrete steps to upgrade or replace it. (Requested from the Upgrade Agent Dashboard canvas.)`
  );
  return { ok: true, status: `Asked the agent to explain ${packageName}.` };
});
actionHandlers.set("push_context", async (context) => {
  const currentSession = requireSession();
  const api = currentSession.rpc?.extensions?.sendAttachmentsToMessage;
  if (typeof api !== "function") {
    throw new CanvasError(
      "unsupported_runtime",
      "This Copilot CLI build does not expose session.extensions.sendAttachmentsToMessage; update the CLI to push dashboard context."
    );
  }
  const state = await getSnapshotForResolution(context);
  const activeScenario = Array.isArray(state.scenarios) ? state.scenarios.find((candidate) => candidate?.id === state.activeScenarioId) ?? null : null;
  let taskSummary = null;
  if (state.tasks && Array.isArray(state.tasks.tasks)) {
    const counts = { complete: 0, inProgress: 0, notStarted: 0, skipped: 0, failed: 0 };
    const countKeys = {
      Complete: "complete",
      InProgress: "inProgress",
      NotStarted: "notStarted",
      Skipped: "skipped",
      Failed: "failed"
    };
    for (const task of state.tasks.tasks) {
      const countKey = typeof task.state === "string" ? countKeys[task.state] ?? "notStarted" : "notStarted";
      counts[countKey] += 1;
    }
    taskSummary = { total: state.tasks.tasks.length, ...counts };
  }
  const payload = {
    capturedAt: (/* @__PURE__ */ new Date()).toISOString(),
    repoRoot: state.repoRoot,
    activeScenarioId: state.activeScenarioId,
    scenario: activeScenario ? {
      id: activeScenario.id,
      description: typeof activeScenario.description === "string" ? activeScenario.description : null,
      targetFramework: activeScenario.properties?.UpgradeTargetFramework ?? activeScenario.properties?.upgradeTargetFramework ?? null
    } : null,
    assessment: state.assessment ? { path: state.assessment.path, counts: state.assessment.counts, severity: state.assessment.severity } : null,
    dependencies: state.dependencies ? { targetFramework: state.dependencies.targetFramework, counts: state.dependencies.counts } : null,
    tasks: taskSummary
  };
  await api.call(currentSession.rpc?.extensions, {
    attachments: [{
      type: "extension_context",
      title: `Upgrade Agent Dashboard \xB7 ${state.activeScenarioId ?? "no active scenario"}`,
      payload
    }],
    instanceId: context.instanceId
  });
  return { ok: true, status: "Pushed the current upgrade dashboard context to the chat." };
});
var dashboardServer = createDashboardServer({
  indexHtmlPath: INDEX_HTML_PATH,
  getResolution: async () => ensureResolvedRepo(),
  snapshot,
  getActionHandler: (name) => actionHandlers.get(name) ?? null,
  onTelemetry: (payload) => {
    if (payload?.event !== "dashboard/tab_click") return;
    const panel = payload?.properties?.panel;
    if (typeof panel !== "string" || !VALID_PANELS.has(panel)) return;
    if (!resolvedRepo?.path) return;
    const directory = activityLogDir(resolvedRepo.path);
    const file = path5.join(directory, "canvas-telemetry.jsonl");
    const record = { event: "dashboard/tab_click", properties: { panel }, timestamp: (/* @__PURE__ */ new Date()).toISOString() };
    mkdir(directory, { recursive: true }).then(() => appendFile(file, `${JSON.stringify(record)}
`)).catch(() => {
    });
  }
});
var { url: baseUrl } = await dashboardServer.listen();
var canvas = createCanvas({
  id: "dashboard",
  displayName: "Upgrade Agent Dashboard",
  description: "Read-only view of the .NET upgrade artifacts for the current workspace: an Overview landing, plus Activity log, Tasks, Scenario, Projects (table + dependency graph), Dependency health, and Assessment (with incident grouping). Also exposes actions to switch execution mode, share the assessment, and explain dependency issues.",
  actions: [
    {
      name: "refresh",
      description: "Reload artifact state from disk and push it to the canvas.",
      inputSchema: { type: "object", additionalProperties: false },
      handler: (context) => actionHandlers.get("refresh")(context)
    },
    {
      name: "set_panel",
      description: "Switch the visible panel inside the canvas.",
      inputSchema: {
        type: "object",
        properties: { panel: { type: "string", enum: [...VALID_PANELS] } },
        required: ["panel"],
        additionalProperties: false
      },
      handler: (context) => actionHandlers.get("set_panel")(context)
    },
    {
      name: "switch_mode",
      description: "Ask the agent to switch the upgrade execution mode between Guided and Automatic.",
      inputSchema: {
        type: "object",
        properties: { mode: { type: "string", enum: ["guided", "automatic"] } },
        required: ["mode"],
        additionalProperties: false
      },
      handler: (context) => actionHandlers.get("switch_mode")(context)
    },
    {
      name: "share_assessment_as_gist",
      description: "Ask the agent to create a private GitHub gist from the current scenario's assessment.json.",
      inputSchema: { type: "object", additionalProperties: false },
      handler: (context) => actionHandlers.get("share_assessment_as_gist")(context)
    },
    {
      name: "explain_dependency",
      description: "Ask the agent to explain why a NuGet package is flagged in the dependency report and suggest an upgrade path.",
      inputSchema: {
        type: "object",
        properties: { packageName: { type: "string" } },
        required: ["packageName"],
        additionalProperties: false
      },
      handler: (context) => actionHandlers.get("explain_dependency")(context)
    },
    {
      name: "push_context",
      description: "Push a structured snapshot of the current upgrade dashboard state (scenario, assessment, dependency, and task summary) into the chat as context for the next message.",
      inputSchema: { type: "object", additionalProperties: false },
      handler: (context) => actionHandlers.get("push_context")(context)
    }
  ],
  async open(context) {
    const { instanceId, input } = context;
    await ensureResolvedRepo(context.session?.workingDirectory);
    const initialPanel = typeof input?.panel === "string" && VALID_PANELS.has(input.panel) ? input.panel : "overview";
    const url = `${baseUrl}/?instanceId=${encodeURIComponent(instanceId)}&panel=${encodeURIComponent(initialPanel)}`;
    return { url, title: "Upgrade Agent Dashboard", status: "open" };
  },
  onClose({ instanceId }) {
    dashboardServer.closeInstance(instanceId);
  }
});
session = await joinSession({ canvases: [canvas] });
