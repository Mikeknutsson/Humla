/** Read-only historical TransPA evidence; never extrapolate a driver's current vehicle to an earlier date. */
export type HistoricalTrip = {
  employeeNumber: string;
  date: string;
  vehicleRegistrations: string[];
};
export type HistoricalDecision = {
  employeeNumber: string;
  date: string;
  registration: string | null;
  state: "verified" | "review";
  reason: string;
};
const norm = (value: string) => value.toUpperCase().replace(/\s/g, "");
export function resolveHistoricalTrips(trips: HistoricalTrip[]): HistoricalDecision[] {
  const days = new Map<string, Set<string>>();
  for (const trip of trips) {
    if (trip.date < "2025-09-01") continue;
    const key = trip.employeeNumber.trim() + "|" + trip.date;
    const vehicles = days.get(key) ?? new Set<string>();
    for (const registration of trip.vehicleRegistrations) {
      if (registration.trim()) vehicles.add(norm(registration));
    }
    days.set(key, vehicles);
  }
  return [...days.entries()].map(([key, vehicles]) => {
    const separator = key.indexOf("|");
    const employeeNumber = key.slice(0, separator);
    const date = key.slice(separator + 1);
    const registrations = [...vehicles];
    return {
      employeeNumber, date,
      registration: registrations.length === 1 ? registrations[0] : null,
      state: registrations.length === 1 ? "verified" : "review",
      reason: registrations.length === 1 ? "transpa_trip_evidence" : registrations.length > 1 ? "multiple_vehicles_same_day" : "missing_vehicle_evidence"
    };
  });
}
