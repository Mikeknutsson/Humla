import test from "node:test";
import assert from "node:assert/strict";
import {
  canonicalExternalIdentity,
  transactionIdentity,
  resolveHubMapping,
  reconcileImportedLines,
} from "../src/lib/hub/import-reuse-contract.mjs";

const base = {
  tenantId: "944597b6-9c46-4bef-998d-f19e23c4245b",
  source: "workify",
  externalTransactionId: "44155",
  externalLineId: "ST9:1",
  contentVersion: "content-v1",
};

test("Excel/API reimports get the same persistent identity", () => {
  const one = transactionIdentity({ ...base, importBatchId: "excel-1", filename: "orders.xlsx" });
  const two = transactionIdentity({ ...base, importBatchId: "api-2", filename: null });
  assert.equal(one.key, two.key);
  assert.equal(one.status, "identified");
});

test("missing stable line identity must not create a dedup key", () => {
  const identity = transactionIdentity({ ...base, externalLineId: "" });
  assert.equal(identity.status, "needs_review");
  assert.equal(identity.key, null);
});

test("dedup overlapping imports, but retain equal amounts on distinct lines", () => {
  const result = reconcileImportedLines([
    { ...base, amount: 100 },
    { ...base, amount: 100, importBatchId: "again" },
    { ...base, externalLineId: "ST9:2", amount: 100 },
  ]);
  assert.equal(result.accepted.length, 2);
  assert.equal(result.duplicates, 1);
  assert.equal(result.review.length, 0);
});

test("a changed prior source line needs reconciliation and is never added twice", () => {
  const result = reconcileImportedLines([
    base,
    { ...base, contentVersion: "content-v2", amount: 200 },
  ]);
  assert.equal(result.accepted.length, 1);
  assert.equal(result.review[0].reason, "changed_existing_source_line");
});

test("missing content fingerprint fails closed", () => {
  const result = reconcileImportedLines([{ ...base, contentVersion: undefined }]);
  assert.equal(result.accepted.length, 0);
  assert.equal(result.review[0].reason, "missing_source_content_version");
});

test("confirmed Hub mapping is reused across sources and respects dates", () => {
  const rules = [
    { id: "r1", humlaObjectId: "truck-DFC86A", confirmed: true, validFrom: "2026-09-01" },
    { id: "r2", humlaObjectId: "truck-other", confirmed: false, validFrom: "2026-09-01" },
  ];
  assert.deepEqual(resolveHubMapping({ candidates: rules, effectiveDate: "2026-09-30" }), {
    status: "resolved",
    humlaObjectId: "truck-DFC86A",
    ruleIds: ["r1"],
  });
  assert.equal(resolveHubMapping({ candidates: rules, effectiveDate: "2026-08-31" }).status, "needs_review");
});

test("conflicting confirmed economic-unit mapping fails closed", () => {
  const candidates = [
    { id: "a", humlaObjectId: "truck-A", confirmed: true, validFrom: "2026-09-01" },
    { id: "b", humlaObjectId: "truck-B", confirmed: true, validFrom: "2026-09-01" },
  ];
  assert.equal(resolveHubMapping({ candidates, effectiveDate: "2026-09-02" }).reason, "conflicting_confirmed_rules");
});

test("source-specific IDs remain in adapter layer, never replace Humla IDs", () => {
  assert.deepEqual(canonicalExternalIdentity({
    tenantId: base.tenantId, source: "Next", entityType: "project", externalId: "9009",
  }), { tenantId: base.tenantId, source: "next", entityType: "project", externalId: "9009" });
});
