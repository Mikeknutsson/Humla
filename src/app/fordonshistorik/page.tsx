import { createClient } from "@/lib/supabase/server";
import { resolveHistoricalTrips } from "../../../lib/hub/historical-transpa-evidence";
export const dynamic = "force-dynamic";
export default async function HistoricalVehicleReview() {
  const s = await createClient();
  const [persons, times, vehicles] = await Promise.all([
    s.from("hub_transpa_persons").select("transpa_employee_id,employee_number,display_name").not("employee_number","is",null).limit(500),
    s.from("kpi_transpa_time_facts").select("employee_id,work_date,transpa_vehicle_ids").gte("work_date","2025-09-01").limit(10000),
    s.from("hub_transpa_entities").select("external_id,payload").eq("entity_type","vehicle").limit(500)
  ]);
  const errors = [persons.error,times.error,vehicles.error].filter(Boolean);
  const byPerson = new Map((persons.data ?? []).map(p=>[p.transpa_employee_id,p.employee_number as string]));
  const byVehicle = new Map((vehicles.data ?? []).map(v=>[v.external_id,String((v.payload as Record<string,unknown> | null)?.registrationNumber ?? "")]));
  const evidence = (times.data ?? []).filter(t=>byPerson.has(t.employee_id)).map(t=>({
    employeeNumber: byPerson.get(t.employee_id)!,
    date: t.work_date as string,
    vehicleRegistrations: ((t.transpa_vehicle_ids ?? []) as string[]).map(id=>byVehicle.get(id) ?? "")
  }));
  const resolved = resolveHistoricalTrips(evidence);
  return <><header className="topbar"><div><span className="eyebrow">HUMLA HUB · HISTORIK</span><h1>Historisk fordonskontroll</h1><p>TransPA person-ID och fordons-ID matchas mot registreringsnummer. Läsbehörig granskning från 1 september 2025.</p></div></header>
  {errors.length ? <section className="card"><h2>Underlag kunde inte läsas</h2><p>{errors.map(e=>e?.message).join("; ")}</p></section> :
  <section className="section"><h2>Kontrollerade persondagar</h2><p>{resolved.filter(x=>x.state==="verified").length} entydiga · {resolved.filter(x=>x.state==="review").length} behöver granskas. Resultaten påverkar ännu inte KPI.</p><table><thead><tr><th>Anställningsnummer</th><th>Datum</th><th>Fordon</th><th>Kontroll</th></tr></thead><tbody>{resolved.slice(0,250).map(x=><tr key={x.employeeNumber+x.date}><td>{x.employeeNumber}</td><td>{x.date}</td><td>{x.registration ?? "Ej fastställt"}</td><td>{x.reason}</td></tr>)}</tbody></table></section>}</>;
}
