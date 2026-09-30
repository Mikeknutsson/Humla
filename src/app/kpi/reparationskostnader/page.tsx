import Link from "next/link";
import {redirect} from "next/navigation";
import {createClient} from "@/lib/supabase/server";

export const dynamic="force-dynamic";
const money=(n:number)=>new Intl.NumberFormat("sv-SE",{style:"currency",currency:"SEK",maximumFractionDigits:0}).format(n);
type Row={id:string;status:string;amount:number|string;occurred_on:string;account:string|null;description:string|null;source_row_id:string;external_vehicle_id:string|null};
type Source={id:string;allocation:{allocation_type?:string;allocation_reference?:string;allocation_status?:string}|null};
export default async function RepairCosts({searchParams}:{searchParams:Promise<{from?:string;to?:string}>}){
 const db=await createClient();const {data:{user}}=await db.auth.getUser();if(!user)redirect("/kpi/login");
 const {data:member}=await db.from("hub_tenant_members").select("tenant_id").eq("user_id",user.id).eq("status","active").limit(1).maybeSingle();
 if(!member)return <main style={{padding:32}}>Ingen aktiv arbetsyta.</main>;
 const {data:allowed}=await db.rpc("hub_has_permission",{p_tenant_id:member.tenant_id,p_permission:"kpi.read"});
 if(!allowed)return <main style={{padding:32}}>Behörighet saknas.</main>;
 const q=await searchParams;const today=new Date();const year=today.getUTCMonth()<8?today.getUTCFullYear()-1:today.getUTCFullYear();const from=/^\d{4}-\d{2}-\d{2}$/.test(q.from??"")?q.from!:`${year}-09-01`;const to=/^\d{4}-\d{2}-\d{2}$/.test(q.to??"")?q.to!:`${year+1}-08-31`;
 const {data,error}=await db.from("hub_fordonskontrollen_cost_outbox").select("id,status,amount,occurred_on,account,description,source_row_id,external_vehicle_id").eq("tenant_id",member.tenant_id).gte("occurred_on",from).lte("occurred_on",to).order("occurred_on",{ascending:false}).limit(10000);
 if(error)return <main style={{padding:32}}>Kostnader kunde inte hämtas: {error.message}</main>;
 const rows=(data??[]) as Row[];const ids=rows.map(r=>r.source_row_id);
 const sources:Source[]=[];let sourceError="";
 for(let i=0;i<ids.length;i+=200){const res=await db.from("kpi_import_rows").select("id,allocation").eq("tenant_id",member.tenant_id).in("id",ids.slice(i,i+200));if(res.error){sourceError=res.error.message;break;}sources.push(...(res.data??[]) as Source[]);}
 const byId=new Map(sources.map(s=>[s.id,s]));
 const groups=new Map<string,{name:string;approved:number;pending:number;approvedCount:number;pendingCount:number;rows:Row[]}>();
 for(const row of rows){const a=byId.get(row.source_row_id)?.allocation;const key=a?.allocation_reference?`${a.allocation_type??"Objekt"}: ${a.allocation_reference}`:(row.external_vehicle_id?`Fordon: ${row.external_vehicle_id}`:"Saknar koppling");const group=groups.get(key)??{name:key,approved:0,pending:0,approvedCount:0,pendingCount:0,rows:[]};group.rows.push(row);if(row.status==="approved"){group.approved+=Number(row.amount);group.approvedCount++;}else if(row.status==="pending_review"){group.pending+=Number(row.amount);group.pendingCount++;}groups.set(key,group);}
 const summary=[...groups.values()].sort((a,b)=>b.approved-a.approved);const approved=summary.reduce((s,g)=>s+g.approved,0);const pending=summary.reduce((s,g)=>s+g.pending,0);
 return <main style={{maxWidth:1250,margin:"auto",padding:"28px 22px",fontFamily:"inherit"}}>
 <Link href={`/kpi?from=${from}&to=${to}`}>← Humla Dashboard</Link><h1>Reparationskostnader från NEXT</h1>
 <p>Separat kostnadsunderlag för uppföljning. Beloppen läggs inte en andra gång till i KPI-resultatet. Godkännande här avser tidigare granskning för eventuell export till Fordonskontrollen, inte ekonomisk attest.</p>
 <form style={{display:"flex",gap:12,alignItems:"end",flexWrap:"wrap",margin:"22px 0"}}>
 <label>Från<br/><input type="date" name="from" defaultValue={from}/></label><label>Till<br/><input type="date" name="to" defaultValue={to}/></label><button type="submit">Visa period</button></form>
 <div style={{display:"flex",gap:28,flexWrap:"wrap",margin:"24px 0"}}><section><strong>Godkända för möjlig export</strong><h2>{money(approved)}</h2><small>{summary.reduce((s,g)=>s+g.approvedCount,0)} poster</small></section><section><strong>Väntar på granskning</strong><h2>{money(pending)}</h2><small>{summary.reduce((s,g)=>s+g.pendingCount,0)} poster</small></section></div>
 {sourceError&&<p>Projektkopplingar kunde inte läsas: {sourceError}</p>}
 <h2>Fördelning per identifierat projekt eller objekt</h2><div style={{overflowX:"auto"}}><table style={{width:"100%",borderCollapse:"collapse",textAlign:"left"}}><thead><tr><th>Objekt</th><th>Godkänt</th><th>Väntar</th><th>Poster</th></tr></thead><tbody>{summary.map(g=><tr key={g.name} style={{borderTop:"1px solid #bbb"}}><td style={{padding:"10px 4px"}}><details><summary style={{cursor:"pointer"}}>{g.name}</summary><div style={{fontSize:12,margin:"10px 0"}}>{g.rows.sort((a,b)=>b.occurred_on.localeCompare(a.occurred_on)).map(r=><div key={r.id} style={{padding:"7px 0",borderTop:"1px solid #ddd"}}>{r.occurred_on} · {r.description??"Reparation"} · Konto {r.account??"–"} · {money(Number(r.amount))} · {r.status==="approved"?"Granskad":"Väntar"}</div>)}</div></details></td><td>{money(g.approved)}</td><td>{money(g.pending)}</td><td>{g.approvedCount+g.pendingCount}</td></tr>)}</tbody></table></div>
 <p style={{marginTop:20}}>Källa: NEXT-importens kostnadsrader och befintliga projektkopplingar. Interna verkstadskostnader ska belasta respektive fordon när kopplingen är verifierad. Projektidentifiering är inte automatiskt en bekräftad fordonskoppling.</p>
 </main>;
}
