import assert from 'node:assert/strict';
import fs from 'node:fs';
import ts from 'typescript';
import { test } from 'node:test';

const compiled = ts.transpileModule(fs.readFileSync('src/lib/hub/next-finance.ts', 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 },
}).outputText;
const { NEXT_FINANCE_CONTRACT, prepareNextShadowRecord, runNextFinanceShadow } = await import('data:text/javascript;base64,' + Buffer.from(compiled).toString('base64'));
const scope = { tenantId: '944597b6-9c46-4bef-998d-f19e23c4245b', connectionId: '4508d5ad-bd4e-4ca9-9cbf-ff45a0395a34' };
const project = { objectId: '11111111-1111-4111-8111-111111111111', confirmed: true };
const record = () => ({ externalId: 'ledger-12', updatedAt: '2026-10-09T12:00:00Z', raw: { account: '4600', amount: -123.45 }, projectExternalId: '12422', finance: { ledgerEntryId: 'ledger-12', occurredOn: '2026-09-30', amountMinor: -12345, currency: 'SEK', account: '4600', description: 'Kredit intern transport' } });
const config = { enabled: true, schemaVerified: true, credentialsConfigured: true, includeArchived: true, mode: 'shadow_only', entities: ['costs'] };
function fixture(readPage) {
  const calls = [], staged = [];
  return {
    calls, staged, input: {
      scope, config, transport: { readPage }, resolveProject: async () => project,
      now: () => new Date('2026-10-09T13:00:00Z'),
      sink: {
        beginRun: async s => { calls.push(['begin', s]); return 'run-1'; },
        stagePage: async (id, rows) => { calls.push(['stage', id]); staged.push(...rows); },
        completeRun: async (id, result) => calls.push(['complete', id, result]),
        failRun: async (id, code) => calls.push(['fail', id, code]),
      },
    },
  };
}
test('preparation is disconnected and never affects KPI', () => {
  assert.equal(NEXT_FINANCE_CONTRACT.affectsKpi, false);
  assert.equal(NEXT_FINANCE_CONTRACT.mode, 'shadow_only');
  assert.ok(NEXT_FINANCE_CONTRACT.blockers.includes('durable_stage_sink'));
});
test('disabled, unverified and missing credential gates cause no reads or writes', async () => {
  for (const gate of ['enabled', 'schemaVerified', 'credentialsConfigured', 'includeArchived']) {
    const f = fixture(async () => { throw new Error('must not read'); });
    await assert.rejects(runNextFinanceShadow({ ...f.input, config: { ...config, [gate]: false } }), /next_finance_not_ready/);
    assert.equal(f.calls.length, 0);
  }
});
test('canonical identity, signed credit and stable row provenance are retained', async () => {
  const r = await prepareNextShadowRecord(scope, 'costs', record(), async (s, ref) => {
    assert.deepEqual(s, scope); assert.equal(ref, '12422'); return project;
  });
  assert.equal(r.source.finance.amountMinor, -12345);
  assert.equal(r.projectObjectId, project.objectId);
  assert.equal(r.reviewReason, null); assert.equal(r.publishable, false);
  const reordered = record(); reordered.raw = { amount: -123.45, account: '4600' };
  const same = await prepareNextShadowRecord(scope, 'costs', reordered, async () => project);
  assert.equal(r.payloadHash, same.payloadHash); assert.equal(r.sourceKey, same.sourceKey);
  const wage = await prepareNextShadowRecord(scope, 'payroll', record(), async () => project);
  assert.equal(r.economicKey, wage.economicKey, 'a payroll classification is not a second economic row');
  const changed = record(); changed.finance.amountMinor = 10000;
  const revision = await prepareNextShadowRecord(scope, 'costs', changed, async () => project);
  assert.equal(r.sourceKey, revision.sourceKey); assert.notEqual(r.payloadHash, revision.payloadHash);
  const otherScope = await prepareNextShadowRecord({ ...scope, tenantId: project.objectId }, 'costs', record(), async () => project);
  assert.notEqual(r.sourceKey, otherScope.sourceKey);
});
test('unknown and archived projects are preserved, never guessed', async () => {
  const unknown = await prepareNextShadowRecord(scope, 'costs', record(), async () => null);
  assert.equal(unknown.projectObjectId, null); assert.equal(unknown.reviewReason, 'project_identity_unresolved');
  const archived = await prepareNextShadowRecord(scope, 'projects', { externalId: '12422', updatedAt: record().updatedAt, raw: { archived: true }, project: { name: 'Historiskt projekt', status: 'closed' } }, async () => null);
  assert.equal(archived.source.project.status, 'closed'); assert.equal(archived.publishable, false);
  await assert.rejects(prepareNextShadowRecord(scope, 'costs', record(), async () => ({ ...project, confirmed: false })), /next_unconfirmed_identity/);
});
test('invalid monetary amounts, dates, currency and row identities fail closed', async () => {
  for (const patch of [{ amountMinor: 12.5 }, { amountMinor: NaN }, { currency: 'EUR' }, { occurredOn: '2026-02-30' }, { ledgerEntryId: '' }]) {
    const r = record(); Object.assign(r.finance, patch);
    await assert.rejects(prepareNextShadowRecord(scope, 'costs', r, async () => project), /next_invalid_financial_record/);
  }
});
test('all pages include archived projects; checkpoint completes only after staging', async () => {
  const requests = [];
  const f = fixture(async request => {
    requests.push(request);
    const r = record(); r.externalId += request.cursor ?? 'first'; r.finance.ledgerEntryId = r.externalId;
    return { records: [r], nextCursor: request.cursor === null ? 'second' : null };
  });
  const result = await runNextFinanceShadow(f.input);
  assert.deepEqual(requests.map(x => x.cursor), [null, 'second']);
  assert.ok(requests.every(x => x.includeArchived));
  assert.equal(result.rows, 2); assert.equal(result.affectsKpi, false);
  assert.deepEqual(f.calls.map(x => x[0]), ['begin', 'stage', 'stage', 'complete']);
  assert.equal(result.checkpoint, '2026-10-09T13:00:00.000Z');
});
test('failed later pages do not complete or expose secrets in diagnostics', async () => {
  const f = fixture(async ({ cursor }) => {
    if (cursor) throw new Error('Bearer secret-token raw vendor body');
    return { records: [record()], nextCursor: 'second' };
  });
  await assert.rejects(runNextFinanceShadow(f.input), /next_shadow_failed/);
  assert.deepEqual(f.calls.map(x => x[0]), ['begin', 'stage', 'fail']);
  assert.equal(f.calls.at(-1)[2], 'next_shadow_failed');
});
test('pagination loops and storage failures cannot advance checkpoints', async () => {
  const f = fixture(async () => ({ records: [], nextCursor: 'loop' }));
  await assert.rejects(runNextFinanceShadow(f.input), /next_repeated_cursor/);
  assert.ok(!f.calls.some(x => x[0] === 'complete'));
  const failed = fixture(async () => ({ records: [record()], nextCursor: null }));
  failed.input.sink.stagePage = async () => { throw new Error('db connection detail'); };
  await assert.rejects(runNextFinanceShadow(failed.input), /next_shadow_failed/);
  assert.ok(!failed.calls.some(x => x[0] === 'complete'));
});
test('replayed rows count once and conflicting revisions block completion', async () => {
  const replay = fixture(async ({ cursor }) => ({ records: [record()], nextCursor: cursor ? null : 'second' }));
  const result = await runNextFinanceShadow(replay.input);
  assert.equal(result.rows, 1); assert.equal(replay.staged.length, 1);
  const conflict = fixture(async ({ cursor }) => {
    const r = record(); if (cursor) r.finance.amountMinor = 999;
    return { records: [r], nextCursor: cursor ? null : 'second' };
  });
  await assert.rejects(runNextFinanceShadow(conflict.input), /next_conflicting_source_revision/);
  assert.ok(!conflict.calls.some(x => x[0] === 'complete'));
});
