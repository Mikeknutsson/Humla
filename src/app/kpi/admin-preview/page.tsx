import {redirect} from "next/navigation";
import {createClient} from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

const features: {label:string;read:string;manage?:string}[] = [
 {label:"KPI och ekonomisk uppföljning",read:"kpi.read",manage:"kpi.manage"},
 {label:"Fordon och resurser",read:"fleet.read",manage:"fleet.manage"},
 {label:"Bränsle",read:"fuel.read",manage:"fuel.manage"},
 {label:"Integrationer",read:"hub.connections.read",manage:"hub.connections.manage"},
 {label:"Granskning",read:"hub.review.read",manage:"hub.review.manage"}
];

export default async function AdminPreview({searchParams}:{searchParams:Promise<{user_id?:string}>}) {
 const supabase=await createClient();
 const {data:{user}}=await supabase.auth.getUser();
 if(!user) redirect("/kpi/login");
 const {data:admin,error:adminError}=await supabase.from("hub_tenant_members")
  .select("tenant_id,role,status").eq("user_id",user.id).eq("status","active").limit(1).maybeSingle();
 if(adminError || !admin || !["owner","admin"].includes(admin.role))
   return <main className="content"><h1>Åtkomst nekad</h1><p>Endast ägare eller administratör kan förhandsgranska andra användares behörigheter.</p></main>;
 const {data:members,error:membersError}=await supabase.from("hub_tenant_members")
  .select("user_id,display_name,role,status").eq("tenant_id",admin.tenant_id).eq("status","active").order("display_name");
 if(membersError || !members) return <main className="content"><h1>Behörighetsöversikten kunde inte hämtas</h1></main>;
 const query=await searchParams;
 const chosen=members.find(m=>m.user_id===query.user_id)??members.find(m=>m.display_name?.toLowerCase()==="ola")??members[0];
 if(!chosen)return <main className="content"><h1>Inga aktiva användare</h1></main>;
 const [{data:roleRows,error:rolesError},{data:overrides,error:overridesError}]=await Promise.all([
  supabase.from("hub_role_permissions").select("permission_code").eq("role",chosen.role),
  supabase.from("hub_member_permission_overrides").select("permission_code,allowed")
   .eq("tenant_id",admin.tenant_id).eq("user_id",chosen.user_id)
 ]);
 const unreliable=Boolean(rolesError||overridesError);
 const effective=new Set((roleRows??[]).map(r=>r.permission_code));
 for(const override of overrides??[]) {
  if(override.allowed) effective.add(override.permission_code);
  else effective.delete(override.permission_code);
 }
 return <main className="content" style={{maxWidth:980}}>
  <header className="topbar"><div><span className="eyebrow">ADMINISTRATION · ENDAST LÄSNING</span><h1>Visa som användare</h1><p>Förhandsgranskning av registrerade rättigheter – ingen inloggning eller åtkomst växlas.</p></div></header>
  <section className="panel">
   <form method="get" action="/kpi/admin-preview" style={{display:"flex",alignItems:"end",gap:12,flexWrap:"wrap"}}>
    <label htmlFor="preview-user">Välj användare</label>
    <select id="preview-user" name="user_id" defaultValue={chosen.user_id} style={{padding:10,minWidth:230}}>
      {members.map(m=><option value={m.user_id} key={m.user_id}>{m.display_name??"Namnlös användare"}</option>)}
    </select>
    <button type="submit">Visa behörigheter</button>
   </form>
   <p><strong>{chosen.display_name}</strong> · roll: {chosen.role} · status: {chosen.status}</p>
   {unreliable?<p role="alert">Behörigheterna kunde inte kontrolleras fullständigt. Inga slutsatser om åtkomst ska dras.</p>:<>
    <div className="table-wrap"><table><thead><tr><th>Funktion</th><th>Läsa</th><th>Hantera</th></tr></thead><tbody>
     {features.map(f=><tr key={f.read}><td>{f.label}</td><td>{effective.has(f.read)?"Ja":"Nej"}</td><td>{f.manage?(effective.has(f.manage)?"Ja":"Nej"):"–"}</td></tr>)}
    </tbody></table></div>
    <p>Behörigheter bygger på rollens registrerade rättigheter samt individuella tillägg och spärrar. Ett nej betyder att rättigheten inte finns i dessa register; enskilda vyer kan också omfattas av ytterligare kontroller.</p>
   </>}
  </section>
  <section className="panel"><h2>Viktigt om förhandsvisningen</h2><p>Du är fortfarande inloggad som dig själv. Sidan visar inte användarens personliga data eller ett simulerat användarsessionstillstånd. För att verifiera faktisk åtkomst krävs ett test med användarens egen session.</p></section>
  <a href="/kpi">Tillbaka till KPI</a>
 </main>;
}
