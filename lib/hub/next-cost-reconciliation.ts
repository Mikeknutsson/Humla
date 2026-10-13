/** Review-only reconciliation of overlapping Next imports.
 * Same project/date/amount is a suspicion, NOT proof of a duplicate.
 * Posting requires a stable document+line identity supplied by the source.
 */
export type NextCostCandidate = {
  tenantId?: string;
  sourceSystem?: string;
  id: string;
  batchId: string;
  batchStatus?: string | null;
  rowNumber: number;
  projectReference: string;
  occurredOn: string;
  amount: string;
  sourceContentHash: string;
  sourceDocumentId?: string | null;
  sourceDocumentLineId?: string | null;
  sourceAccount?: string | null;
  sourceDescription?: string | null;
  sourceSupplier?: string | null;
};
export type Reconciliation = {
  rowId: string;
  state: "unique_verified" | "duplicate_verified" | "review_required" | "invalid";
  canonicalRowId?: string;
  reason: string;
};
const norm = (s: string) => s.trim().toUpperCase();
export function reconcileNextCosts(rows: NextCostCandidate[]): Reconciliation[] {
  const bySource = new Map<string, NextCostCandidate[]>();
  const bySignature = new Map<string, NextCostCandidate[]>();
  const sourceKey = (row: NextCostCandidate) => row.sourceDocumentId?.trim() && row.sourceDocumentLineId?.trim()
    ? JSON.stringify([row.tenantId ?? "", row.sourceSystem ?? "next", row.sourceDocumentId.trim(), row.sourceDocumentLineId.trim()]) : null;
  const signature = (row: NextCostCandidate) => JSON.stringify([row.tenantId ?? "", row.sourceSystem ?? "next", norm(row.projectReference), row.occurredOn, row.amount]);
  for (const row of rows) {
    const key = sourceKey(row);
    if (key) bySource.set(key, [...(bySource.get(key) ?? []), row]);
    const sig = signature(row);
    bySignature.set(sig, [...(bySignature.get(sig) ?? []), row]);
  }
  return rows.map(row => {
    if (!row.amount.trim() || !Number.isFinite(Number(row.amount)) || !/^\d{4}-\d{2}-\d{2}$/.test(row.occurredOn))
      return { rowId: row.id, state: "invalid" as const, reason: "invalid_economic_data" };
    if (row.batchStatus !== "completed")
      return { rowId: row.id, state: "review_required" as const, reason: "import_batch_not_completed" };
    const key = sourceKey(row);
    if (key) {
      const peers = bySource.get(key)!;
      // A changed amount/content under the same ID is a correction/conflict, not a duplicate.
      if (!row.sourceContentHash || peers.some(p => p.sourceContentHash !== row.sourceContentHash || signature(p) !== signature(row)))
        return { rowId: row.id, state: "review_required" as const, reason: "conflicting_source_document_line" };
      const canonical = peers.filter(p => p.batchStatus === "completed").sort((a,b) => a.id.localeCompare(b.id))[0];
      if (canonical.id !== row.id)
        return { rowId: row.id, state: "duplicate_verified" as const, canonicalRowId: canonical.id, reason: "same_source_document_line" };
      return { rowId: row.id, state: "unique_verified" as const, reason: "source_document_line_identity" };
    }
    const sig = signature(row);
    const peers = bySignature.get(sig) ?? [];
    return {
      rowId: row.id,
      state: "review_required" as const,
      reason: peers.some(p => p.batchId !== row.batchId) ? "overlapping_import_without_source_line_identity" : "missing_source_line_identity"
    };
  });
}
