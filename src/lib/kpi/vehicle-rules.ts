export type VehicleRule = { column: string; value: string; registration: string };
const normalized = (value: string) => value.trim().toUpperCase();
export const registrationValue = (value: string) => value.toUpperCase().replace(/[\s-]/g, "");
export const isRegistration = (value: string) => /^[A-Z]{3}[0-9]{2}[A-Z0-9]$/.test(value);

export function parseVehicleRules(text: string, headers: string[]): VehicleRule[] {
  if (text.length > 100_000) throw new Error("För många fordonskopplingar.");
  const rules = text.split(/\r?\n/).filter((line) => line.trim()).map((line, index) => {
    const parts = line.split(";").map((part) => part.trim());
    if (parts.length !== 3 || !headers.includes(parts[0]) || !parts[1] || !isRegistration(registrationValue(parts[2]))) {
      throw new Error(`Fordonskoppling ${index + 1}: ange befintligt kolumnnamn;exakt värde;svenskt regnummer.`);
    }
    return { column: parts[0], value: normalized(parts[1]), registration: registrationValue(parts[2]) };
  });
  const seen = new Map<string, string>();
  for (const rule of rules) {
    const key = JSON.stringify([rule.column, rule.value]);
    if (seen.has(key) && seen.get(key) !== rule.registration) throw new Error("Samma kolumnvärde är kopplat till flera fordon. Lös konflikten före import.");
    seen.set(key, rule.registration);
  }
  return rules;
}

export function resolveVehicle(source: Record<string, string>, raw: string, rules: VehicleRule[]) {
  const direct = registrationValue(raw);
  const matched = rules.filter((rule) => normalized(source[rule.column] ?? "") === rule.value);
  const candidates = new Set(matched.map((rule) => rule.registration));
  if (isRegistration(direct)) candidates.add(direct);
  if (candidates.size > 1) return { registration: null, error: "Motstridiga fordonskopplingar", matched };
  if (candidates.size === 1) return { registration: [...candidates][0], error: null, matched };
  return { registration: null, error: raw.trim() ? "Fordonsbeteckning saknar verifierad regnummerkoppling" : null, matched };
}
