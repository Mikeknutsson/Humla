export type HubImportSource = "workify" | "next" | "transpa" | "fordonskontrollen" | "bsmart" | "ps_olja" | "other";
export function normalizeSource(source: string): HubImportSource;
export function canonicalExternalIdentity(input: {
  tenantId: string; source: string; entityType: string; externalId: string;
}): { tenantId: string; source: HubImportSource; entityType: string; externalId: string };
export function transactionIdentity(input: {
  tenantId: string; source: string; externalTransactionId?: string | null; externalLineId?: string | null;
}): { key: string | null; status: "identified" | "needs_review"; reason?: string };
export function resolveHubMapping(input: {
  candidates?: Array<{ id?: string; confirmed: boolean; humlaObjectId?: string | null; validFrom: string; validTo?: string | null; enabled?: boolean }>;
  effectiveDate: string;
}): { status: "resolved"; humlaObjectId: string; ruleIds: string[] } | { status: "needs_review"; reason: string; candidates: string[] };
export function reconcileImportedLines<T extends {
  tenantId: string; source: string; externalTransactionId?: string | null;
  externalLineId?: string | null; contentVersion?: string; contentFingerprint?: string;
}>(records: T[]): {
  accepted: T[];
  review: Array<{ record: T; reason: string; transactionKey?: string }>;
  duplicates: number;
};
