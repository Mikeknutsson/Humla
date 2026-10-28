import Link from "next/link";
import {redirect} from "next/navigation";
import {createClient} from "@/lib/supabase/server";
import {assignTransportUnit,closeTransportUnitAssignment} from "./actions";
export const dynamic="force-dynamic";
export default async function TransportAssignments({searchParams}:{searchParams:Promise<{result?:string}>}){
 const db=await createClient(),{data:{user}}=await db.auth.getUser();if(!user)redirect("/kpi/login");
 const {data:member}=await db.from("hub_tenant_members").select("tenant_id,role")
  .eq("user_id",user.id).eq("status","active").limit(1).maybeSingle();
 if(!member||member.role!=="owner")return <main className="section" role="alert"><h1>Åtkomst nekad</h1><p>Endast organisationens ägare kan tilldela arbetsledaransvar.</p></main>;
 const [{data:people,error:peopleError},{data:units,error:unitsError},{data:assignments,error:assignError}]=await Promise.all([
  db.from("hub_tenant_members").select("user_id,display_name,role").eq("tenant_id",member.tenant_id).eq("status","active").order("display_name"),
  db.from("hub_objects").select("id,data").eq("tenant_id",member.tenant_id).eq("object_type","EconomicUnit"),
  db.from("hub_transport_leader_units").select("id,user_id,unit_id,valid_from,valid_to").eq("tenant_id",member.tenant_id).order("created_at",{ascending:false}).limit(150),
 ]);
 const canonicalUnits=(units??[]).map(u=>({id:u.id,name:String(u.data?.name??'Namnlös enhet')})).sort((a,b)=>a.name.localeCompare(b.name,'sv'));
 const q=await searchParams;
 const nameById=new Map((people??[]).map(p=>[p.user_id,p.display_name??p.user_id]));
 const unitById=new Map(canonicalUnits.map(u=>[u.id,u.name]));
 return <main>
  <header className="topbar"><div><span className="eyebrow">HUMLA TRANSPORT · ADMIN</span><h1>Arbetsledarnas enheter</h1>
   <p>Tilldela befintliga ekonomiska enheter till inloggade transportledare, med giltighetsperiod.</p></div><Link href="/transport-styrning" className="navitem">Till mitt styrkort →</Link></header>
  {q.result&&<section className="section" role="status"><p>{q.result==="created"?"Ansvarstilldelningen har sparats.":q.result==="closed"?"Ansvarsperioden är avslutad.":"Tilldelningen kunde inte genomföras. Kontrollera uppgifter och behörigheter."}</p></section>}
  {(peopleError||unitsError||assignError)?<section className="section" role="alert"><h2>Uppgifterna kunde inte läsas</h2><p>Kontrollera att ansvarstabellen är driftsatt och rättigheter gäller.</p></section>:
  <>
   <section className="section"><h2>Ny tilldelning</h2><p><Link href="/kpi/mina-enheter">Förhandsvisa arbetsledarvyn →</Link></p>
    <p>Endast aktiva Humla-konton kan väljas. Enheter som byter arbetsledare behåller sin ekonomiska historik.</p>
    <form action={assignTransportUnit} style={{display:"flex",flexWrap:"wrap",gap:12,alignItems:"end"}}>
     <label>Transportledare <select name="user_id" required defaultValue=""><option value="" disabled>Välj användare</option>
      {(people??[]).map(p=><option key={p.user_id} value={p.user_id}>{p.display_name??p.user_id} ({p.role})</option>)}</select></label>
     <label>Ekonomisk enhet <select name="unit_id" required defaultValue=""><option value="" disabled>Välj enhet</option>
      {canonicalUnits.map(u=><option key={u.id} value={u.id}>{u.name}</option>)}</select></label>
     <label>Gäller från <input type="date" name="valid_from" required defaultValue={new Date().toISOString().slice(0,10)}/></label>
     <label>Gäller till (valfritt) <input type="date" name="valid_to"/></label>
     <button type="submit">Tilldela enhet</button>
    </form>
   </section>
   <section className="section"><h2>Registrerade ansvar</h2>
    {(assignments??[]).length===0?<p>Det finns ännu inga tilldelningar.</p>:<div className="table" role="table">
      <div className="tr th" role="row"><span>Användare</span><span>Enhet</span><span>Från</span><span>Till</span><span>Åtgärd</span></div>
      {(assignments??[]).map(a=><div className="tr" role="row" key={a.id}>
       <strong>{nameById.get(a.user_id)??"Okänd användare"}</strong><span>{unitById.get(a.unit_id)??"Okänd enhet"}</span>
       <span>{a.valid_from}</span><span>{a.valid_to??"Tills vidare"}</span>
       <form action={closeTransportUnitAssignment} style={{display:"flex",gap:5}}>
        <input type="hidden" name="assignment_id" value={a.id}/>
        <input type="date" name="valid_to" min={a.valid_from} required aria-label="Avsluta från datum"/>
        <button type="submit">Avsluta</button>
       </form>
      </div>)}</div>}
   </section>
  </>}
 </main>;
}
