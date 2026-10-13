/** Deterministic, non-posting vehicle attribution for imported cost lines.
 * Never changes ledger totals: a line receives at most one vehicle or review status.
 */
export type PersonnelVehicleMapping = {
  projectReference: string;
  vehicleRegistration: string;
  validFrom: string | null;
  validTo: string | null;
  enabled: boolean;
};
export type CostLine = {
  source: string;
  sourceLineId: string;
  date: string;
  personnelProject?: string | null;
  registration?: string | null;
  transpaRegistration?: string | null;
  historicalTranspaRegistrations?: string[] | null;
  workifyRegistration?: string | null;
};
export type Attribution = {
  key: string;
  vehicle: string | null;
  method: "source_registration" | "transpa" | "workify" | "personnel" | "review";
  reason?: string;
};
const normalized = (v?: string | null) => (v ?? "").trim().toUpperCase().replace(/\s+/g, "");
const inPeriod = (date: string, m: PersonnelVehicleMapping) =>
  (!m.validFrom || date >= m.validFrom) && (!m.validTo || date <= m.validTo);
export function attributeCostLine(line: CostLine, mappings: PersonnelVehicleMapping[]): Attribution {
  const key = [line.source.trim().toLowerCase(), line.sourceLineId.trim()].join(":");
  if (!line.source.trim() || !line.sourceLineId.trim())
    return { key, vehicle: null, method: "review", reason: "missing_source_line_identity" };
  const direct = normalized(line.registration);
  if (direct) return { key, vehicle: direct, method: "source_registration" };
  const historical = [...new Set((line.historicalTranspaRegistrations ?? []).map(normalized).filter(Boolean))];
  if (historical.length > 1) return { key, vehicle: null, method: "review", reason: "multiple_historical_transpa_vehicles" };
  if (historical.length === 1) return { key, vehicle: historical[0], method: "transpa" };
  const transpa = normalized(line.transpaRegistration);
  if (transpa) return { key, vehicle: transpa, method: "transpa" };
  const workify = normalized(line.workifyRegistration);
  if (workify) return { key, vehicle: workify, method: "workify" };
  const candidates = [...new Set(mappings
    .filter(m => m.enabled && m.projectReference === line.personnelProject && inPeriod(line.date, m))
    .map(m => normalized(m.vehicleRegistration)).filter(Boolean))];
  if (candidates.length === 1) return { key, vehicle: candidates[0], method: "personnel" };
  return { key, vehicle: null, method: "review", reason: candidates.length ? "ambiguous_personnel_vehicle" : "unmatched" };
}
/** Returns unique source rows, with conflicting duplicate identities held for review.
 * Caller must validate financial amounts and retain an audit trail before posting.
 */
export function attributeUniqueCostLines(lines: CostLine[], mappings: PersonnelVehicleMapping[]) {
  const grouped = new Map<string, CostLine[]>();
  for (const line of lines) {
    const key = [line.source.trim().toLowerCase(), line.sourceLineId.trim()].join(":");
    const group = grouped.get(key) ?? [];
    group.push(line);
    grouped.set(key, group);
  }
  return [...grouped.values()].map(group => {
    const first = attributeCostLine(group[0], mappings);
    if (group.length > 1 && group.some(line => JSON.stringify(line) !== JSON.stringify(group[0])))
      return { ...first, vehicle: null, method: "review" as const, reason: "conflicting_duplicate_source_line" };
    return first;
  });
}
