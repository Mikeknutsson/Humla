import Link from "next/link";
import {redirect} from "next/navigation";
import {createClient} from "@/lib/supabase/server";
import {stockholmToday} from "@/lib/kpi/period";

export const dynamic="force-dynamic";
type Unit={unit_id:string;unit_name:string;unit_type:string|null;registrations:string[]|null};
type FinancialUnit={unit_id:string;unit_name:string;revenue:number|null;cost:number|null;result:number|null;fuel:number|null;row_count:number|null};
type Scorecard={from:string;to:string;units:FinancialUnit[];summary:{revenue:number|null;cost:number|null;result:number|null;fuel:number|null};quality:{status:string;unit_count?:number}};
const money=new Intl.NumberFormat("sv-SE",{style:"currency",currency:"SEK",maximumFractionDigits:0});
const amount=(value:number|null|undefined)=>value===null||value===undefined||!Number.isFinite(value)?"Underlag saknas":money.format(value);
function defaultMonth(){const t=stockholmToday();const d=new Date(Date.UTC(t.year,t.month-2,1));return d.toISOString().slice(0,7);}
function monthRange(month:string){const [y,m]=month.split("-").map(Number);return {from:month+"-01",to:new Date(Date.UTC(y,m,0)).toISOString().slice(0,10)};}
export default async function TransportSteering({searchParams}:{searchParams:Promise<{month?:string;user_id?:string}>}){
 const db=await createClient();
 const {data:{user}}=await db.auth.getUser();if(!user)redirect("/kpi/login");
 const {data:member}=await db.from("hub_tenant_members").select("tenant_id,display_name,role")
  .eq("user_id",user.id).eq("status","active").limit(1).maybeSingle();
 if(!member)return <section className="section"><h1>Åtkomst saknas</h1><p>Ingen aktiv organisation är kopplad till ditt konto.</p></section>;
 const query=await searchParams;
 const month=query.month??defaultMonth();
 if(!/^\d{4}-(0[1-9]|1[0-2])$/.test(month))return <section className="section"><h1>Ogiltig månad</h1><Link href="/kpi/transport-styrning">Återställ</Link></section>;
 const {from,to}=monthRange(month);
 const owner=member.role==="owner";
 const selectedUser=owner?query.user_id??user.id:user.id;
 const [{data:units,error:unitError},{data:score,error:scoreError}]=await Promise.all([
  db.rpc("hub_transport_leader_units_for_user",{p_tenant_id:member.tenant_id,p_user_id:selectedUser,p_as_of:to}),
  db.rpc("hub_transport_leader_scorecard_v1",{p_tenant_id:member.tenant_id,p_user_id:selectedUser,p_from:from,p_to:to})
 ]);
 const visible=Array.isArray(units)?units as Unit[]:[];
 const report=score as Scorecard|null;
 return <div>
  <header className="topbar"><div><span className="eyebrow">HUMLA TRANSPORT</span><h1>Mitt styrkort</h1>
   <p>{member.display_name??"Arbetsledare"} · Enbart tilldelade ekonomiska enheter</p></div>
   <div>{owner&&<Link className="navitem" href="/kpi/transport-styrning/admin">Hantera ansvar →</Link>}</div>
  </header>
  <section className="section">
    <form method="get" style={{display:"flex",alignItems:"end",gap:12,flexWrap:"wrap"}}>
      <label>Rapportmånad <input type="month" name="month" defaultValue={month} required/></label>
      {owner&&selectedUser!==user.id&&<input type="hidden" name="user_id" value={selectedUser}/>}
      <button type="submit">Visa</button>
    </form>
    <p>Enheterna måste ha varit tilldelade under hela rapportmånaden för att beloppen ska visas. Delvisa ansvarsbyten hanteras separat, så historiken inte flyttas felaktigt.</p>
  </section>
  {unitError||scoreError||!report?<section className="section" role="alert"><h2>Styrkortet kunde inte läsas</h2>
    <p>Behörigheten eller Hubbles ekonomiska rapport måste verifieras. Inga belopp visas.</p></section>:
    <>{visible.length===0?<section className="section"><h2>Inga enheter tilldelade</h2>
      <p>En administratör behöver koppla dina ekonomiska enheter till kontot och rätt giltighetsperiod.</p></section>:
      <section className="section"><span className="label">ANSVARSOMRÅDE</span><h2>Mina enheter ({visible.length})</h2>
        <div className="linkgrid three">{visible.map(u=><article className="module" key={u.unit_id}>
          <span>{u.unit_type??"Ekonomisk enhet"}</span><h3>{u.unit_name}</h3>
          <p>{u.registrations?.length?u.registrations.join(", "):"Ingen registrering angiven"}</p>
        </article>)}</div></section>}
      <section className="section"><span className="label">EKONOMI · HUMLA HUB</span><h2>Styrtal {month}</h2>
        <div className="stats">
          {([["Omsättning",report.summary?.revenue],["Kostnader",report.summary?.cost],["Resultat",report.summary?.result],["Bränslekostnad",report.summary?.fuel]] as const).map(([label,value])=>
           <article key={label}><b style={{fontSize:21}}>{amount(value)}</b><strong>{label}</strong></article>)}
        </div>
        <p>Beloppen baseras på Hubbles ekonomiska fakta och enbart tilldelade enheter. Ej fördelade poster ingår inte i styrkortet. Kostnader och resultat är preliminära tills ekonomiavstämningen är klar.</p>
        <div style={{overflowX:"auto"}}><table style={{width:"100%"}}><thead><tr><th>Enhet</th><th>Intäkt</th><th>Kostnad</th><th>Resultat</th><th>Bränsle</th></tr></thead>
          <tbody>{(report.units??[]).map(u=><tr key={u.unit_id}><td>{u.unit_name}</td>
           <td>{amount(u.revenue)}</td><td>{amount(u.cost)}</td><td>{amount(u.result)}</td><td>{amount(u.fuel)}</td></tr>)}</tbody></table></div>
        {!report.units?.length&&<p>Inga kvalitetssäkrade ekonomiska rader finns för fullt tilldelade enheter under perioden.</p>}
      </section></>}
 </div>;
}
