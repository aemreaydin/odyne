// One-shot validation of curriculum.yaml against the engine-curriculum spec deltas.
// Usage: npx -y js-yaml curriculum/curriculum.yaml | node validate_curriculum.mjs
import { readFileSync } from "node:fs";

const doc = JSON.parse(readFileSync(0, "utf-8"));
const errors = [];
const mods = Object.fromEntries(doc.modules.map(m => [m.id, m]));

// Field names per curriculum-tracking spec
for (const m of doc.modules) {
  for (const f of ["id", "title", "phase", "requires", "lessons"])
    if (!(f in m)) errors.push(`${m.id ?? "?"}: missing field ${f}`);
  for (const l of m.lessons) {
    for (const f of ["id", "slug", "title", "type", "status"])
      if (!(f in l)) errors.push(`${l.id ?? "?"}: missing field ${f}`);
    if (!["concept", "kata", "build", "design", "milestone"].includes(l.type))
      errors.push(`${l.id}: bad type ${l.type}`);
    if (!["locked", "available", "active", "done"].includes(l.status))
      errors.push(`${l.id}: bad status ${l.status}`);
    if (!l.id.startsWith(m.id + "-")) errors.push(`${l.id}: id not under module ${m.id}`);
  }
}

// Requires resolve; phase ordering
for (const m of doc.modules)
  for (const r of m.requires) {
    if (!mods[r]) errors.push(`${m.id}: unknown prerequisite ${r}`);
    else if (mods[r].phase > m.phase)
      errors.push(`${m.id} (phase ${m.phase}) requires ${r} (higher phase ${mods[r].phase})`);
  }

const ancestors = (mid, seen = new Set()) => {
  for (const r of mods[mid]?.requires ?? []) {
    if (seen.has(r)) continue;
    seen.add(r); ancestors(r, seen);
  }
  return seen;
};

// Acyclic, rooted at m00
for (const mid of Object.keys(mods)) {
  const anc = ancestors(mid);
  if (anc.has(mid)) errors.push(`cycle through ${mid}`);
  if (mid !== "m00" && !anc.has("m00")) errors.push(`${mid}: not rooted at m00`);
}

// Milestone gating
for (const mid of ["m40", "m41", "m42", "m43"])
  if (!ancestors(mid).has("m33")) errors.push(`${mid}: Breakout (m33) not a transitive prerequisite`);
for (const need of ["m51", "m41", "m42"])
  if (!ancestors("m52").has(need)) errors.push(`m52: missing prerequisite ${need}`);
if (mods.m33.lessons.at(-1).type !== "milestone") errors.push("m33 does not end in a milestone");
if (mods.m52.lessons.at(-1).type !== "milestone") errors.push("m52 does not end in a milestone");

// RHI placement: m50 only after the 3D renderer
if (!ancestors("m50").has("m43")) errors.push("m50: 3D renderer (m43) not a prerequisite");

// Kata graduation: engine-bound kata modules contain a later build lesson
for (const mid of ["m02", "m03", "m41", "m42"]) {
  const types = mods[mid].lessons.map(l => l.type);
  const k = types.indexOf("kata");
  if (k === -1 || !types.slice(k).includes("build"))
    errors.push(`${mid}: kata without a subsequent graduate build`);
}

// Seed state
if (doc.active_change !== null) errors.push("active_change not null");
const statuses = doc.modules.flatMap(m => m.lessons.map(l => [l.id, l.status]));
const avail = statuses.filter(([, s]) => s === "available").map(([i]) => i);
if (avail.join() !== "m00-01") errors.push(`available lessons != [m00-01]: ${avail}`);
if (statuses.some(([, s]) => s === "active" || s === "done")) errors.push("found active/done lessons in seed");

const phases = [...new Set(doc.modules.map(m => m.phase))].sort();
console.log(`${doc.modules.length} modules, ${statuses.length} lessons, phases ${phases}`);
if (errors.length) { console.log("FAIL:"); errors.forEach(e => console.log(" -", e)); process.exit(1); }
console.log("OK: all spec checks pass");
