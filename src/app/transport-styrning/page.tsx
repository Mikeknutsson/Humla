import Link from "next/link";
import {redirect} from "next/navigation";
import {createClient} from "@/lib/supabase/server";

export const dynamic="force-dynamic";
type Unit={unit_id:string;unit_name:string;unit_type:string|null;registrations:string[]|null};

export default async function TransportSteering(){
 const db=await createClient();
 const {data:{user}}=await db.auth.getUser();
 if(!user)redirect("/kpi/login");
 const {data:member}=await db.from("hub_tenant_members").select("tenant_id,display_name,role")
  .eq("user_id",user.id).eq("status","active").limit(1).maybeSingle();
 if(!member)return <section className="section"><h1>Åtkomst saknas</h1><p>Ingen aktiv organisation är kopplad till ditt konto.</p></section>;
 const {data:units,error}=await db.rpc("hub_transport_leader_units_for_user",
  {p_tenant_id:member.tenant_id,p_as_of:new Date().toISOString().slice(0,10)});
 const visible=Array.isArray(units)?units as Unit[]:[];
 return <div>
  <header className="topbar"><div><span className="eyebrow">HUMLA TRANSPORT</span>
   <h1>Mitt styrkort</h1><p>{member.display_name??"Arbetsledare"} · Enbart tilldelade ekonomiska enheter</p></div>
   <Link className="navitem" href="/kpi">KPI & Ekonomi →</Link></header>
  {error?<section className="section" role="alert"><h2>Styrkortet kunde inte läsas</h2>
   <p>Behörighetskopplingen är ännu inte aktiverad eller kunde inte verifieras. Ingen data visas.</p></section>:
  visible.length===0?<section className="section"><h2>Inga enheter tilldelade</h2>
   <p>Din arbetsledarvy är klar att konfigureras. En behörig administratör behöver först koppla dina enheter till kontot.</p></section>:
   <><section className="section"><span className="label">ANSVARSOMRÅDE</span><h2>Mina enheter ({visible.length})</h2>
    <div className="linkgrid three">{visible.map(u=><article className="module" key={u.unit_id}>
     <span>{u.unit_type??"Ekonomisk enhet"}</span><h3>{u.unit_name}</h3>
     <p>{u.registrations?.length?u.registrations.join(", "):"Ingen registrering angiven"}</p></article>)}</div></section>
    <section className="section"><span className="label">STYRTAL</span><h2>Nyckeltal per ansvarsområde</h2>
     <p>Ekonomiska nyckeltal aktiveras efter att Hubbles aggregering verifierats för din enhetsbehörighet. Det visas inte några avdelningstotaler som skulle kunna omfatta andra arbetsledares enheter.</p></section></>}
 </div>;
}
