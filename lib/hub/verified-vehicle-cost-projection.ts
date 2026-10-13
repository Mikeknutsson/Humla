import { reconcileNextCosts, type NextCostCandidate } from "./next-cost-reconciliation";
import { attributeCostLine, type PersonnelVehicleMapping } from "./personnel-vehicle-attribution";

/** Shared read-only projection for Hub, KPI and other modules.
 * Does not mutate imported rows or post costs. Fail closed on uncertain imports.
 */
export type ImportedCostRow = NextCostCandidate & {
  sourceSystem: string;
  costCenter: string | null;
  vehicleRegistration: string | null;
  employeeProject: string | null;
};
export type ProjectedCost = {
  sourceRowId: string;
  projectReference: string;
  amount: string;
  state: "ready" | "review";
  vehicle: string | null;
  reason: string;
  canonicalRowId?: string;
};
export function projectVerifiedVehicleCosts(
  rows: ImportedCostRow[],
  mappings: PersonnelVehicleMapping[]
): ProjectedCost[] {
  const reconciled = reconcileNextCosts(rows);
  return rows.map((row, i) => {
    const review = reconciled[i];
    const base = { sourceRowId: row.id, projectReference: row.projectReference, amount: row.amount };
    if (review.state !== "unique_verified")
      return { ...base, state: "review", vehicle: null, reason: review.reason, canonicalRowId: review.canonicalRowId } as ProjectedCost;
    const attribution = attributeCostLine({
      source: row.sourceSystem,
      sourceLineId: row.id,
      date: row.occurredOn,
      personnelProject: row.employeeProject ?? row.projectReference,
      registration: row.vehicleRegistration
    }, mappings);
    if (!attribution.vehicle)
      return { ...base, state: "review", vehicle: null, reason: attribution.reason ?? "unmatched" };
    return { ...base, state: "ready", vehicle: attribution.vehicle, reason: attribution.method };
  });
}
