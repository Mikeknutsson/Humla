import Link from "next/link";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

type VehicleRow = Record<string, unknown>;
type TargetRow = { unit_key: string; target_margin_percent: number; valid_from: string; valid_to: string | null };

const money = (n: number) => new Intl.NumberFormat("sv-SE",{style:"currency",currency:"SEK",maximumFractionDigits:0}).format(n);
const num = (v: unknown) => typeof v === "number" && Number.isFinite(v) ? v : null;

export default async function TransportManagerKpi({
  searchParams
}: { searchParams: Promise<{from?:string;to?:string}> }) {
  const supabase = await createClient();
  const {data:{user}} = await supabase.auth.getUser();
  if (!user) redirect("/kpi/login");
  const {data:member} = await supabase.from("hub_tenant_members")
    .select("tenant_id,display_name").eq("user_id",user.id).eq("status","active").limit(1).maybeSingle();
  if (!member) return <main className="content"><h1>Ingen aktiv arbetsyta</h1></main>;
  const {data:canRead} = await supabase.rpc("hub_has_permission",{p_tenant_id:member.tenant_id,p_permission:"kpi.read"});
  if (!canRead) return <main className="content"><h1>Åtkomst nekad</h1></main>;

  const params = await searchParams;
  const today = new Date();
  const fy = today.getUTCMonth() >= 8 ? today.getUTCFullYear() : today.getUTCFullYear()-1;
  const dateOk = (v:unknown):v is string => typeof v==="string" && /^\d{4}-\d{2}-\d{2}$/.test(v) && !Number.isNaN(Date.parse(v));
  const from = dateOk(params.from) ? params.from : `${fy}-09-01`;
  const to = dateOk(params.to) ? params.to : `${fy+1}-08-31`;
  if (from>to) return <main className="content"><h1>Ogiltig period</h1></main>;

  const [{data:report,error:reportError},{data:targets,error:targetError}] = await Promise.all([
    supabase.rpc("hub_kpi_cost_center_dashboard_v1",{
      p_tenant_id:member.tenant_id,p_from:from,p_to:to,p_cost_center:"30"
    }),
    supabase.from("hub_kpi_unit_margin_targets")
      .select("unit_key,target_margin_percent,valid_from,valid_to")
      .eq("tenant_id",member.tenant_id)
      .lte("valid_from",to)
      .or(`valid_to.is.null,valid_to.gte.${from}`)
  ]);

  if (reportError || !report) return <main className="content"><h1>Ekonomin kunde inte hämtas</h1><p>Inga belopp visas när underlaget saknas.</p></main>;
  // The Hub report uses the canonical financial cost-center code 30.
  // NEXT project register stores the human-readable label "Transport".
  // Keep both source values intact and resolve project classification separately.
  const {data:transportProjects,error:projectError} = await supabase
    .from("hub_kpi_project_register_canonical_v1")
    .select("project_number,project_name,project_manager,cost_center,source_cost_center")
    .eq("tenant_id",member.tenant_id)
    .eq("cost_center","30");
  const {data:projectMappings,error:mappingError} = await supabase
    .from("kpi_project_unit_mappings")
    .select("project_reference,vehicle_registration,valid_from,valid_to,enabled")
    .eq("tenant_id",member.tenant_id)
    .eq("enabled",true)
    .lte("valid_from",to)
    .or(`valid_to.is.null,valid_to.gte.${from}`);
  const transportKeys = new Set((transportProjects ?? []).map(p=>String(p.project_number)));
  const linkedMappings = (projectMappings ?? []).filter(m=>transportKeys.has(String(m.project_reference)));
  const rows:VehicleRow[] = Array.isArray(report.vehicles) ? report.vehicles : [];
  const goals:TargetRow[] = (targets ?? []) as TargetRow[];
  return <main className="content" style={{maxWidth:1200,margin:"0 auto",padding:24}}>
    <p><Link href="/kpi">← KPI-översikt</Link></p>
    <h1>Mina kostnadsenheter</h1>
    <p>Period: {from} – {to}. Transport, material och tippavgifter redovisas separat i ekonomins originalunderlag.</p>
    {targetError && <p role="alert">Målregistret är inte tillgängligt. Mål visas inte.</p>}
    <p>Projekt i importerat transportregister: {projectError ? "kunde inte hämtas" : (transportProjects ?? []).length}. Kostnadsställe 30 och Transport ingår i samma projekturval.</p>
    <p>Denna vy visar transportens enheter. Personlig områdes- och fordonstilldelning kopplas på separat innan vyn ges till arbetsledare.</p>
    <h2>Ekonomisk uppföljning per enhet</h2>
    <div style={{overflowX:"auto"}}><table style={{width:"100%",borderCollapse:"collapse"}}>
      <thead><tr><th align="left">Enhet</th><th align="right">Intäkt</th><th align="right">Kostnad</th><th align="right">Resultat</th><th align="right">Marginal</th><th align="right">Mål</th><th align="right">Avvikelse</th><th align="right">Avvikelse kr</th><th align="left">Detaljer</th></tr></thead>
      <tbody>{rows.map((row,index)=>{
        const key=String(row.registration ?? row.registration_number ?? row.unit_name ?? row.name ?? row.vehicle_registration ?? "");
        const revenue=num(row.revenue ?? row.income);
        const cost=num(row.cost ?? row.costs);
        const result=num(row.result ?? row.profit) ?? (revenue!==null && cost!==null ? revenue-cost : null);
        const margin=revenue!==null && revenue!==0 && result!==null ? result/revenue*100 : null;
        const overlapping=goals.filter(g=>g.unit_key===key && g.valid_from<=to && (!g.valid_to || g.valid_to>=from));
        const goal=overlapping.length===1 && overlapping[0].valid_from<=from && (!overlapping[0].valid_to || overlapping[0].valid_to>=to) ? overlapping[0].target_margin_percent : null;
        return <tr key={key || index}>
          <td>{key || "Okänd enhet"}</td>
          <td align="right">{revenue===null?"—":money(revenue)}</td>
          <td align="right">{cost===null?"—":money(cost)}</td>
          <td align="right">{result===null?"—":money(result)}</td>
          <td align="right">{margin===null?"—":`${margin.toFixed(1)} %`}</td>
          <td align="right">{goal===null?"—":`${goal} %`}</td>
          <td align="right">{goal===null || margin===null ? "—" : `${(margin-goal).toFixed(1)} pp`}</td>
          <td align="right">{goal===null || revenue===null || result===null ? "—" : money(result-revenue*goal/100)}</td>
          <td>{key?<Link href={`/kpi?view=overview&vehicle=${encodeURIComponent(key)}&from=${from}&to=${to}`}>Visa arbetsunderlag →</Link>:null}</td>
        </tr>;
      })}</tbody>
    </table></div>
    {!rows.length && <p>Inga fordon i rapporten för vald period.</p>}
    <details><summary>Projektkopplingar från NEXT (sekundär uppföljning)</summary>
    <h2>Projekt från NEXT</h2>
    <p>Aktiva projekt–fordonskopplingar inom vald period: {mappingError ? "kunde inte hämtas" : linkedMappings.length}. Kopplingarna visar ansvar och tillhörighet, inte summerad ekonomi.</p>
    {projectError ? <p role="alert">Projektregistret kunde inte läsas.</p> :
      <details><summary>Visa projekt och kopplade fordon ({transportProjects?.length ?? 0})</summary>
      <div style={{overflowX:"auto"}}><table style={{width:"100%"}}>
        <thead><tr><th align="left">Projekt</th><th align="left">Namn</th><th align="left">Projektledare</th><th align="left">Kopplade fordon</th></tr></thead>
        <tbody>{(transportProjects ?? []).map(project=><tr key={project.project_number}>
          <td>{project.project_number}</td><td>{project.project_name}</td>
          <td>{project.project_manager || "Ej angiven"}</td>
          <td>{linkedMappings.filter(m=>m.project_reference===project.project_number).map(m=>m.vehicle_registration).filter(Boolean).join(", ") || "Ej kopplat"}</td>
        </tr>)}</tbody>
      </table></div></details>}
    </details>
    <p>Enhetsmål som ändras under perioden visas tills vidare som ”—” i stället för att beräknas felaktigt.</p>
  </main>;
}
