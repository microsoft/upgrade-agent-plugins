// extension.ts
import { existsSync as existsSync2 } from "node:fs";
import { appendFile, mkdir } from "node:fs/promises";
import path8 from "node:path";
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

// lib/commit-message.ts
var NEWLINE = /\r\n|\r|\n/;
function messageLines(message) {
  return typeof message === "string" ? message.split(NEWLINE) : [];
}
function subjectIndex(lines) {
  return lines.findIndex((line) => line.trim() !== "");
}
function commitSubject(message) {
  const lines = messageLines(message);
  const index = subjectIndex(lines);
  return index === -1 ? "" : lines[index].trim();
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
  build_started: { label: "Build started", kind: "build" },
  build_completed: { label: "Build completed", kind: "build" },
  build_session_completed: { label: "Build session completed", kind: "build" },
  phase_entered: { label: "Phase entered", kind: "phase" },
  branch_changed: { label: "Branch changed", kind: "branch" },
  head_detached: { label: "HEAD detached", kind: "branch" },
  scenario_started: { label: "Scenario started", kind: "scenario" },
  scenario_completed: { label: "Scenario completed", kind: "scenario" },
  settings_changed: { label: "Settings changed", kind: "system" },
  provider_started: { label: "Provider started", kind: "system" },
  provider_stopped: { label: "Provider stopped", kind: "system" }
};
var SYSTEM_ACTIVITY_KIND = "system";
function isRecord(value) {
  return typeof value === "object" && value !== null;
}
function isUnknownArray(value) {
  return Array.isArray(value);
}
function stringOrNull(value) {
  return typeof value === "string" ? value : null;
}
function numberOrNull(value) {
  return typeof value === "number" ? value : null;
}
function booleanOrNull(value) {
  return typeof value === "boolean" ? value : null;
}
function timestampOrNull(value) {
  if (typeof value === "string" || typeof value === "number" || value instanceof Date) {
    return value;
  }
  return null;
}
function toBuildProjectResult(value) {
  const record = isRecord(value) ? value : {};
  return {
    ...record,
    projectPath: stringOrNull(record.projectPath),
    succeeded: booleanOrNull(record.succeeded),
    durationMs: numberOrNull(record.durationMs)
  };
}
function humanizeEventName(eventName) {
  if (typeof eventName !== "string" || eventName.length === 0) return "Unknown";
  const words = eventName.split(/[_\-.]+/).filter(Boolean);
  if (words.length === 0) return eventName;
  return words.join(" ").replace(/^./, (c) => c.toUpperCase());
}
function formatActivityEntry(raw) {
  const row = isRecord(raw) ? raw : {};
  const payload = isRecord(row.payload) ? row.payload : null;
  const fields = payload ? { ...row, ...payload } : row;
  const ts = fields.timestamp ?? fields.ts ?? fields.time ?? null;
  const rawEvent = fields.event ?? fields.type;
  const eventName = typeof rawEvent === "string" ? rawEvent : "unknown";
  const meta = ACTIVITY_EVENT_LABELS[eventName] ?? { label: humanizeEventName(eventName), kind: "other" };
  const detail = buildActivityDetail(eventName, fields);
  const entry = {
    seq: numberOrNull(row.seq ?? fields.seq),
    timestamp: timestampOrNull(ts),
    event: eventName,
    label: meta.label,
    kind: meta.kind,
    taskId: stringOrNull(fields.taskId ?? fields.task_id),
    detail
  };
  if (meta.kind === "file") {
    entry.filePath = stringOrNull(fields.path ?? fields.filePath);
    entry.linesAdded = numberOrNull(fields.linesAdded ?? fields.lines_added);
    entry.linesRemoved = numberOrNull(fields.linesRemoved ?? fields.lines_removed);
    entry.patchFile = stringOrNull(fields.patchFile ?? fields.patch_file);
  }
  if (meta.kind === "commit") {
    entry.commitHash = stringOrNull(fields.commitHash ?? fields.hash);
    entry.commitMessage = stringOrNull(fields.commitMessage ?? fields.message);
    entry.commitFiles = fields.files ?? null;
    entry.insertions = numberOrNull(fields.insertions);
    entry.deletions = numberOrNull(fields.deletions);
  }
  if (meta.kind === "build") {
    entry.succeeded = booleanOrNull(fields.succeeded);
    entry.durationMs = numberOrNull(fields.durationMs ?? fields.duration);
    entry.succeededProjects = numberOrNull(fields.succeededProjects);
    entry.projectResults = isUnknownArray(fields.projectResults) ? fields.projectResults.map(toBuildProjectResult) : null;
    entry.command = stringOrNull(fields.command);
    entry.buildSucceeded = readBuildSucceeded(eventName, fields);
    entry.errorCount = numberOrNull(fields.errorCount ?? fields.errors);
    entry.warningCount = numberOrNull(fields.warningCount ?? fields.warnings);
    entry.totalProjects = numberOrNull(fields.totalProjects ?? fields.total);
    entry.failedProjects = numberOrNull(fields.failedProjects);
  }
  if (meta.kind === "phase") {
    entry.phase = stringOrNull(fields.phase ?? fields.name);
  }
  if (meta.kind === "branch") {
    entry.oldBranch = stringOrNull(fields.oldBranch ?? fields.from);
    entry.newBranch = stringOrNull(fields.newBranch ?? fields.to);
  }
  if (meta.kind === SYSTEM_ACTIVITY_KIND) {
    entry.providerId = stringOrNull(fields.providerId ?? fields.provider);
  }
  return entry;
}
function readBuildSucceeded(eventName, e) {
  if (eventName === "build_started") return null;
  if (typeof e.succeeded === "boolean") return e.succeeded;
  return (e.errorCount ?? e.errors ?? 0) === 0 && (e.failedProjects ?? 0) === 0;
}
function buildOutcomeLabel(eventName, e) {
  const succeeded = readBuildSucceeded(eventName, e);
  if (succeeded === true) return "succeeded";
  if (succeeded === false) return "failed";
  return "completed";
}
function buildActivityDetail(eventName, e) {
  switch (eventName) {
    case "task_started":
    case "task_completed":
    case "task_failed": {
      const parts = [];
      const name = e.displayName ?? e.taskName ?? e.name;
      if (name) parts.push(String(name));
      else if (e.taskId) parts.push(String(e.taskId));
      if (e.reason) parts.push(`\u2014 ${String(e.reason)}`);
      return parts.join(" ");
    }
    case "file_modified":
    case "file_created":
    case "file_deleted":
    case "file_renamed": {
      const p = String(e.path ?? e.filePath ?? "");
      const adds = e.linesAdded ?? e.lines_added;
      const dels = e.linesRemoved ?? e.lines_removed;
      let suffix = "";
      if (adds != null || dels != null) {
        suffix = ` (+${String(adds ?? 0)} / -${String(dels ?? 0)})`;
      }
      return `${p}${suffix}`;
    }
    case "commit_created":
    case "commit_amended": {
      const hash = String(e.commitHash ?? e.hash ?? "").slice(0, 7);
      const msg = commitSubject(String(e.commitMessage ?? e.message ?? ""));
      return hash ? `${hash} ${msg}` : msg;
    }
    case "build_started": {
      const project = e.project ?? e.projectName ?? e.projectPath ?? e.path;
      const total = e.totalProjects ?? e.total ?? null;
      if (project) {
        const config = e.configuration ?? e.config;
        return config ? `${String(project)} (${String(config)})` : String(project);
      }
      if (total != null) {
        return `${String(total)} project${total === 1 ? "" : "s"}`;
      }
      return "";
    }
    case "build_completed": {
      const errs = e.errorCount ?? e.errors ?? null;
      const warns = e.warningCount ?? e.warnings ?? null;
      const total = e.totalProjects ?? e.total ?? null;
      const tail = total != null ? ` across ${String(total)} project${total === 1 ? "" : "s"}` : "";
      const counts = [];
      if (errs != null) counts.push(`${String(errs)} error${errs === 1 ? "" : "s"}`);
      if (warns != null) counts.push(`${String(warns)} warning${warns === 1 ? "" : "s"}`);
      const tally = counts.length > 0 ? ` \u2014 ${counts.join(", ")}` : "";
      return `${buildOutcomeLabel(eventName, e)}${tally}${tail}`;
    }
    case "build_session_completed": {
      const total = e.totalProjects ?? null;
      const succeeded = e.succeededProjects ?? null;
      const failed = e.failedProjects ?? 0;
      const tally = total != null ? ` (${String(succeeded ?? 0)}/${String(total)} ok${failed ? `, ${String(failed)} failed` : ""})` : failed ? ` \u2014 ${String(failed)} failed` : "";
      return `${buildOutcomeLabel(eventName, e)}${tally}`;
    }
    case "phase_entered": {
      return String(e.phase ?? e.name ?? "");
    }
    case "branch_changed": {
      const from = String(e.oldBranch ?? e.from ?? "?");
      const to = String(e.newBranch ?? e.to ?? "?");
      return `${from} \u2192 ${to}`;
    }
    case "head_detached": {
      const at = String(e.commitHash ?? e.hash ?? e.sha ?? "").slice(0, 7);
      const from = e.oldBranch ?? e.previousBranch ?? e.from;
      const parts = [];
      if (from) parts.push(`${String(from)} \u2192`);
      parts.push(at ? `detached at ${at}` : "detached HEAD");
      return parts.join(" ");
    }
    case "scenario_started": {
      const parts = [];
      if (e.scenarioId) parts.push(String(e.scenarioId));
      const source = e.sourceFramework;
      const target = e.targetFramework;
      if (source || target) parts.push(`${String(source ?? "?")} \u2192 ${String(target ?? "?")}`);
      const opts = [e.mode, e.strategy].filter(Boolean);
      if (opts.length > 0) parts.push(`(${opts.join(", ")})`);
      return parts.join(" ");
    }
    case "scenario_completed": {
      const parts = [];
      if (e.status) parts.push(String(e.status));
      const total = e.totalTasks ?? null;
      if (total != null) {
        const done = e.completed ?? 0;
        const tally = [`${String(done)}/${String(total)} tasks`];
        if (e.failed) tally.push(`${String(e.failed)} failed`);
        if (e.skipped) tally.push(`${String(e.skipped)} skipped`);
        parts.push(`\u2014 ${tally.join(", ")}`);
      }
      const commits = e.totalCommits;
      const files = e.totalFilesChanged;
      if (commits != null || files != null) {
        parts.push(`(${String(commits ?? 0)} commit${commits === 1 ? "" : "s"}, ${String(files ?? 0)} file${files === 1 ? "" : "s"})`);
      }
      return parts.join(" ");
    }
    case "settings_changed": {
      const key = e.key ?? e.setting ?? e.name;
      if (!key) {
        const keys = e.keys ?? e.changed;
        return isUnknownArray(keys) ? keys.join(", ") : "";
      }
      const from = e.oldValue ?? e.previousValue;
      const to = e.newValue ?? e.value;
      if (from === void 0 && to === void 0) return String(key);
      return `${String(key)}: ${formatScalar(from)} \u2192 ${formatScalar(to)}`;
    }
    case "provider_started": {
      const id = e.providerId ?? e.provider ?? e.id ?? "provider";
      const pid = e.pid ?? e.processId;
      return pid != null ? `${String(id)} (pid ${String(pid)})` : String(id);
    }
    case "provider_stopped": {
      const id = e.providerId ?? e.provider ?? e.id ?? "provider";
      const reason = e.reason ?? (e.exitCode != null ? `exit ${String(e.exitCode)}` : null);
      return reason ? `${String(id)} \u2014 ${String(reason)}` : String(id);
    }
    default: {
      const {
        timestamp,
        ts,
        time,
        event,
        type,
        taskId,
        task_id,
        seq,
        provider,
        payload,
        correlationId,
        ...rest
      } = e;
      const keys = Object.keys(rest);
      if (keys.length === 0) return "";
      return keys.map((k) => `${k}=${formatScalar(rest[k])}`).join(" ");
    }
  }
}
function formatScalar(v) {
  if (v == null) return "";
  if (typeof v === "string") return v;
  if (typeof v === "number" || typeof v === "boolean") return String(v);
  return JSON.stringify(v) ?? "";
}

// lib/time-format.ts
var SECOND = 1e3;
var MINUTE = 60 * SECOND;
var HOUR = 60 * MINUTE;
var DAY = 24 * HOUR;
var WEEK = 7 * DAY;
var YEAR = 365 * DAY;
var MONTH = YEAR / 12;
var MAX_TIME = 864e13;
function parseTimestamp(timestamp) {
  if (timestamp === null || timestamp === void 0 || timestamp === "") {
    return NaN;
  }
  if (timestamp instanceof Date) {
    return timestamp.getTime();
  }
  if (typeof timestamp === "number") {
    return Number.isFinite(timestamp) && Math.abs(timestamp) <= MAX_TIME ? timestamp : NaN;
  }
  return Date.parse(String(timestamp));
}
function toIsoTimestamp(timestamp) {
  const parsed = parseTimestamp(timestamp);
  return Number.isNaN(parsed) ? null : new Date(parsed).toISOString();
}
function compareInstants(left, right, sign) {
  const a = parseTimestamp(left);
  const b = parseTimestamp(right);
  if (!Number.isNaN(a) && !Number.isNaN(b)) {
    return a === b ? 0 : sign * (a - b);
  }
  if (!Number.isNaN(a)) {
    return -1;
  }
  if (!Number.isNaN(b)) {
    return 1;
  }
  return 0;
}
function compareNewestFirst(left, right) {
  return compareInstants(left, right, -1);
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
      if (/\*\*Progress\*\*/i.test(line) || /<progress/i.test(line) || /\*\*Status\*\*/i.test(line)) {
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
    const path9 = m[1].trim();
    if (path9) out.push(path9);
  }
  return out;
}

// lib/deps.ts
function isRecord2(value) {
  return typeof value === "object" && value !== null;
}
function pick(obj, ...names) {
  if (!isRecord2(obj)) return void 0;
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
      if (typeof c === "string" && INCOMPAT_VALUES.has(c)) {
        count++;
      }
    }
  }
  return count;
}

// lib/paths.ts
function normalizePathSeparators(p) {
  if (typeof p !== "string" || p === "") {
    return "";
  }
  const slashed = p.replace(/\\/g, "/");
  return slashed.length > 1 ? slashed.replace(/\/+$/, "") : slashed;
}
function projectNameFromPath(p) {
  if (typeof p !== "string" || !p) {
    return "(unknown project)";
  }
  const base = normalizePathSeparators(p).split("/").pop() ?? "";
  return base.replace(/\.[a-z]+proj$/i, "");
}
function isAgentArtifactPath(p) {
  const normalized = normalizePathSeparators(p).toLowerCase();
  if (normalized === "") {
    return false;
  }
  return normalized.includes(".github/upgrades/") || normalized.endsWith(".github/upgrades");
}

// lib/assessment.ts
function isRecord3(value) {
  return typeof value === "object" && value !== null;
}
function aggregateFeatures(projects) {
  if (!Array.isArray(projects)) {
    return [];
  }
  const map = /* @__PURE__ */ new Map();
  for (const proj of projects) {
    if (!isRecord3(proj)) {
      continue;
    }
    const projFeatures = Array.isArray(proj.features) ? proj.features : [];
    const projPath = typeof proj.path === "string" ? proj.path : "";
    const properties = isRecord3(proj.properties) ? proj.properties : {};
    const appName = properties.appName ?? properties.AppName;
    const projName = typeof appName === "string" && appName ? appName : projectNameFromPath(projPath);
    for (const f of projFeatures) {
      if (!isRecord3(f) || typeof f.featureId !== "string") {
        continue;
      }
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
function isRecord4(value) {
  return typeof value === "object" && value !== null;
}
function isUnknownArray2(value) {
  return Array.isArray(value);
}
function recordOrEmpty(value) {
  return isRecord4(value) ? value : {};
}
function unvalidatedList(value) {
  return value;
}
function unvalidatedRecord(value) {
  return value;
}
function unvalidatedString(value) {
  return value;
}
function unvalidatedNumber(value) {
  return value;
}
var ACTIVITY_TAIL_LIMIT = 1e3;
async function readActivityTail(repoRoot, maxLines = ACTIVITY_TAIL_LIMIT) {
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
          entries.push({ event: "unparseable", label: "unparseable", kind: "other", detail: line, seq: null, timestamp: null, taskId: null });
        }
      }
    } catch {
    }
  }
  entries.sort((a, b) => compareNewestFirst(a.timestamp, b.timestamp));
  return {
    entries: entries.slice(0, maxLines),
    truncated: entries.length > maxLines
  };
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
      body = unvalidatedRecord(JSON.parse(await fs.readFile(path2.join(scenarioPath, "scenario.json"), "utf8")));
    } catch {
      body = { error: "could not read scenario.json" };
    }
    scenarios.push({ id: entry.name, scenarioPath, mtime, ...body });
  }
  scenarios.sort((a, b) => (unvalidatedNumber(b.mtime) ?? 0) - (unvalidatedNumber(a.mtime) ?? 0));
  return scenarios;
}
function getActiveScenario(scenarios) {
  return scenarios.length > 0 ? scenarios[0] : null;
}
async function readProjects(repoRoot) {
  const projects = [];
  const walkedDirs = /* @__PURE__ */ new Set();
  const projectFiles = /* @__PURE__ */ new Set();
  const preReadStats = /* @__PURE__ */ new Map();
  const MAX_PROJECTS = 500;
  async function walk(dir) {
    if (projects.length >= MAX_PROJECTS) return;
    walkedDirs.add(dir);
    preReadStats.set(dir, await _statToken(dir));
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
      projectFiles.add(full);
      preReadStats.set(full, await _statToken(full));
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
  return { projects, walkedDirs: [...walkedDirs], projectFiles: [...projectFiles], preReadStats };
}
function findAssessmentJson(activeScenario) {
  if (!activeScenario?.scenarioPath) return null;
  const file = path2.join(unvalidatedString(activeScenario.scenarioPath), "assessment.json");
  return existsSync(file) ? file : null;
}
async function readAssessment(activeScenario) {
  const file = findAssessmentJson(activeScenario);
  if (!file) return null;
  try {
    const data = JSON.parse(await fs.readFile(file, "utf8"));
    if (data === null || data === void 0) throw new TypeError("assessment.json is not an object");
    const record = recordOrEmpty(data);
    const stats = recordOrEmpty(record.stats);
    const summary = recordOrEmpty(stats.summary);
    const charts = recordOrEmpty(stats.charts);
    const projects = isUnknownArray2(record.projects) ? record.projects : [];
    const features = aggregateFeatures(projects);
    return {
      path: file,
      settings: record.settings ?? null,
      analysisStartTime: record.analysisStartTime ?? null,
      analysisEndTime: record.analysisEndTime ?? null,
      counts: {
        projects: summary.projects ?? projects.length,
        issues: summary.issues ?? 0,
        incidents: summary.incidents ?? 0,
        effort: summary.effort ?? 0,
        mandatory: recordOrEmpty(charts.severity).Mandatory ?? 0
      },
      severity: charts.severity ?? {},
      category: charts.category ?? {},
      features,
      projects: projects.filter((p) => isRecord4(p)).map((p) => {
        const props = recordOrEmpty(p.properties);
        return {
          path: p.path,
          startingProject: !!p.startingProject,
          issues: p.issues ?? 0,
          storyPoints: p.storyPoints ?? 0,
          appName: props.appName ?? null,
          frameworks: props.frameworks ?? [],
          projectKind: props.projectKind ?? null,
          isSdk: !!props.isSdkStyle,
          // Sizing metrics surfaced by the Assessment "Highlevel metrics"
          // block (camelCase in the canonical producer's assessment.json).
          numberOfCodeFiles: props.numberOfCodeFiles ?? 0,
          linesOfCode: props.linesOfCode ?? 0,
          minLinesOfCodeToChange: props.minLinesOfCodeToChange ?? 0,
          maxLinesOfCodeToChange: props.maxLinesOfCodeToChange ?? 0,
          ruleInstances: isUnknownArray2(p.ruleInstances) ? p.ruleInstances.filter((ri) => isRecord4(ri)) : []
        };
      }),
      rules: isRecord4(record.rules) ? record.rules : {},
      markdown: await readAssessmentMarkdown(activeScenario)
    };
  } catch {
    return null;
  }
}
async function readAssessmentMarkdown(activeScenario) {
  if (!activeScenario?.scenarioPath) return null;
  const file = path2.join(unvalidatedString(activeScenario.scenarioPath), "assessment.md");
  if (!existsSync(file)) return null;
  try {
    return { path: file, content: await fs.readFile(file, "utf8") };
  } catch {
    return null;
  }
}
async function readPlan(activeScenario) {
  if (!activeScenario?.scenarioPath) return null;
  const file = path2.join(unvalidatedString(activeScenario.scenarioPath), "plan.md");
  if (!existsSync(file)) return null;
  try {
    return { path: file, content: await fs.readFile(file, "utf8") };
  } catch {
    return null;
  }
}
function findDependencyHealthJson(activeScenario) {
  if (!activeScenario?.scenarioPath) return null;
  const file = path2.join(unvalidatedString(activeScenario.scenarioPath), "dependencies-health.json");
  return existsSync(file) ? file : null;
}
function _depRefPath(x) {
  let raw = null;
  if (typeof x === "string") {
    raw = x;
  } else if (x && typeof x === "object") {
    const n = pick(x, "path", "Path", "projectPath", "ProjectPath", "name", "Name", "projectName", "ProjectName");
    if (typeof n === "string") raw = n;
  }
  if (!raw) return "";
  return raw.replace(/\\/g, "/");
}
function _depRefDisplay(fullPath) {
  const base = fullPath.split("/").pop() ?? fullPath;
  return base.replace(/\.[a-z]+proj$/i, "");
}
async function readDependencyHealth(activeScenario) {
  const file = findDependencyHealthJson(activeScenario);
  if (!file) return null;
  try {
    const data = JSON.parse(await fs.readFile(file, "utf8"));
    const gov = pick(data, "packageGovernance", "PackageGovernance") ?? {};
    const packagesRaw = pick(gov, "packages", "Packages");
    const packages = isUnknownArray2(packagesRaw) ? packagesRaw : [];
    const projectsRaw = pick(data, "projects", "Projects");
    const projects = isUnknownArray2(projectsRaw) ? projectsRaw : [];
    return {
      path: file,
      targetFramework: pick(gov, "targetFramework", "TargetFramework") ?? null,
      counts: {
        distinctPackages: pick(gov, "totalDistinctPackages", "TotalDistinctPackages") ?? packages.length,
        versionDrift: pick(gov, "totalVersionDriftInstances", "TotalVersionDriftInstances") ?? 0,
        projects: projects.length
      },
      packages: packages.map((p) => {
        const versionsRaw = unvalidatedList(pick(p, "versions", "Versions") ?? []);
        const seen = /* @__PURE__ */ new Set();
        const projectRefs = [];
        for (const v of versionsRaw) {
          for (const pr of unvalidatedList(pick(v, "projects", "Projects") ?? [])) {
            const full = _depRefPath(pr);
            if (!full || seen.has(full)) continue;
            seen.add(full);
            projectRefs.push({ path: full, name: _depRefDisplay(full) });
          }
        }
        return {
          name: pick(p, "name", "Name") ?? "",
          totalProjectCount: pick(p, "totalProjectCount", "TotalProjectCount") ?? 0,
          distinctVersionCount: pick(p, "distinctVersionCount", "DistinctVersionCount") ?? 0,
          recommendedVersion: pick(p, "recommendedVersion", "RecommendedVersion") ?? null,
          isCompatible: pick(p, "isCompatible", "IsCompatible") ?? null,
          projects: [...projectRefs],
          versions: versionsRaw.map((v) => ({
            version: pick(v, "version", "Version") ?? "",
            projectCount: unvalidatedList(pick(v, "projects", "Projects") ?? []).length,
            isRecommended: !!pick(v, "isRecommended", "IsRecommended")
          })),
          upgrade: pick(p, "upgrade", "Upgrade") ?? null
        };
      }),
      projects: projects.map((proj) => {
        const deps = pick(proj, "dependencies", "Dependencies");
        const imports = pick(proj, "imports", "Imports");
        return {
          name: pick(proj, "name", "Name") ?? "",
          path: pick(proj, "path", "Path") ?? "",
          isSdk: !!pick(proj, "isSdk", "IsSdk"),
          currentFrameworks: pick(proj, "currentFrameworks", "CurrentFrameworks") ?? [],
          targetFramework: pick(proj, "targetFramework", "TargetFramework") ?? null,
          packageCount: unvalidatedList(pick(deps, "packages", "Packages") ?? []).length,
          assemblyCount: unvalidatedList(pick(deps, "assemblies", "Assemblies") ?? []).length,
          projectRefCount: unvalidatedList(pick(deps, "projectReferences", "ProjectReferences") ?? []).length,
          frameworkRefCount: unvalidatedList(pick(deps, "frameworkReferences", "FrameworkReferences") ?? []).length,
          importsCount: isUnknownArray2(imports) ? imports.length : 0,
          incompatible: countIncompatible(deps),
          dependencies: deps ?? null
        };
      })
    };
  } catch {
    return null;
  }
}
async function readTasks(_repoRoot, activeScenario) {
  if (!activeScenario?.scenarioPath) return null;
  const tasksPath = path2.join(unvalidatedString(activeScenario.scenarioPath), "tasks.md");
  if (!existsSync(tasksPath)) return null;
  try {
    const content = await fs.readFile(tasksPath, "utf8");
    const { tasks, overview } = parseTasksMd(content);
    const tasksDir = path2.join(unvalidatedString(activeScenario.scenarioPath), "tasks");
    const detailedTasks = await Promise.all(
      tasks.map(async (task) => {
        const taskDir = path2.join(tasksDir, task.id);
        const detailsPath = path2.join(taskDir, "progress-details.md");
        const taskMdPath = path2.join(taskDir, "task.md");
        let progressDetails = null;
        let hasProgressDetails = false;
        try {
          progressDetails = await fs.readFile(detailsPath, "utf8");
          hasProgressDetails = true;
        } catch {
          progressDetails = null;
        }
        let taskBlurb = null;
        let taskBlurbPath = null;
        try {
          taskBlurb = (await fs.readFile(taskMdPath, "utf8")).trim();
          taskBlurbPath = taskMdPath;
        } catch {
          taskBlurb = null;
          taskBlurbPath = null;
        }
        return hasProgressDetails ? { ...task, progressDetails, progressDetailsPath: detailsPath, taskBlurb, taskBlurbPath } : { ...task, progressDetails, taskBlurb, taskBlurbPath };
      })
    );
    let updatedAt = null;
    try {
      updatedAt = new Date(statSync2(tasksPath).mtimeMs).toISOString();
    } catch {
      updatedAt = null;
    }
    return { path: tasksPath, scenarioId: activeScenario.id, overview, tasks: detailedTasks, updatedAt };
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
    probe("active scenario", unvalidatedString(activeScenario.scenarioPath));
    probe("scenario.json", path2.join(unvalidatedString(activeScenario.scenarioPath), "scenario.json"));
    probe("tasks.md", path2.join(unvalidatedString(activeScenario.scenarioPath), "tasks.md"));
    probe("assessment.json", path2.join(unvalidatedString(activeScenario.scenarioPath), "assessment.json"));
    probe("dependencies-health.json", path2.join(unvalidatedString(activeScenario.scenarioPath), "dependencies-health.json"));
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
var _snapshotCache = /* @__PURE__ */ new Map();
var _snapshotInflight = /* @__PURE__ */ new Map();
var _projectsCache = /* @__PURE__ */ new Map();
var SNAPSHOT_MAX_AGE_MS = 3e4;
async function _statToken(p) {
  try {
    const st = await fs.stat(p);
    return `${st.mtimeMs}:${st.size}:${st.isDirectory() ? "d" : "f"}`;
  } catch {
    return "\u2205";
  }
}
async function computeChangeToken(targets, statFn = _statToken) {
  if (!Array.isArray(targets) || targets.length === 0) return "";
  const sorted = [...targets].sort();
  const parts = await Promise.all(sorted.map(async (p) => `${p}=${await statFn(p)}`));
  return parts.join("\n");
}
async function listScenarioChildDirs(repoRoot) {
  const dir = path2.join(repoRoot, SCENARIOS_REL);
  try {
    const entries = await fs.readdir(dir, { withFileTypes: true });
    return entries.filter((e) => e.isDirectory()).map((e) => path2.join(dir, e.name));
  } catch {
    return [];
  }
}
function buildTokenTargets(repoRoot, scenarios, activeScenario, tasks, walkedDirs, projectFiles, scenarioChildDirs) {
  const targets = [path2.join(repoRoot, SCENARIOS_REL)];
  for (const s of scenarios ?? []) {
    if (!s?.scenarioPath) {
      continue;
    }
    const sPath = unvalidatedString(s.scenarioPath);
    targets.push(sPath, path2.join(sPath, "scenario.json"));
  }
  targets.push(...scenarioChildDirs ?? []);
  if (activeScenario?.scenarioPath) {
    const sp = unvalidatedString(activeScenario.scenarioPath);
    for (const file of ["assessment.json", "assessment.md", "dependencies-health.json", "plan.md", "scenario-instructions.md", "tasks.md"]) {
      targets.push(path2.join(sp, file));
    }
    const tasksDir = path2.join(sp, "tasks");
    targets.push(tasksDir);
    for (const task of tasks?.tasks ?? []) {
      const taskDir = path2.join(tasksDir, task.id);
      targets.push(taskDir, path2.join(taskDir, "progress-details.md"), path2.join(taskDir, "task.md"));
    }
  }
  targets.push(activityLogDir(repoRoot), resolveActivityLog(repoRoot), ...resolveActivityArchives(repoRoot));
  targets.push(repoRoot, ...walkedDirs, ...projectFiles ?? []);
  return [...new Set(targets)];
}
async function snapshot(repoRoot, resolution, { force = false } = {}) {
  if (!force) {
    const cached = _snapshotCache.get(repoRoot);
    if (cached && Date.now() - cached.computedAt < SNAPSHOT_MAX_AGE_MS && await computeChangeToken(cached.tokenTargets) === cached.token) {
      return cached.state;
    }
    const inflight = _snapshotInflight.get(repoRoot);
    if (inflight) {
      return inflight;
    }
  }
  const computePromise = (async () => {
    const { state, tokenTargets } = await computeSnapshot(repoRoot, resolution, force);
    _snapshotCache.set(repoRoot, {
      state,
      tokenTargets,
      token: await computeChangeToken(tokenTargets),
      computedAt: Date.now()
    });
    return state;
  })();
  if (!force) {
    _snapshotInflight.set(repoRoot, computePromise);
    computePromise.finally(() => {
      if (_snapshotInflight.get(repoRoot) === computePromise) {
        _snapshotInflight.delete(repoRoot);
      }
    }).catch(() => {
    });
  }
  return computePromise;
}
async function readProjectsCached(repoRoot, force = false) {
  if (!force) {
    const cached = _projectsCache.get(repoRoot);
    if (cached && await computeChangeToken(cached.tokenTargets) === cached.token) {
      return cached.result;
    }
  }
  const result = await readProjects(repoRoot);
  const tokenTargets = [.../* @__PURE__ */ new Set([repoRoot, ...result.walkedDirs, ...result.projectFiles])];
  _projectsCache.set(repoRoot, {
    result,
    tokenTargets,
    token: await computeChangeToken(tokenTargets, (p) => result.preReadStats.get(p) ?? _statToken(p))
  });
  return result;
}
async function computeSnapshot(repoRoot, resolution, force = false) {
  const scenarios = await readScenarios(repoRoot);
  const activeScenario = getActiveScenario(scenarios);
  const [activityTail, projectsResult, assessment, dependencies, tasks, plan, diagnostics, scenarioInstructions, scenarioChildDirs] = await Promise.all([
    readActivityTail(repoRoot),
    readProjectsCached(repoRoot, force),
    readAssessment(activeScenario),
    readDependencyHealth(activeScenario),
    readTasks(repoRoot, activeScenario),
    readPlan(activeScenario),
    buildDiagnostics(repoRoot, resolution, activeScenario),
    readScenarioInstructions(activeScenario),
    listScenarioChildDirs(repoRoot)
  ]);
  const activityLog = resolveActivityLog(repoRoot);
  const state = {
    repoRoot,
    activitySources: existsSync(activityLog) ? [activityLog] : [],
    activeScenarioId: activeScenario?.id ?? null,
    activity: activityTail.entries,
    activityTruncated: activityTail.truncated,
    scenarios,
    projects: projectsResult.projects,
    assessment,
    dependencies,
    tasks,
    plan,
    diagnostics,
    scenarioInstructions,
    generatedAt: (/* @__PURE__ */ new Date()).toISOString()
  };
  const tokenTargets = buildTokenTargets(repoRoot, scenarios, activeScenario, tasks, projectsResult.walkedDirs, projectsResult.projectFiles, scenarioChildDirs);
  return { state, tokenTargets };
}
async function readScenarioInstructions(activeScenario) {
  if (!activeScenario?.scenarioPath) return null;
  const file = path2.join(unvalidatedString(activeScenario.scenarioPath), "scenario-instructions.md");
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
function isRecord5(value) {
  return typeof value === "object" && value !== null;
}
function sortedKeysReplacer(_key, value) {
  if (isRecord5(value) && !Array.isArray(value)) {
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
  const diagRecord = isRecord5(diagnostics) ? diagnostics : {};
  const diagKey = diagnostics ? {
    paths: diagRecord.paths,
    resolutionSource: diagRecord.resolutionSource,
    resolvedRepoRoot: diagRecord.resolvedRepoRoot,
    gitKind: diagRecord.gitKind,
    gitDir: diagRecord.gitDir
  } : null;
  return JSON.stringify({ ...rest, diagnostics: diagKey }, sortedKeysReplacer);
}

// lib/server.ts
function unvalidatedRecord2(value) {
  return value;
}
function thrown(value) {
  return value;
}
function maybeThrown(value) {
  return value;
}
function unvalidatedBody(value) {
  return value;
}
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
    if (maybeThrown(error)?.code === "ENOENT" || maybeThrown(error)?.code === "EISDIR") {
      return false;
    }
    throw error;
  }
}
var COMMIT_HASH_RE = /^[a-f0-9]{4,64}$/i;
function isValidCommitHash(value) {
  return COMMIT_HASH_RE.test(value);
}
var MAX_ACTION_BODY_BYTES = 1024 * 1024;
var MAX_TELEMETRY_BODY_BYTES = 10 * 1024;
var LOOPBACK_HOSTNAMES = /* @__PURE__ */ new Set(["127.0.0.1", "localhost", "::1"]);
function hostnameFromAuthority(authority) {
  if (typeof authority !== "string" || authority.length === 0) {
    return null;
  }
  const value = authority.trim();
  if (value.startsWith("[")) {
    const end = value.indexOf("]");
    if (end === -1) {
      return null;
    }
    return value.slice(1, end).toLowerCase();
  }
  const colon = value.indexOf(":");
  return (colon === -1 ? value : value.slice(0, colon)).toLowerCase();
}
function isLoopbackHost(hostHeader) {
  const hostname = hostnameFromAuthority(hostHeader);
  return hostname !== null && LOOPBACK_HOSTNAMES.has(hostname);
}
function isLoopbackOrigin(origin) {
  let parsed;
  try {
    parsed = new URL(origin);
  } catch {
    return false;
  }
  if (parsed.protocol !== "http:" && parsed.protocol !== "https:") {
    return false;
  }
  const hostname = parsed.hostname.replace(/^\[|\]$/g, "").toLowerCase();
  return LOOPBACK_HOSTNAMES.has(hostname);
}
function isCrossSiteRequest(req) {
  const secFetchSite = req.headers["sec-fetch-site"];
  if (typeof secFetchSite === "string" && secFetchSite.length > 0) {
    return secFetchSite === "cross-site" || secFetchSite === "cross-origin";
  }
  const origin = req.headers.origin;
  if (typeof origin === "string" && origin.length > 0) {
    return !isLoopbackOrigin(origin);
  }
  return false;
}
function isCrossSiteProtectedRoute(method, pathname) {
  if (method !== "GET") {
    return true;
  }
  return pathname === "/events" || pathname.startsWith("/api/");
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
    pollIntervalMs = 5e3,
    keepaliveMs = 2e4
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
    const state = await snapshot2(resolution.path, resolution, { force });
    const hash = hashState(unvalidatedRecord2(state));
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
    if (!isLoopbackHost(req.headers.host)) {
      res.writeHead(403, { "content-type": "text/plain; charset=utf-8" });
      res.end("forbidden: host not allowed");
      return;
    }
    if (isCrossSiteProtectedRoute(req.method, url.pathname) && isCrossSiteRequest(req)) {
      res.writeHead(403, { "content-type": "text/plain; charset=utf-8" });
      res.end("forbidden: cross-site request rejected");
      return;
    }
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
      meta.lastStateHash = hashState(unvalidatedRecord2(state));
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
        res.end(JSON.stringify({ error: thrown(err).message }));
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
        res.end(JSON.stringify({ error: thrown(err).message }));
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
        res.end(JSON.stringify({ error: thrown(err).message }));
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
      }, keepaliveMs);
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
        meta.lastStateHash = hashState(unvalidatedRecord2(state));
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
      const chunks = [];
      let received = 0;
      let overflow = false;
      req.on("data", (chunk) => {
        if (overflow) return;
        received += chunk.length;
        if (received > MAX_ACTION_BODY_BYTES) {
          overflow = true;
          res.writeHead(413, { "content-type": "application/json" });
          res.end(JSON.stringify({ error: "request body too large" }));
          return;
        }
        chunks.push(chunk);
      });
      req.on("end", async () => {
        if (overflow) return;
        try {
          const body = Buffer.concat(chunks).toString("utf8");
          const payload = unvalidatedRecord2(JSON.parse(body || "{}"));
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
          let state = null;
          try {
            const meta = getInstanceMeta(ctx.instanceId);
            const resolution = meta.resolution ?? await getResolution(ctx.instanceId);
            if (resolution) {
              meta.resolution = resolution;
              state = await snapshot2(resolution.path, resolution);
              meta.lastStateHash = hashState(unvalidatedRecord2(state));
            }
          } catch (refreshError) {
            const detail = refreshError instanceof Error ? refreshError.message : String(refreshError);
            console.warn(`[upgrade-agent-dashboard] post-action state refresh failed for "${actionName}": ${detail}`);
            state = null;
          }
          res.writeHead(200, { "content-type": "application/json" });
          res.end(JSON.stringify({ result, state }));
        } catch (err) {
          res.writeHead(400, { "content-type": "application/json" });
          res.end(JSON.stringify({ error: err instanceof Error ? err.message : "Unknown error" }));
        }
      });
      return;
    }
    if (req.method === "POST" && url.pathname === "/telemetry") {
      const chunks = [];
      let received = 0;
      let overflow = false;
      req.on("data", (chunk) => {
        if (overflow) return;
        received += chunk.length;
        if (received > MAX_TELEMETRY_BODY_BYTES) {
          overflow = true;
          res.writeHead(413);
          res.end();
          return;
        }
        chunks.push(chunk);
      });
      req.on("end", () => {
        if (overflow) return;
        try {
          const payload = JSON.parse(Buffer.concat(chunks).toString("utf8") || "{}");
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
        res.end(unvalidatedBody(maybeThrown(err)?.message ?? "internal error"));
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
      await new Promise((resolve) => server.listen(port, host, () => resolve()));
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
      } else if (!stdout.trim()) {
        execFile("git", ["ls-files", "--error-unmatch", "--", filePath], { cwd: repoRoot }, (lsErr) => {
          if (!lsErr) {
            resolve("");
            return;
          }
          execFile(
            "git",
            ["diff", "--no-index", "--", "/dev/null", filePath],
            { cwd: repoRoot, maxBuffer: 1024 * 1024 },
            (_diffErr, diffOut) => {
              if (diffOut) {
                resolve(diffOut);
              } else {
                resolve("");
              }
            }
          );
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

// lib/panels.ts
var TAB_PANELS = [
  "overview",
  "assessment",
  "plan",
  "execution",
  "activity",
  "options"
];
var ASSESSMENT_SUB_TABS = [
  "summary",
  "issues",
  "projects",
  "dependencies",
  "features"
];
var EXECUTION_DEEP_LINKS = ["tasks", "builds", "repository"];
var DEEP_LINK_PANELS = [
  ...EXECUTION_DEEP_LINKS,
  ...ASSESSMENT_SUB_TABS.map((sub) => `assessment:${sub}`)
];
var OVERLAY_PANELS = ["diagnostics"];
var PANEL_NAMES = [
  ...TAB_PANELS,
  ...DEEP_LINK_PANELS,
  ...OVERLAY_PANELS
];
var PANEL_SET = new Set(PANEL_NAMES);
function isValidPanel(panel) {
  return typeof panel === "string" && PANEL_SET.has(panel);
}
var TELEMETRY_PANELS = [...TAB_PANELS, ...OVERLAY_PANELS];
var TELEMETRY_EVENTS = ["dashboard/tab_click", "dashboard/tab_navigation"];
var TELEMETRY_PANEL_SET = new Set(TELEMETRY_PANELS);
var TELEMETRY_EVENT_SET = new Set(TELEMETRY_EVENTS);
function isTelemetryPanel(panel) {
  return typeof panel === "string" && TELEMETRY_PANEL_SET.has(panel);
}
function isTelemetryEvent(event) {
  return typeof event === "string" && TELEMETRY_EVENT_SET.has(event);
}

// lib/telemetry-sink.ts
function resolveTelemetryRecord(payload, now = /* @__PURE__ */ new Date()) {
  if (typeof payload !== "object" || payload === null) {
    return null;
  }
  const { event, properties } = payload;
  if (!isTelemetryEvent(event)) {
    return null;
  }
  const panel = properties?.panel;
  if (!isTelemetryPanel(panel)) {
    return null;
  }
  return { event, properties: { panel }, timestamp: now.toISOString() };
}

// lib/markdown-editor.ts
import path5 from "node:path";
import { createHash } from "node:crypto";
import { realpathSync, statSync as statSync3 } from "node:fs";
var nodeFileSystem = {
  realpathSync: (target) => realpathSync(target),
  statSync: (target) => ({ isFile: () => statSync3(target).isFile() })
};
function isContained(root, candidate) {
  const relative = path5.relative(root, candidate);
  return relative !== "" && !relative.startsWith("..") && !path5.isAbsolute(relative);
}
function resolveEditableMarkdownPath(candidate, repoRoot, fs3 = nodeFileSystem) {
  if (typeof candidate !== "string" || candidate.trim() === "") {
    return { ok: false, code: "invalid_path", message: "path is required." };
  }
  const trimmed = candidate.trim();
  if (trimmed.includes("\0")) {
    return { ok: false, code: "invalid_path", message: "path contains an invalid character." };
  }
  if (!/\.md$/i.test(trimmed)) {
    return { ok: false, code: "not_markdown", message: `Only markdown files can be opened in the editor: ${trimmed}` };
  }
  if (typeof repoRoot !== "string" || repoRoot.trim() === "") {
    return { ok: false, code: "repo_unresolved", message: "The repository root has not been resolved yet." };
  }
  const root = path5.resolve(repoRoot);
  const resolved = path5.resolve(root, trimmed);
  if (!isContained(root, resolved)) {
    return { ok: false, code: "outside_repo", message: `Refusing to open a file outside the repository: ${trimmed}` };
  }
  let realRoot;
  try {
    realRoot = path5.resolve(fs3.realpathSync(root));
  } catch {
    return { ok: false, code: "repo_unresolved", message: "The repository root is no longer accessible." };
  }
  let realPath;
  try {
    realPath = path5.resolve(fs3.realpathSync(resolved));
    if (!fs3.statSync(realPath).isFile()) {
      return { ok: false, code: "markdown_missing_on_disk", message: `${trimmed} is not a file.` };
    }
  } catch {
    return { ok: false, code: "markdown_missing_on_disk", message: `${trimmed} is no longer on disk.` };
  }
  if (!isContained(realRoot, realPath)) {
    return { ok: false, code: "outside_repo", message: `Refusing to open a file outside the repository: ${trimmed}` };
  }
  if (!/\.md$/i.test(realPath)) {
    return { ok: false, code: "not_markdown", message: `Only markdown files can be opened in the editor: ${trimmed}` };
  }
  const relativePath = path5.relative(realRoot, realPath);
  return { ok: true, path: realPath, relativePath: relativePath.split(path5.sep).join("/") };
}
function markdownEditorInstanceId(relativePath) {
  const digest = createHash("sha256").update(relativePath).digest("hex").slice(0, 8);
  const slug = relativePath.toLowerCase().replace(/[^a-z0-9]+/g, "-").slice(0, 40).replace(/^-+|-+$/g, "");
  return slug === "" ? `markdown-${digest}` : `markdown-${slug}-${digest}`;
}
function markdownEditorTitle(relativePath) {
  const segments = relativePath.split("/").filter((segment) => segment !== "");
  return segments.slice(-2).join("/");
}

// lib/feedback.ts
var FEEDBACK_REPO_URL = "https://github.com/microsoft/upgrade-agent-plugins";
var FEEDBACK_ISSUE_URL = `${FEEDBACK_REPO_URL}/issues/new`;
var MAX_FIELD_LENGTH = 100;
var UNKNOWN = "unknown";
function sanitizeField(value) {
  let text;
  if (typeof value === "string") {
    text = value;
  } else if (typeof value === "number" && Number.isFinite(value)) {
    text = String(value);
  } else {
    return "";
  }
  const collapsed = text.replace(/\s+/g, " ").trim().replace(/[|`<>\\]/g, "");
  if (collapsed.length <= MAX_FIELD_LENGTH) {
    return collapsed;
  }
  return `${collapsed.slice(0, MAX_FIELD_LENGTH - 1)}\u2026`;
}
function fieldOrUnknown(value) {
  const sanitized = sanitizeField(value);
  return sanitized === "" ? UNKNOWN : `\`${sanitized}\``;
}
function buildFeedbackEnvironmentRows(context = {}) {
  const targetFramework = sanitizeField(context.targetFramework);
  return [
    ["Plugin version", fieldOrUnknown(context.pluginVersion)],
    ["Host", fieldOrUnknown(context.host)],
    ["Host version", fieldOrUnknown(context.hostVersion)],
    ["Scenario", fieldOrUnknown(context.scenarioId)],
    ...targetFramework === "" ? [] : [["Target framework", `\`${targetFramework}\``]],
    ["Phase", fieldOrUnknown(context.phase)]
  ];
}
function buildFeedbackIssueBody(context = {}) {
  const rows = buildFeedbackEnvironmentRows(context);
  return [
    "",
    "",
    "---",
    "<details><summary>Environment (auto-filled)</summary>",
    "",
    "| | |",
    "|---|---|",
    ...rows.map(([name, value]) => `| ${name} | ${value} |`),
    "",
    "</details>",
    ""
  ].join("\n");
}
function buildFeedbackIssueUrl(context = {}) {
  const params = new URLSearchParams({ body: buildFeedbackIssueBody(context) });
  return `${FEEDBACK_ISSUE_URL}?${params.toString()}`;
}

// lib/feedback-context.ts
import { readFileSync as readFileSync2 } from "node:fs";
import path6 from "node:path";
import { fileURLToPath as fileURLToPath2 } from "node:url";
var MAX_MANIFEST_LOOKUP_DEPTH = 6;
function detectHost(env, fallback) {
  if (env.AI_AGENT === "github_copilot_app_agent") {
    return "GitHub Copilot app";
  }
  if (env.GITHUB_ACTIONS === "true") {
    return "Copilot coding agent";
  }
  if (typeof env.COPILOT_CLI_BINARY_VERSION === "string" && env.COPILOT_CLI_BINARY_VERSION.trim() !== "") {
    return "Copilot CLI";
  }
  return fallback;
}
function readHostVersion(env) {
  const version = env.COPILOT_CLI_BINARY_VERSION;
  return typeof version === "string" && version.trim() !== "" ? version.trim() : void 0;
}
function isRecord6(value) {
  return typeof value === "object" && value !== null;
}
function readPluginVersion(startDir, readFile = (p) => readFileSync2(p, "utf8")) {
  let dir = startDir;
  for (let depth = 0; depth < MAX_MANIFEST_LOOKUP_DEPTH; depth += 1) {
    try {
      const parsed = JSON.parse(readFile(path6.join(dir, "plugin.json")));
      if (isRecord6(parsed) && typeof parsed.version === "string" && parsed.version.trim() !== "") {
        return parsed.version.trim();
      }
    } catch {
    }
    const parent = path6.dirname(dir);
    if (parent === dir) {
      break;
    }
    dir = parent;
  }
  return null;
}
function activeScenarioOf(state) {
  if (!Array.isArray(state.scenarios)) {
    return null;
  }
  return state.scenarios.find((candidate) => candidate?.id === state.activeScenarioId) ?? null;
}
function buildFeedbackContext(state, options) {
  const snapshot2 = state ?? {};
  const scenario = activeScenarioOf(snapshot2);
  const scenarioProperties = isRecord6(scenario?.properties) ? scenario.properties : {};
  const targetFramework = scenarioProperties.UpgradeTargetFramework ?? scenarioProperties.upgradeTargetFramework ?? snapshot2.dependencies?.targetFramework ?? null;
  const moduleDir = options.moduleDir ?? path6.dirname(fileURLToPath2(import.meta.url));
  const env = options.env ?? {
    AI_AGENT: process.env.AI_AGENT,
    GITHUB_ACTIONS: process.env.GITHUB_ACTIONS,
    COPILOT_CLI_BINARY_VERSION: process.env.COPILOT_CLI_BINARY_VERSION
  };
  return {
    pluginVersion: readPluginVersion(moduleDir) ?? void 0,
    host: detectHost(env, options.surface),
    hostVersion: readHostVersion(env),
    scenarioId: snapshot2.activeScenarioId ?? void 0,
    targetFramework: targetFramework ?? void 0,
    phase: options.phaseLabel ?? void 0
  };
}

// lib/open-external.ts
import { spawn as nodeSpawn } from "node:child_process";
import path7 from "node:path";
function windowsProtocolHandler(env = process.env) {
  const systemRoot = typeof env.SystemRoot === "string" && env.SystemRoot !== "" ? env.SystemRoot : "C:\\Windows";
  return path7.join(systemRoot, "System32", "rundll32.exe");
}
function externalOpenCommand(url, platform, env) {
  if (platform === "win32") {
    return { command: windowsProtocolHandler(env), args: ["url.dll,FileProtocolHandler", url] };
  }
  if (platform === "darwin") {
    return { command: "open", args: [url] };
  }
  return { command: "xdg-open", args: [url] };
}
var ExternalOpenError = class extends Error {
  code;
  constructor(code, message) {
    super(message);
    this.name = "ExternalOpenError";
    this.code = code;
  }
};
function assertAllowed(url, allowedPrefixes) {
  if (typeof url !== "string" || url === "") {
    throw new ExternalOpenError("invalid_url", "A URL is required.");
  }
  if (!allowedPrefixes.some((prefix) => prefix !== "" && url.startsWith(prefix))) {
    throw new ExternalOpenError("url_not_allowed", "Refusing to open a URL outside the allowed list.");
  }
}
async function openExternalUrl(url, options) {
  assertAllowed(url, options.allowedPrefixes);
  const platform = options.platform ?? process.platform;
  const spawnFn = options.spawn ?? nodeSpawn;
  const { command, args } = externalOpenCommand(url, platform);
  return await new Promise((resolve, reject) => {
    let child;
    try {
      child = spawnFn(command, args, { detached: true, stdio: "ignore", windowsHide: true });
    } catch (error) {
      reject(new ExternalOpenError("spawn_failed", `Could not launch ${command}: ${error?.message ?? error}`));
      return;
    }
    let settled = false;
    child.once("error", (error) => {
      if (settled) {
        return;
      }
      settled = true;
      reject(new ExternalOpenError("spawn_failed", `Could not launch ${command}: ${error?.message ?? error}`));
    });
    child.once("spawn", () => {
      if (settled) {
        return;
      }
      settled = true;
      child.unref();
      resolve({ command, args });
    });
  });
}

// lib/task-state.ts
var TERMINAL_TASK_STATES = /* @__PURE__ */ new Set(["Complete"]);
function isTerminalTaskState(state) {
  return typeof state === "string" && TERMINAL_TASK_STATES.has(state);
}
var ATTENTION_TASK_STATES = /* @__PURE__ */ new Set(["Failed", "Skipped"]);
function isAttentionTaskState(state) {
  return typeof state === "string" && ATTENTION_TASK_STATES.has(state);
}

// lib/phase.ts
var PHASE_META = {
  setup: {
    label: "Getting set up",
    description: "Reading the repository and preparing the upgrade scenario."
  },
  assess: {
    label: "Assessing",
    description: "Scanning projects and dependencies for compatibility issues."
  },
  plan: {
    label: "Planning",
    description: "Choosing an upgrade strategy and breaking it into tasks."
  },
  execute: {
    label: "Upgrading",
    description: "Applying changes to your code."
  },
  validate: {
    label: "Validating",
    description: "Building and testing the upgraded solution."
  }
};
var PHASE_ALIASES = /* @__PURE__ */ new Map([
  ["setup", "setup"],
  ["initialize", "setup"],
  ["initialization", "setup"],
  ["assess", "assess"],
  ["assessment", "assess"],
  ["analyze", "assess"],
  ["analysis", "assess"],
  ["plan", "plan"],
  ["planning", "plan"],
  ["execute", "execute"],
  ["execution", "execute"],
  ["upgrade", "execute"],
  ["remediate", "execute"],
  ["validate", "validate"],
  ["validation", "validate"],
  ["verify", "validate"],
  ["test", "validate"]
]);
var ARTIFACT_PHASES = [
  [/\/tasks\/[^/]+\/progress-details\.md$/, "execute"],
  [/\/tasks\/[^/]+\/task\.md$/, "plan"],
  [/\/tasks\.md$/, "plan"],
  [/\/plan\.md$/, "plan"],
  [/\/upgrade-options\.md$/, "plan"],
  [/\/assessment[^/]*$/, "assess"],
  [/\/dependencies-health\.json$/, "assess"],
  [/\/scenario-instructions\.md$/, "setup"],
  [/\/scenario\.json$/, "setup"]
];
function isRecord7(value) {
  return typeof value === "object" && value !== null;
}
function normalizePhaseName(value) {
  if (typeof value !== "string") {
    return null;
  }
  return PHASE_ALIASES.get(value.trim().toLowerCase()) ?? null;
}
function phaseForArtifact(filePath) {
  const normalized = normalizePathSeparators(filePath).toLowerCase();
  for (const [pattern, phase] of ARTIFACT_PHASES) {
    if (pattern.test(normalized)) {
      return phase;
    }
  }
  return null;
}
function build(id, inferred, evidence, at) {
  return { id, ...PHASE_META[id], inferred, evidence, at };
}
function derivePhase(state) {
  const currentState = isRecord7(state) ? state : {};
  const activity = Array.isArray(currentState.activity) ? currentState.activity : [];
  const tasks = isRecord7(currentState.tasks) && Array.isArray(currentState.tasks.tasks) ? currentState.tasks.tasks : [];
  const hasLiveTask = tasks.some((task) => isRecord7(task) && task.state === "InProgress");
  const allTasksDone = tasks.length > 0 && tasks.every((task) => isRecord7(task) && isTerminalTaskState(task.state));
  const needsAttention = tasks.some((task) => isRecord7(task) && isAttentionTaskState(task.state));
  const scenarios = Array.isArray(currentState.scenarios) ? currentState.scenarios : [];
  const hasScenario = typeof currentState.activeScenarioId === "string" && currentState.activeScenarioId !== "" || scenarios.length > 0;
  const hasAgentArtifact = activity.some(
    (entry) => isRecord7(entry) && entry.kind === "file" && isAgentArtifactPath(entry.filePath)
  );
  const upgradeUnderway = hasScenario || hasAgentArtifact || tasks.length > 0;
  for (const entry of activity) {
    if (!isRecord7(entry)) {
      continue;
    }
    const at = toIsoTimestamp(entry.timestamp);
    const explicit = entry.event === "phase_entered" ? normalizePhaseName(entry.phase) : null;
    if (explicit) {
      return build(explicit, false, null, at);
    }
    if (entry.kind !== "file" || typeof entry.filePath !== "string") {
      continue;
    }
    if (!isAgentArtifactPath(entry.filePath)) {
      if (!upgradeUnderway) {
        continue;
      }
      return build(allTasksDone ? "validate" : "execute", true, entry.filePath, at);
    }
    const inferred = phaseForArtifact(entry.filePath);
    if (inferred) {
      const started = hasLiveTask || needsAttention;
      const resolved = allTasksDone ? "validate" : started && inferred !== "validate" ? "execute" : inferred;
      return build(resolved, true, entry.filePath, at);
    }
  }
  if (hasLiveTask || needsAttention) {
    return build("execute", true, null, null);
  }
  return null;
}

// extension.ts
var INDEX_HTML_PATH = resolveCanvasIndexHtml(import.meta.url);
function inputFields(input) {
  return input;
}
function isRecord8(value) {
  return typeof value === "object" && value !== null;
}
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
  const panel = inputFields(input)?.panel;
  if (!isValidPanel(panel)) {
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
  const mode = inputFields(input)?.mode;
  if (mode !== "guided" && mode !== "automatic") {
    throw new CanvasError("invalid_mode", "mode must be 'guided' or 'automatic'.");
  }
  await currentSession.send(
    `Please switch the upgrade mode to ${mode}. (Requested from the Upgrade Agent Dashboard canvas.)`
  );
  return { ok: true, status: `Asked the agent to switch to ${mode} mode.` };
});
actionHandlers.set("explain_dependency", async (context) => {
  const currentSession = requireSendSession();
  const packageName = (inputFields(context.input)?.packageName ?? "").toString().trim();
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
actionHandlers.set("open_markdown_editor", async (context) => {
  const currentSession = requireSession();
  const openCanvas = currentSession.rpc?.canvas?.open;
  if (typeof openCanvas !== "function") {
    throw new CanvasError(
      "unsupported_runtime",
      "This Copilot CLI build does not expose session.rpc.canvas.open; update the CLI to open markdown files in the editor."
    );
  }
  const resolution = await ensureResolvedRepo(context.session?.workingDirectory);
  const resolved = resolveEditableMarkdownPath(inputFields(context.input)?.path, resolution.path);
  if (!resolved.ok) {
    throw new CanvasError(resolved.code, resolved.message);
  }
  await openCanvas.call(currentSession.rpc?.canvas, {
    canvasId: "editor",
    instanceId: markdownEditorInstanceId(resolved.relativePath),
    input: {
      path: resolved.relativePath,
      scope: "repo",
      title: markdownEditorTitle(resolved.relativePath)
    }
  });
  return { ok: true, path: resolved.path, status: `Opened ${resolved.relativePath} in the editor.` };
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
  const scenarioProperties = isRecord8(activeScenario?.properties) ? activeScenario.properties : {};
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
      targetFramework: scenarioProperties.UpgradeTargetFramework ?? scenarioProperties.upgradeTargetFramework ?? null
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
async function feedbackContextForCanvas(context) {
  let state = null;
  try {
    state = await getSnapshotForResolution(context);
  } catch {
    state = null;
  }
  return buildFeedbackContext(state, {
    surface: "Copilot App canvas",
    phaseLabel: derivePhase(state)?.label ?? null
  });
}
actionHandlers.set("open_feedback_issue", async (context) => {
  const url = buildFeedbackIssueUrl(await feedbackContextForCanvas(context));
  try {
    await openExternalUrl(url, { allowedPrefixes: [FEEDBACK_ISSUE_URL] });
    return { ok: true, status: "Opened the feedback form in your browser." };
  } catch {
    return { ok: false, url };
  }
});
var dashboardServer = createDashboardServer({
  indexHtmlPath: INDEX_HTML_PATH,
  getResolution: async () => ensureResolvedRepo(),
  snapshot,
  getActionHandler: (name) => actionHandlers.get(name) ?? null,
  onTelemetry: (payload) => {
    const record = resolveTelemetryRecord(payload);
    if (record === null) return;
    if (!resolvedRepo?.path) return;
    const directory = activityLogDir(resolvedRepo.path);
    const file = path8.join(directory, "canvas-telemetry.jsonl");
    mkdir(directory, { recursive: true }).then(() => appendFile(file, `${JSON.stringify(record)}
`)).catch(() => {
    });
  }
});
var { url: baseUrl } = await dashboardServer.listen();
var canvas = createCanvas({
  id: "dashboard",
  displayName: "Upgrade Agent Dashboard",
  description: "Read-only view of the .NET upgrade artifacts for the current workspace: an Overview landing, plus Assessment (with Summary metrics, Issues explorer, Projects, Dependencies, and Features sub-tabs), Plan (rendered plan.md and per-task task.md), Tasks, Options, Execution, and Activity log. Also exposes actions to switch execution mode, explain dependency issues, open a markdown artifact in the editor canvas, and file feedback on GitHub.",
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
        properties: { panel: { type: "string", enum: [...PANEL_NAMES] } },
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
      name: "open_markdown_editor",
      description: "Open one of the scenario's markdown artifacts (plan.md, a task's task.md, \u2026) in the editor canvas. The path must be a markdown file inside the repository.",
      inputSchema: {
        type: "object",
        properties: { path: { type: "string" } },
        required: ["path"],
        additionalProperties: false
      },
      handler: (context) => actionHandlers.get("open_markdown_editor")(context)
    },
    {
      name: "push_context",
      description: "Push a structured snapshot of the current upgrade dashboard state (scenario, assessment, dependency, and task summary) into the chat as context for the next message.",
      inputSchema: { type: "object", additionalProperties: false },
      handler: (context) => actionHandlers.get("push_context")(context)
    },
    {
      name: "open_feedback_issue",
      description: "Open a prefilled feedback issue for the Upgrade Agent on GitHub in the user's default browser. The prefill is the environment block only \u2014 the user writes the report on GitHub, and nothing is submitted until they press Create.",
      inputSchema: { type: "object", additionalProperties: false },
      handler: (context) => actionHandlers.get("open_feedback_issue")(context)
    }
  ],
  async open(context) {
    const { instanceId, input } = context;
    await ensureResolvedRepo(context.session?.workingDirectory);
    const fields = inputFields(input);
    const initialPanel = isValidPanel(fields?.panel) ? fields.panel : "overview";
    const url = `${baseUrl}/?instanceId=${encodeURIComponent(instanceId)}&panel=${encodeURIComponent(initialPanel)}`;
    return { url, title: "Upgrade Agent Dashboard", status: "open" };
  },
  onClose({ instanceId }) {
    dashboardServer.closeInstance(instanceId);
  }
});
session = await joinSession({ canvases: [canvas] });
