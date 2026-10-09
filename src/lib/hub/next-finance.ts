/** Hub-owned preparation layer. No NeXT HTTP endpoint or credential is assumed.
 * A vendor adapter must supply this INTERNAL contract after API discovery.
 * Shadow runs never publish financial facts or replace manual imports.
 */
export const NEXT_FINANCE_CONTRACT = {
  version: 1,
  status: 'prepared_not_connected',
  mode: 'shadow_only',
  entities: ['projects', 'costs', 'revenues', 'payroll', 'customer_invoices', 'supplier_invoices'],
  includesArchivedProjects: true,
  affectsKpi: false,
  blockers: ['verified_api_schema', 'vault_credentials', 'durable_stage_sink', 'historical_project_mapping', 'file_api_reconciliation', 'approved_activation'],
} as const;

export type NextFinanceEntity = typeof NEXT_FINANCE_CONTRACT.entities[number];
export type NextSourceRecord = {
  externalId: string;
  updatedAt: string;
  raw: Record<string, unknown>;
  projectExternalId?: string;
  project?: { name: string; status: string };
  finance?: {
    /** Stable, authoritative ledger ROW ID; not invoice number or voucher alone. */
    ledgerEntryId: string;
    occurredOn: string;
    amountMinor: number;
    currency: 'SEK';
    account: string;
    description: string;
    voucherNumber?: string;
    invoiceNumber?: string;
  };
  deleted?: boolean;
};
export type NextFinanceScope = { tenantId: string; connectionId: string };
export type NextCanonicalProject = { objectId: string; confirmed: true };
export type NextShadowRecord = {
  sourceKey: string;
  economicKey: string | null;
  payloadHash: string;
  scope: NextFinanceScope;
  entity: NextFinanceEntity;
  source: NextSourceRecord;
  projectObjectId: string | null;
  reviewReason: string | null;
  publishable: false;
};
export interface NextFinanceTransport {
  /** Read-only, bounded HTTP with validated host and server-side Vault secrets.
   * Translate actual pagination/field names here, not in Dashboard.
   */
  readPage(input: {
    entity: NextFinanceEntity; cursor: string | null;
    updatedSince: string | null; includeArchived: true;
  }): Promise<{ records: NextSourceRecord[]; nextCursor: string | null }>;
}
export interface NextFinanceStageSink {
  /** Must hold a per-connection lock and create a durable inactive generation. */
  beginRun(scope: NextFinanceScope): Promise<string>;
  /** Idempotent on sourceKey + payloadHash. Preserve revisions and raw payloads. */
  stagePage(runId: string, records: NextShadowRecord[]): Promise<void>;
  /** Atomically complete the generation and save checkpoint; NEVER activate KPI. */
  completeRun(runId: string, result: { rows: number; reviewRows: number; checkpoint: string }): Promise<void>;
  /** Partial/failed runs remain inactive and never advance the checkpoint. */
  failRun(runId: string, errorCode: string): Promise<void>;
}
export type NextFinancePreparedConfig = {
  enabled: boolean;
  schemaVerified: boolean;
  credentialsConfigured: boolean;
  includeArchived: boolean;
  mode: 'shadow_only';
  entities: NextFinanceEntity[];
};

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
function required(value: unknown): value is string {
  return typeof value === 'string' && value.trim().length > 0 && value.length <= 500;
}
function dateOnly(value: string) {
  return /^\d{4}-\d{2}-\d{2}$/.test(value) && Number.isFinite(Date.parse(value)) && new Date(value).toISOString().slice(0, 10) === value;
}
function timestamp(value: unknown): value is string {
  return typeof value === 'string' && dateOnly(value.slice(0, 10)) && /^\d{4}-\d{2}-\d{2}T/.test(value) && /(Z|[+-]\d{2}:\d{2})$/.test(value) && Number.isFinite(Date.parse(value));
}
function canonicalJson(value: unknown): string {
  if (value === null || typeof value === 'string' || typeof value === 'boolean') return JSON.stringify(value);
  if (typeof value === 'number' && Number.isFinite(value)) return JSON.stringify(value);
  if (Array.isArray(value)) return '[' + value.map(canonicalJson).join(',') + ']';
  if (value && typeof value === 'object') return '{' + Object.entries(value).filter(([, v]) => v !== undefined).sort(([a], [b]) => a.localeCompare(b)).map(([k, v]) => JSON.stringify(k) + ':' + canonicalJson(v)).join(',') + '}';
  throw new Error('next_invalid_json');
}
async function hash(value: unknown) {
  const bytes = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(canonicalJson(value)));
  return [...new Uint8Array(bytes)].map(x => x.toString(16).padStart(2, '0')).join('');
}

export async function prepareNextShadowRecord(
  scope: NextFinanceScope, entity: NextFinanceEntity, record: NextSourceRecord,
  resolveProject: (scope: NextFinanceScope, externalId: string) => Promise<NextCanonicalProject | null>,
): Promise<NextShadowRecord> {
  if (!uuid.test(scope.tenantId) || !uuid.test(scope.connectionId)) throw new Error('next_invalid_scope');
  if (!NEXT_FINANCE_CONTRACT.entities.includes(entity)) throw new Error('next_invalid_entity');
  if (!required(record.externalId) || !timestamp(record.updatedAt) || !record.raw || Array.isArray(record.raw) || typeof record.raw !== 'object' || (record.deleted !== undefined && typeof record.deleted !== 'boolean')) throw new Error('next_invalid_source_record');
  const financial = ['costs', 'revenues', 'payroll'].includes(entity);
  if (entity === 'projects' && !record.deleted && (!required(record.project?.name) || !required(record.project?.status))) throw new Error('next_project_metadata_required');
  if (financial && !record.deleted) {
    const f = record.finance;
    if (!f || !required(f.ledgerEntryId) || !required(f.account) || !dateOnly(f.occurredOn) || !Number.isSafeInteger(f.amountMinor) || f.currency !== 'SEK' || typeof f.description !== 'string') throw new Error('next_invalid_financial_record');
    // Credits retain their sign. Do not derive a second wage amount from hours.
  }
  const externalProject = entity === 'projects' ? record.externalId : record.projectExternalId;
  if (externalProject !== undefined && !required(externalProject)) throw new Error('next_invalid_project_reference');
  const resolved = externalProject ? await resolveProject(scope, externalProject) : null;
  if (resolved && (resolved.confirmed !== true || !uuid.test(resolved.objectId))) throw new Error('next_unconfirmed_identity');
  return {
    sourceKey: JSON.stringify([scope.tenantId, scope.connectionId, entity, record.externalId]),
    economicKey: record.finance ? JSON.stringify([scope.tenantId, scope.connectionId, 'next_ledger_row', record.finance.ledgerEntryId]) : null,
    payloadHash: await hash(record), scope, entity, source: record,
    projectObjectId: resolved?.objectId ?? null,
    reviewReason: record.deleted ? 'source_deleted_requires_review' : resolved ? null : 'project_identity_unresolved',
    publishable: false,
  };
}

/** Server/worker entry point. Disabled unless ALL explicit prerequisites hold.
 * Authentication/tenant authorization belongs to the calling worker; this is
 * not an HTTP endpoint. No transport or durable sink is configured by default.
 */
export async function runNextFinanceShadow(input: {
  scope: NextFinanceScope;
  config: NextFinancePreparedConfig;
  transport: NextFinanceTransport;
  sink: NextFinanceStageSink;
  resolveProject: (scope: NextFinanceScope, externalId: string) => Promise<NextCanonicalProject | null>;
  updatedSince?: string | null;
  now?: () => Date;
  maxPages?: number;
  maxRecordsPerPage?: number;
}) {
  const { config, scope, transport, sink } = input;
  if (!config.enabled || !config.schemaVerified || !config.credentialsConfigured || !config.includeArchived || config.mode !== 'shadow_only') throw new Error('next_finance_not_ready');
  if (!uuid.test(scope.tenantId) || !uuid.test(scope.connectionId)) throw new Error('next_invalid_scope');
  if (!config.entities.length || new Set(config.entities).size !== config.entities.length || config.entities.some(x => !NEXT_FINANCE_CONTRACT.entities.includes(x))) throw new Error('next_invalid_entities');
  const updatedSince = input.updatedSince ?? null;
  if (updatedSince !== null && !timestamp(updatedSince)) throw new Error('next_invalid_checkpoint');
  // Watermark is captured BEFORE reading; the next run must use an overlap
  // window to account for vendor timestamp precision / late updates.
  const checkpoint = (input.now?.() ?? new Date()).toISOString();
  if (updatedSince && Date.parse(updatedSince) > Date.parse(checkpoint)) throw new Error('next_future_checkpoint');
  const maxPages = input.maxPages ?? 1000, maxRecords = input.maxRecordsPerPage ?? 1000;
  if (!Number.isSafeInteger(maxPages) || maxPages < 1 || !Number.isSafeInteger(maxRecords) || maxRecords < 1) throw new Error('next_invalid_limits');
  const runId = await sink.beginRun(scope);
  let rows = 0, reviewRows = 0;
  const stagedKeys = new Map<string, string>();
  try {
    for (const entity of config.entities) {
      let cursor: string | null = null, pageCount = 0;
      const seen = new Set<string>();
      do {
        if (++pageCount > maxPages) throw new Error('next_page_limit');
        const page = await transport.readPage({ entity, cursor, updatedSince, includeArchived: true });
        if (!Array.isArray(page.records) || page.records.length > maxRecords || (page.nextCursor !== null && !required(page.nextCursor))) throw new Error('next_invalid_page');
        const prepared: NextShadowRecord[] = [];
        for (const record of page.records) {
          const row = await prepareNextShadowRecord(scope, entity, record, input.resolveProject);
          const prior = stagedKeys.get(row.sourceKey);
          if (prior === row.payloadHash) continue; // replay/overlapping pages
          if (prior !== undefined) throw new Error('next_conflicting_source_revision');
          stagedKeys.set(row.sourceKey, row.payloadHash);
          prepared.push(row);
        }
        await sink.stagePage(runId, prepared);
        rows += prepared.length; reviewRows += prepared.filter(x => x.reviewReason !== null).length;
        cursor = page.nextCursor;
        if (cursor !== null) {
          if (seen.has(cursor)) throw new Error('next_repeated_cursor');
          seen.add(cursor);
        }
      } while (cursor !== null);
    }
    await sink.completeRun(runId, { rows, reviewRows, checkpoint });
    return { runId, rows, reviewRows, checkpoint, affectsKpi: false as const };
  } catch (error) {
    // Never store vendor response bodies, URLs or tokens in public diagnostics.
    const code = error instanceof Error && /^next_[a-z_]+$/.test(error.message) ? error.message : 'next_shadow_failed';
    await sink.failRun(runId, code);
    throw new Error(code);
  }
}
