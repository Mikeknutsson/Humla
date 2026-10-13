/** Review-only reconciliation of overlapping Next imports.
 * Same project/date/amount is a suspicion, NOT proof of a duplicate.
 * Posting requires a stable document+line identity supplied by the source.
 */
export type NextCostCandidate = {
  id: string;
  batchId: string;
  rowNumber: number;
  projectReference: string;
  occurredOn: string;
  amount: string;
  sourceContentHash: string;
  sourceDocumentId?: string | null;
  sourceDocumentLineId?: string | null;
};
export type Reconciliation = {
  rowId: string;
  state: "unique_verified" | "duplicate_verified" | "review_required";
  canonicalRowId?: string;
  reason: string;
};
const norm = (s: string) => s.trim().toUpperCase();
export function reconcileNextCosts(rows: NextCostCandidate[]): Reconciliation[] {
  const bySource = new Map<string, string>();
  const bySignature = new Map<string, NextCostCandidate[]>();
  for (const row of rows) {
    const sig = [norm(row.projectReference), row.occurredOn, row.amount].join("|");
    bySignature.set(sig, [...(bySignature.get(sig) ?? []), row]);
  }
  return rows.map(row => {
    const sourceKey = row.sourceDocumentId?.trim() && row.sourceDocumentLineId?.trim()
      ? [norm(row.sourceDocumentId), norm(row.sourceDocumentLineId)].join("|")
      : null;
    if (sourceKey) {
      const existing = bySource.get(sourceKey);
      if (existing && existing !== row.id)
        return { rowId: row.id, state: "duplicate_verified" as const, canonicalRowId: existing, reason: "same_source_document_line" };
      bySource.set(sourceKey, row.id);
      return { rowId: row.id, state: "unique_verified" as const, reason: "source_document_line_identity" };
    }
    const sig = [norm(row.projectReference), row.occurredOn, row.amount].join("|");
    const peers = bySignature.get(sig) ?? [];
    return {
      rowId: row.id,
      state: "review_required" as const,
      reason: peers.some(p => p.batchId !== row.batchId) ? "overlapping_import_without_source_line_identity" : "missing_source_line_identity"
    };
  });
}
