import Link from "next/link";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";
const fmt = (v: number | null) => v === null ? "Ej angivet" : new Intl.NumberFormat("sv-SE",{style:"currency",currency:"SEK",maximumFractionDigits:0}).format(v);

export default async function TransportCostSetup() {
  const supabase = await createClient();
  const {data:{user}} = await supabase.auth.getUser();
  if (!user) redirect("/kpi/login");
  const {data:member} = await supabase.from("hub_tenant_members").select("tenant_id").eq("user_id",user.id).eq("status","active").limit(1).maybeSingle();
  if (!member) return <main className="content"><h1>Ingen arbetsyta</h1></main>;
  const {data:allowed} = await supabase.rpc("hub_has_permission",{p_tenant_id:member.tenant_id,p_permission:"kpi.manage"});
  if (!allowed) return <main className="content"><h1>Administratörsbehörighet krävs</h1></main>;
  const [{data:units,error:unitsError},{data:components,error:componentsError},{data:rules,error:rulesError}] = await Promise.all([
    supabase.from("kpi_units").select("id,name,unit_type,registrations,projects,valid_from,valid_to,enabled").eq("tenant_id",member.tenant_id).eq("enabled",true).order("name").limit(500),
    supabase.from("kpi_unit_components").select("unit_id,component_type,component_reference,allocation_percent,valid_from,valid_to").eq("tenant_id",member.tenant_id).limit(1000),
    supabase.from("hub_cost_allocation_rules").select("id,name,cost_category,allocation_method,monthly_amount,include_in_vehicle_result,valid_from,valid_to,enabled,target_scope").eq("tenant_id",member.tenant_id).order("priority").limit(500)
  ]);
  const problems = [unitsError,componentsError,rulesError].filter(Boolean);
  return <main className="content" style={{maxWidth:1240,margin:"0 auto",padding:24}}>
    <p><Link href="/kpi/transportledare">← Kostnadsuppföljning</Link></p>
    <h1>Kostnadsenheter och kostnadsfördelning – Transport</h1>
    <p>Administrativ kontrollvy för befintliga Hub-regler. Inga ekonomiska belopp fördelas om från denna sida.</p>
    {problems.length>0 && <p role="alert">Delar av registret kunde inte läsas. Kontrollera behörigheter och databasstatus innan ändringar görs.</p>}
    <section><h2>Ekonomiska enheter ({unitsError?"—":units?.length ?? 0})</h2>
      <p>Intäktsbringande enhet är huvudobjektet. Kopplade släp, förare och andra resurser visas som komponenter.</p>
      <div style={{overflowX:"auto"}}><table style={{width:"100%"}}>
        <thead><tr><th align="left">Enhet</th><th align="left">Typ</th><th align="left">Registreringar</th><th align="left">Komponenter</th><th align="left">Giltig från</th></tr></thead>
        <tbody>{(units ?? []).map(unit=><tr key={unit.id}><td><strong>{unit.name}</strong></td><td>{unit.unit_type ?? "—"}</td><td>{(unit.registrations ?? []).join(", ") || "—"}</td><td>{(components ?? []).filter(c=>c.unit_id===unit.id).map(c=>`${c.component_type}: ${c.component_reference} (${c.allocation_percent ?? 100} %)`).join("; ") || "Inga registrerade"}</td><td>{unit.valid_from ?? "—"}</td></tr>)}</tbody>
      </table></div>
    </section>
    <section><h2>Gemensamma kostnader och fördelningsregler ({rulesError?"—":rules?.length ?? 0})</h2>
      <p>Reglernas ekonomiska effekt ska beräknas i Hubben. En inaktiv regel påverkar inte resultatet.</p>
      <div style={{overflowX:"auto"}}><table style={{width:"100%"}}>
        <thead><tr><th align="left">Regel</th><th align="left">Kategori</th><th align="left">Metod</th><th align="right">Månadsbelopp</th><th align="left">Fordonsresultat</th><th align="left">Status</th></tr></thead>
        <tbody>{(rules ?? []).map(rule=><tr key={rule.id}><td>{rule.name}</td><td>{rule.cost_category}</td><td>{rule.allocation_method}</td><td align="right">{fmt(rule.monthly_amount)}</td><td>{rule.include_in_vehicle_result?"Ja":"Nej"}</td><td>{rule.enabled?"Aktiv":"Inaktiv"}</td></tr>)}</tbody>
      </table></div>
      {!rulesError && !rules?.length && <p>Inga kostnadsfördelningsregler finns registrerade. Skapa och granska regler i Hubben innan de aktiveras; inga schablonbelopp läggs in automatiskt.</p>}
    </section>
    <section><h2>Fördelningsprinciper</h2>
      <p>Direkta kostnader följer verifierad enhetskoppling. Gemensamma kostnader kan fördelas lika, med fasta andelar eller efter en verifierad fördelningsnyckel. Varje ursprungstransaktion ska ha en unik identitet och summan av fördelade andelar får aldrig överstiga 100 %.</p>
      <p>Personalkostnad, bränsle, service och reparationer, fasta kostnader och övrigt ska särredovisas. Ofördelade och osäkra belopp ska kunna granskas separat.</p>
    </section>
  </main>;
}
