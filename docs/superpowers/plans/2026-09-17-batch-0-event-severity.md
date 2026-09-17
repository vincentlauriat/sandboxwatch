# Batch 0 — Event severity, server side

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every change event a severity, computed in one place on the server and published by the API, so that no client has to judge what a change means.

**Architecture:** A new module owns the twelve event types and their severity. The diff engine routes every emission through its guard, so a thirteenth type cannot reach the log without a severity. The API decorates events **on the way out** — the append-only log keeps storing facts only. The HTML page consumes the same table and finally distinguishes a lost Reader role from a probe that flickered.

**Tech Stack:** Node.js ≥ 20, CommonJS, zero npm dependencies, `node --test`.

**Spec:** `SandboxWatch/docs/superpowers/specs/2026-09-17-supervision-dispositif-design.md` (sections 4, 5 and 7)

**Repository:** This plan is executed in **`../AzureSandboxManager`**, not in `SandboxWatch`. It has its own CI (`npm test`) and its own deployment. Work on a branch there; open a pull request; do not push to `main`.

## Global Constraints

- **Zero npm dependencies.** No `package.json` `dependencies` section may appear. This is an advertised property of the project.
- **Node.js ≥ 20**, CommonJS (`'use strict';` at the top of every file, `require`/`module.exports`).
- **Tests run with `npm test`** = `node --test test/*.test.js`. Use `node:test` and `node:assert/strict`.
- **Severity is never written to `events.jsonl`.** The log stores facts; severity is a reading.
- **The server publishes judgments, not words.** `severity` yes; human labels stay in `src/html.js`.
- **The `denied ≠ empty` rule is untouchable.** A section that did not collect renders as refused, never as an empty table.

---

### Task 1: The vocabulary module

**Files:**
- Create: `src/vocabulary.js`
- Test: `test/vocabulary.test.js`

**Interfaces:**
- Consumes: nothing.
- Produces: `EVENT_TYPES: readonly string[]` · `severityOf(type: string) => 'informational'|'notable'|'critical'` · `assertKnownType(type: string) => string` (throws on unknown) · `withSeverity(events: object[]) => object[]`

- [ ] **Step 1: Write the failing test**

Create `test/vocabulary.test.js`:

```js
'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { EVENT_TYPES, severityOf, assertKnownType, withSeverity } = require('../src/vocabulary');

test('the vocabulary holds exactly the twelve types the diff engine emits', () => {
  assert.equal(EVENT_TYPES.length, 12);
});

test('losing or regaining collector access is critical', () => {
  assert.equal(severityOf('collector_access_lost'), 'critical');
  assert.equal(severityOf('collector_access_restored'), 'critical');
});

test('governance and budget changes are notable', () => {
  for (const type of ['role_added', 'role_removed', 'lock_added', 'lock_removed', 'budget_threshold_crossed']) {
    assert.equal(severityOf(type), 'notable', type);
  }
});

test('inventory and probe changes are informational', () => {
  for (const type of ['resource_added', 'resource_removed', 'app_state_changed', 'plan_tier_changed', 'probe_status_changed']) {
    assert.equal(severityOf(type), 'informational', type);
  }
});

test('an unknown type reads as notable, never informational', () => {
  // Never quieter than what is known. An old log line whose type this table no
  // longer carries must stay visible; demoting it to informational would hide
  // it behind a blank marker.
  assert.equal(severityOf('something_new'), 'notable');
});

test('assertKnownType names the file to edit', () => {
  assert.equal(assertKnownType('role_added'), 'role_added');
  assert.throws(() => assertKnownType('something_new'), /src\/vocabulary\.js/);
});

test('withSeverity decorates without mutating the input', () => {
  const stored = [{ at: '2026-09-17T08:00:00.000Z', type: 'role_removed', subject: 'x', detail: {}, collector: 'governance' }];
  const out = withSeverity(stored);
  assert.equal(out[0].severity, 'notable');
  assert.equal('severity' in stored[0], false);
});

test('withSeverity tolerates an absent list', () => {
  assert.deepEqual(withSeverity(undefined), []);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm test 2>&1 | grep -A3 vocabulary`
Expected: FAIL — `Cannot find module '../src/vocabulary'`

- [ ] **Step 3: Write minimal implementation**

Create `src/vocabulary.js`:

```js
'use strict';

/**
 * The event vocabulary: every type this server emits, and how serious it is.
 *
 * Severity is derived on read and NEVER written to the change log. The log is
 * append-only and still holds the trace of a role transfer noticed weeks
 * later; storing a judgment in it would freeze that judgment, so promoting a
 * type later would leave history classified under the old rule and
 * inconsistent with the present. Deriving it reclassifies the whole history
 * retroactively, with no data migration.
 */

const SEVERITY = Object.freeze({
  resource_added: 'informational',
  resource_removed: 'informational',
  app_state_changed: 'informational',
  plan_tier_changed: 'informational',
  probe_status_changed: 'informational',

  role_added: 'notable',
  role_removed: 'notable',
  lock_added: 'notable',
  lock_removed: 'notable',
  budget_threshold_crossed: 'notable',

  // The incident this project was written after: a role moved over a weekend
  // with nobody told. It gets its own level so it is never queued behind a
  // probe that flapped.
  collector_access_lost: 'critical',
  collector_access_restored: 'critical',
});

const EVENT_TYPES = Object.freeze(Object.keys(SEVERITY));

/**
 * Reading a type this table does not carry must not be quieter than reading a
 * known one — the same direction-of-error rule the clients apply. 'notable' is
 * visible without being able to raise an alarm.
 */
function severityOf(type) {
  return SEVERITY[type] ?? 'notable';
}

/** Emission-time guard: a new type cannot reach the log without a severity. */
function assertKnownType(type) {
  if (!Object.hasOwn(SEVERITY, type)) {
    throw new Error(`unknown event type '${type}' — add it to src/vocabulary.js with a severity`);
  }
  return type;
}

/** Decorates events on the way out. The stored line is never modified. */
function withSeverity(events) {
  return (events ?? []).map((event) => ({ ...event, severity: severityOf(event.type) }));
}

module.exports = { SEVERITY, EVENT_TYPES, severityOf, assertKnownType, withSeverity };
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npm test`
Expected: PASS — the 8 new tests, and the 47 existing ones still green.

- [ ] **Step 5: Commit**

```bash
git add src/vocabulary.js test/vocabulary.test.js
git commit -m "feat: add the event vocabulary and its severity table"
```

---

### Task 2: Route every emission through the guard

**Files:**
- Modify: `src/diff.js` — the `event()` helper (around line 29) and the two `collector_access_*` branches in `diffSnapshots` (around lines 155–170)
- Test: `test/diff.test.js` (append)

**Interfaces:**
- Consumes: `assertKnownType`, `EVENT_TYPES` from Task 1.
- Produces: no new export. The guarantee is structural — `diffSnapshots` cannot emit a type absent from the vocabulary.

The two collector-transition events are currently built as object literals and bypass `event()`. Routing them through it is what makes the guard total.

This task has **no new observable behaviour**: the emitted events keep the exact same shape. Its
value is structural, so the cycle is "pin, refactor, re-run" rather than red-green. The
thirteenth-type protection is proved by Task 1's `assertKnownType` test plus this wiring — once every
emission goes through the guard, the existing suite throws on a type with no severity.

- [ ] **Step 1: Pin the current behaviour**

Append to `test/diff.test.js`:

```js
const { EVENT_TYPES } = require('../src/vocabulary');

const okGovernance = { status: 'ok', data: { roleAssignments: [], locks: [], denyAssignments: [] } };
const deniedGovernance = { status: 'denied', message: 'Authorization failed' };

test('every type the diff engine emits is in the vocabulary', () => {
  // diffSnapshots routes every emission through the vocabulary guard, so this
  // asserts the wiring rather than re-listing the table.
  const pairs = [
    [{ governance: okGovernance }, { governance: deniedGovernance }],
    [{ governance: deniedGovernance }, { governance: okGovernance }],
  ];
  const emitted = new Set();
  for (const [before, after] of pairs) {
    for (const e of diffSnapshots(before, after)) emitted.add(e.type);
  }
  assert.deepEqual([...emitted].sort(), ['collector_access_lost', 'collector_access_restored']);
  for (const type of emitted) assert.ok(EVENT_TYPES.includes(type), type);
});

test('a collector transition keeps its exact shape', () => {
  // The clients decode these four keys; the guard must not reshape them.
  const [event] = diffSnapshots({ governance: okGovernance }, { governance: deniedGovernance });
  assert.deepEqual(Object.keys(event).sort(), ['collector', 'detail', 'subject', 'type']);
  assert.equal(event.type, 'collector_access_lost');
  assert.equal(event.subject, 'governance');
  assert.equal(event.collector, 'governance');
  assert.deepEqual(event.detail, { status: 'denied', message: 'Authorization failed' });
});
```

- [ ] **Step 2: Run the pins and verify they PASS**

Run: `npm test 2>&1 | grep -B2 -A6 "in the vocabulary"`
Expected: **PASS**. They describe what the code already does. If either fails now, stop — the
assumption this task rests on is wrong and the refactor would hide it.

- [ ] **Step 3: Write minimal implementation**

In `src/diff.js`, add the import under `'use strict';`:

```js
const { assertKnownType } = require('./vocabulary');
```

Replace the `event` helper:

```js
function event(type, subject, detail) {
  return { type: assertKnownType(type), subject, detail };
}
```

Replace the two collector branches inside `diffSnapshots`:

```js
    if (wasOk && !isOk) {
      events.push({
        ...event('collector_access_lost', collector, {
          status: is,
          message: after?.[collector]?.message ?? null,
        }),
        collector,
      });
      continue;
    }

    if (!wasOk && isOk) {
      // No data events: the gap against the pre-loss state is not attributable
      // to a real change.
      events.push({ ...event('collector_access_restored', collector, { from: was }), collector });
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npm test`
Expected: PASS — including every pre-existing `diff.test.js` assertion. Those exercise the ten data event types; if any were missing from the vocabulary, the guard would now throw and they would fail. That is the thirteenth-type protection, proved by the existing suite.

- [ ] **Step 5: Commit**

```bash
git add src/diff.js test/diff.test.js
git commit -m "feat: emit every change event through the vocabulary guard"
```

---

### Task 3: Publish the severity, keep the log pure

**Files:**
- Modify: `src/api.js` — the import block, the `/` HTML branch, and the `/api/v1/changes` branch
- Test: `test/api.test.js` (append) and create `test/events.test.js`

**Interfaces:**
- Consumes: `withSeverity` from Task 1.
- Produces: `GET /api/v1/changes` returns `{ limit, events: [{ at, type, subject, collector, detail, severity }] }`.

`test/api.test.js` covers only `tokenMatches` today; there is no handler test. This task adds the first one, with a fake request and response — later batches reuse it.

- [ ] **Step 1: Write the failing test**

Create `test/events.test.js`:

```js
'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { EventLog } = require('../src/events');

test('the log stores facts, not judgments', async () => {
  // Severity is derived on read. Writing it here would freeze a judgment into
  // an append-only file that still holds events from weeks ago.
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), 'asm-events-'));
  const log = new EventLog(dir);

  await log.append(
    [{ type: 'role_removed', subject: 'principal-1', detail: {}, collector: 'governance' }],
    '2026-09-17T08:00:00.000Z'
  );

  const raw = await fs.readFile(path.join(dir, 'events.jsonl'), 'utf8');
  const stored = JSON.parse(raw.trim());
  assert.deepEqual(Object.keys(stored).sort(), ['at', 'collector', 'detail', 'subject', 'type']);
  assert.equal('severity' in stored, false);
});
```

Append to `test/api.test.js`:

```js
const { createHandler } = require('../src/api');

function fakeResponse() {
  const res = { statusCode: 0, headers: {}, body: '' };
  res.writeHead = (status, headers) => { res.statusCode = status; Object.assign(res.headers, headers ?? {}); };
  res.setHeader = (name, value) => { res.headers[name] = value; };
  res.end = (body) => { res.body = body ?? ''; };
  return res;
}

function handlerWith(events) {
  return createHandler({
    config: { token: 's3cret' },
    store: { latest: async () => null },
    log: { read: async () => events },
    runCollection: async () => ({ collectedAt: '2026-09-17T08:00:00.000Z' }),
    now: () => Date.parse('2026-09-17T08:00:00.000Z'),
  });
}

test('the changes route publishes a severity per event', async () => {
  const handle = handlerWith([
    { at: '2026-09-17T08:00:00.000Z', type: 'collector_access_lost', subject: 'governance', detail: {}, collector: 'governance' },
    { at: '2026-09-17T07:50:00.000Z', type: 'probe_status_changed', subject: 'api', detail: {}, collector: 'probes' },
  ]);
  const res = fakeResponse();
  await handle({ url: '/api/v1/changes', method: 'GET', headers: { 'x-sandbox-token': 's3cret' } }, res);

  assert.equal(res.statusCode, 200);
  const body = JSON.parse(res.body);
  assert.equal(body.events[0].severity, 'critical');
  assert.equal(body.events[1].severity, 'informational');
});

test('the changes route still refuses a wrong token', async () => {
  const handle = handlerWith([]);
  const res = fakeResponse();
  await handle({ url: '/api/v1/changes', method: 'GET', headers: { 'x-sandbox-token': 'wrong' } }, res);
  assert.equal(res.statusCode, 401);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm test 2>&1 | grep -A5 "publishes a severity"`
Expected: FAIL — `expected undefined to equal 'critical'`

- [ ] **Step 3: Write minimal implementation**

In `src/api.js`, extend the import block:

```js
const { withSeverity } = require('./vocabulary');
```

In the `/` HTML branch, decorate what the page receives:

```js
      const events = withSeverity(await log.read(20));
```

In the `/api/v1/changes` branch:

```js
      return json(res, 200, { limit, events: withSeverity(await log.read(limit)) });
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npm test`
Expected: PASS — the 3 new tests plus everything that was green before.

- [ ] **Step 5: Commit**

```bash
git add src/api.js test/api.test.js test/events.test.js
git commit -m "feat: publish a severity on every change event"
```

---

### Task 4: Show criticality on the page

**Files:**
- Modify: `src/html.js` — the `table()` helper (around line 35), the `eventRows` construction in `renderPage` (around line 47), and the `<style>` block (around line 120)
- Test: create `test/html.test.js`

**Interfaces:**
- Consumes: the `severity` field each event now carries (Task 3).
- Produces: nothing other modules read. `renderPage` keeps its signature.

Markers match the CLI exactly — `!!` critical, `!` notable, blank informational — so the two surfaces teach the same vocabulary. `EVENT_LABELS` stays here: the server publishes judgments, each surface makes its own words.

- [ ] **Step 1: Write the failing test**

Create `test/html.test.js`:

```js
'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { renderPage } = require('../src/html');

const snapshot = {
  collectedAt: '2026-09-17T08:00:00.000Z',
  apps: { status: 'ok', data: [] },
  probes: { status: 'ok', data: [] },
  resources: { status: 'ok', data: [] },
  plans: { status: 'ok', data: [] },
  budget: { status: 'ok', data: [] },
  governance: { status: 'denied', message: 'Authorization failed' },
};

function page(events) {
  return renderPage({ snapshot, events, ageSeconds: 12, roleHint: '' });
}

test('a critical event is marked and coloured', () => {
  const html = page([
    { at: '2026-09-17T08:00:00.000Z', type: 'collector_access_lost', subject: 'governance', detail: {}, severity: 'critical' },
  ]);
  assert.match(html, /sev-critical/);
  assert.match(html, /!!/);
});

test('an informational event carries no marker', () => {
  const html = page([
    { at: '2026-09-17T08:00:00.000Z', type: 'probe_status_changed', subject: 'api', detail: {}, severity: 'informational' },
  ]);
  assert.doesNotMatch(html, /sev-critical|sev-notable/);
});

test('a denied section still renders as refused, never as an empty table', () => {
  // The rule the whole project exists to protect. Reading a revoked Reader
  // role as "no role assignments" is the false alarm being prevented.
  const html = page([]);
  assert.match(html, /Access denied/);
  assert.match(html, /Authorization failed/);
  // The governance table is not rendered at all — not rendered empty.
  assert.doesNotMatch(html, /Principal/);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm test 2>&1 | grep -A5 "marked and coloured"`
Expected: FAIL — no `sev-critical` in the output

- [ ] **Step 3: Write minimal implementation**

In `src/html.js`, teach `table()` an optional row object. Existing callers pass arrays and are untouched:

```js
function table(headers, rows) {
  if (!rows.length) return '<p class="empty">Nothing to show.</p>';
  const row = (r) => {
    const cells = Array.isArray(r) ? r : r.cells;
    const className = Array.isArray(r) ? '' : ` class="${escape(r.className)}"`;
    return `<tr${className}>${cells.map((c) => `<td>${c}</td>`).join('')}</tr>`;
  };
  return `<div class="scroll"><table>
    <thead><tr>${headers.map((h) => `<th>${escape(h)}</th>`).join('')}</tr></thead>
    <tbody>${rows.map(row).join('')}</tbody>
  </table></div>`;
}
```

Add the marker table above `renderPage`:

```js
// Same markers as `sbw changes`, so both surfaces teach one vocabulary.
const SEVERITY_MARKER = { critical: '!!', notable: '!', informational: '' };
```

Replace the `eventRows` construction:

```js
  const eventRows = (events ?? []).map((e) => ({
    className: e.severity === 'informational' ? '' : `sev-${e.severity}`,
    cells: [
      escape(e.at),
      `${escape(SEVERITY_MARKER[e.severity] ?? '!')} ${escape(EVENT_LABELS[e.type] ?? e.type)}`.trim(),
      escape(e.subject),
      escape(JSON.stringify(e.detail)),
    ],
  }));
```

Add two rules at the end of the `<style>` block, before the closing backtick of the style string:

```css
  tr.sev-critical td { color:var(--bad); }
  tr.sev-notable td { color:var(--warn); }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npm test`
Expected: PASS — 3 new tests, everything else green.

- [ ] **Step 5: Commit**

```bash
git add src/html.js test/html.test.js
git commit -m "feat: mark critical and notable changes on the dashboard"
```

---

### Task 5: Document the contract

**Files:**
- Modify: `docs/api.md` — the change-event payload section
- Modify: `README.md` — the change-types paragraph

**Interfaces:**
- Consumes: the field shipped in Task 3.
- Produces: the written contract `SandboxWatch/Sources/SandboxWatchKit/SandboxAPIContract.swift` will be pinned against in batch A.

- [ ] **Step 1: Update `docs/api.md`**

In the `/api/v1/changes` payload description, add `severity` to the event fields and append:

```markdown
`severity` is one of `informational`, `notable`, `critical`. It is a function of `type`, derived
when the event is read and never stored in the change log — so re-classifying a type later
reclassifies the whole history with it. A client that meets a value it does not know must treat it
as `notable`: visible, but never loud enough to raise an alarm on its own.

| Severity | Types |
|---|---|
| `critical` | `collector_access_lost`, `collector_access_restored` |
| `notable` | `role_added`, `role_removed`, `lock_added`, `lock_removed`, `budget_threshold_crossed` |
| `informational` | `resource_added`, `resource_removed`, `app_state_changed`, `plan_tier_changed`, `probe_status_changed` |
```

- [ ] **Step 2: Update `README.md`**

After the sentence listing the change types, add:

```markdown
Each event also carries a `severity` — `informational`, `notable` or `critical`. Losing or regaining
collector access is the critical pair: it is the incident this project was written after, and it must
never queue behind a probe that flickered.
```

- [ ] **Step 3: Verify the suite and the page**

Run: `npm test`
Expected: PASS, and the count reported has grown from 47 by the tests added in Tasks 1–4.

Run: `node --env-file=.env server.js` then open the page.
Expected: without a managed identity every collector reports `denied` — that is the documented local behaviour, not a failure. The change table is empty; that is normal on a fresh `SNAPSHOT_DIR`.

- [ ] **Step 4: Commit**

```bash
git add docs/api.md README.md
git commit -m "docs: document the severity field on change events"
```

- [ ] **Step 5: Open the pull request**

```bash
git push -u origin <branch>
gh pr create --fill
```

---

## Deliberately not in this plan

- **Deleting the two phantom `deny_assignment_*` branches** and moving the severity table into
  `SandboxAPIContract` as a dated fallback (spec §5.5). Both are Swift, in the `SandboxWatch`
  repository — they belong to batch A's plan, written once this one has shipped.
- **Any client change.** Nothing in `SandboxWatch` is touched by this plan.

## Exit gate for batch 0

Batch A must not start before all of these hold:

- [ ] `npm test` green, with the new tests for the vocabulary, the guard, the log's purity, the API field and the page markers.
- [ ] Zero npm dependencies — `package.json` still has no `dependencies` key.
- [ ] Deployed to the real sandbox, and `curl -H "X-Sandbox-Token: $SANDBOX_TOKEN" https://<app>.azurewebsites.net/api/v1/changes | head` shows `severity` on each event.
- [ ] The deployed page shows `!!` on a `collector_access_lost` if one is present in the log.
- [ ] `events.jsonl` on the deployed instance still has no `severity` key — check one line with
      `az webapp ssh` or the Kudu console.

The last one matters most: it is the difference between a judgment derived and a judgment frozen.
