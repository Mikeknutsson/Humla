/**
 * Humla Hub import contract (CORE-001).
 *
 * Adapters for Excel, API and webhooks must emit the same normalized envelope.
 * This module never creates canonical identities or allocations on guesses.
 *
 * Compatibility: legacy imports are explicitly marked for review rather than
 * silently treated as unique or attributed to a vehicle.
 */

const SOURCES = new Set(["workify", "next", "transpa", "fordonskontrollen", "bsmart", "ps_olja", "other"]);
const ID_RE = /^[^\u0000-\u001f\u007f]{1,200}$/u;

export function normalizeSource(source) {
  const value = String(source ?? "").trim().toLowerCase().replace(/[\s-]+/g, "_");
  if (!SOURCES.has(value)) throw new Error("Unknown import source: " + value);
  return value;
}

function requiredId(value, label) {
  const text = String(value ?? "").trim();
  if (!ID_RE.test(text)) throw new Error(label + " must be a stable nonempty identifier");
  return text;
}

export function canonicalExternalIdentity({ tenantId, source, entityType, externalId }) {
  return {
    tenantId: requiredId(tenantId, "tenantId"),
    source: normalizeSource(source),
    entityType: requiredId(entityType, "entityType"),
    externalId: requiredId(externalId, "externalId"),
  };
}

/**
 * The identity must be a stable transaction/line ID, not a row index, upload
 * filename, or import batch ID. Rows lacking one are review-only.
 *
 * A fingerprint is intentionally *not* invented from amount/date alone:
 * repeated real work at equal prices must not be silently deduplicated.
 */
export function transactionIdentity(input) {
  const { tenantId, source, externalTransactionId, externalLineId } = input;
  const t = requiredId(tenantId, "tenantId");
  const s = normalizeSource(source);
  if (!externalTransactionId || externalLineId === null || externalLineId === undefined || externalLineId === "") {
    return { key: null, status: "needs_review", reason: "missing_stable_source_transaction_or_line_id" };
  }
  const tx = requiredId(externalTransactionId, "externalTransactionId");
  const line = requiredId(externalLineId, "externalLineId");
  return { key: JSON.stringify([t, s, tx, line]), status: "identified" };
}

/**
 * Only persistent, confirmed, date-applicable Hub rules can auto-allocate.
 * Matching the same external name or vehicle registration is merely evidence.
 */
export function resolveHubMapping({ candidates = [], effectiveDate }) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(String(effectiveDate ?? ""))) {
    throw new Error("effectiveDate must be YYYY-MM-DD");
  }
  const eligible = candidates.filter((rule) =>
    rule.confirmed === true &&
    rule.humlaObjectId &&
    rule.validFrom <= effectiveDate &&
    (!rule.validTo || effectiveDate <= rule.validTo) &&
    rule.enabled !== false
  );
  const objects = [...new Set(eligible.map((rule) => rule.humlaObjectId))];
  if (objects.length === 1) {
    return {
      status: "resolved",
      humlaObjectId: objects[0],
      ruleIds: [...new Set(eligible.map((rule) => rule.id).filter(Boolean))],
    };
  }
  return {
    status: "needs_review",
    reason: objects.length > 1 ? "conflicting_confirmed_rules" : "no_applicable_confirmed_rule",
    candidates: objects,
  };
}

/**
 * Prevent the same source transaction line from being counted more than once.
 * If the provider changed a previously imported line, send it to reconciliation
 * rather than add the new amount on top of the old amount.
 */
export function reconcileImportedLines(records) {
  const seen = new Map();
  const accepted = [];
  const review = [];
  let duplicates = 0;
  for (const record of records) {
    const identity = transactionIdentity(record);
    if (!identity.key) {
      review.push({ record, reason: identity.reason });
      continue;
    }
    const signature = record.contentVersion ?? record.contentFingerprint;
    if (typeof signature !== "string" || !signature.trim()) {
      review.push({ record, reason: "missing_source_content_version" });
      continue;
    }
    const previous = seen.get(identity.key);
    if (!previous) {
      seen.set(identity.key, signature);
      accepted.push(record);
    } else if (previous === signature) {
      duplicates++;
    } else {
      // Caller must reconcile the changed line against persisted history.
      review.push({ record, reason: "changed_existing_source_line", transactionKey: identity.key });
    }
  }
  return { accepted, review, duplicates };
}

/**
 * Read-only comparison for cumulative snapshots, such as Workify order exports.
 * Never sum different snapshots as additional turnover. Every later snapshot
 * replaces the earlier value of the same source order in this control view.
 * A zero-value or invalid amount stays visible in the review bucket.
 *
 * This is a reconciliation helper, NOT an instruction to persist accounting
 * corrections without verifying source dates and the accounting ledger.
 */
export function reconcileOrderSnapshots({ previous = [], latest = [] }) {
  function index(rows) {
    const orders = new Map();
    for (const row of rows) {
      const key = String(row.orderNumber ?? "").trim();
      const amount = Number(row.amount);
      if (!key || !Number.isFinite(amount)) {
        throw new Error("Snapshot rows require orderNumber and finite amount");
      }
      const existing = orders.get(key) ?? { amount: 0, invalidAmount: 0, rows: 0 };
      existing.amount += amount;
      if (row.isValid !== true) existing.invalidAmount += amount;
      existing.rows++;
      orders.set(key, existing);
    }
    return orders;
  }
  const before = index(previous), after = index(latest);
  const keys = new Set([...before.keys(), ...after.keys()]);
  const changedOrders = [], newOrders = [], removedOrders = [];
  for (const key of keys) {
    const prior = before.get(key), current = after.get(key);
    if (!prior) newOrders.push(key);
    else if (!current) removedOrders.push(key);
    else if (Math.round((prior.amount-current.amount)*100) !== 0 || prior.rows !== current.rows) changedOrders.push(key);
  }
  const sum = (orders, field) => [...orders.values()].reduce((total, row) => total+row[field], 0);
  return {
    previousTotal: sum(before, "amount"),
    latestTotal: sum(after, "amount"),
    latestUnreviewedAmount: sum(after, "invalidAmount"),
    orderCount: after.size,
    newOrders,
    changedOrders,
    removedOrders,
    // A vanished order must be reviewed, not silently written off.
    status: removedOrders.length > 0 ? "needs_review" : "comparable",
  };
}
