import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { createClient as createAdminClient } from "@supabase/supabase-js";

export const dynamic = "force-dynamic";

async function ownerContext() {
  const db = await createClient();
  const { data: { user } } = await db.auth.getUser();
  if (!user) redirect("/kpi/login");
  const { data: membership } = await db.from("hub_tenant_members").select("tenant_id,role").eq("user_id", user.id).eq("status","active").eq("role","owner").limit(1).maybeSingle();
  if (!membership) return null;
  return membership;
}
function admin() {
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!key || !process.env.NEXT_PUBLIC_SUPABASE_URL) return null;
  return createAdminClient(process.env.NEXT_PUBLIC_SUPABASE_URL, key, {auth:{autoRefreshToken:false,persistSession:false}});
}
async function createForeman(formData: FormData) {
  "use server";
  const owner = await ownerContext();
  if (!owner) redirect("/kpi");
  const client = admin();
  if (!client) redirect("/kpi/anvandare?error=config");
  const email = String(formData.get("email")??"").trim().toLowerCase();
  const name = String(formData.get("name")??"").trim();
  const password = String(formData.get("password")??"");
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || !name || password.length < 12) redirect("/kpi/anvandare?error=validation");
  const {data,error} = await client.auth.admin.createUser({email,password,email_confirm:true});
  if (error || !data.user) redirect("/kpi/anvandare?error=create");
  const {error:membershipError}=await client.from("hub_tenant_members").insert({tenant_id:owner.tenant_id,user_id:data.user.id,role:"supervisor",status:"active",display_name:name});
  if (membershipError) {
    await client.auth.admin.deleteUser(data.user.id);
    redirect("/kpi/anvandare?error=membership");
  }
  redirect("/kpi/anvandare?success=created");
}
async function changeStatus(formData: FormData) {
  "use server";
  const owner = await ownerContext();
  if (!owner) redirect("/kpi");
  const client = admin();
  if (!client) redirect("/kpi/anvandare?error=config");
  const id = String(formData.get("id")??"");
  const status = String(formData.get("status")??"");
  if (!/^[0-9a-f-]{36}$/i.test(id) || !["active","inactive"].includes(status)) redirect("/kpi/anvandare?error=validation");
  const {error}=await client.from("hub_tenant_members").update({status}).eq("tenant_id",owner.tenant_id).eq("user_id",id).eq("role","supervisor");
  redirect("/kpi/anvandare?"+(error?"error=update":"success=updated"));
}
async function resetPassword(formData: FormData) {
  "use server";
  const owner=await ownerContext();
  if(!owner)redirect("/kpi");
  const client=admin();
  if(!client)redirect("/kpi/anvandare?error=config");
  const id=String(formData.get("id")??"");
  const password=String(formData.get("password")??"");
  if(password.length<12)redirect("/kpi/anvandare?error=validation");
  const {data:member}=await client.from("hub_tenant_members").select("user_id").eq("tenant_id",owner.tenant_id).eq("user_id",id).eq("role","supervisor").maybeSingle();
  if(!member)redirect("/kpi/anvandare?error=access");
  const {error}=await client.auth.admin.updateUserById(id,{password});
  redirect("/kpi/anvandare?"+(error?"error=reset":"success=reset"));
}
export default async function UsersPage({searchParams}:{searchParams:Promise<{error?:string;success?:string}>}) {
  const owner=await ownerContext();
  if(!owner)return <main className="kpi-app"><section className="panel"><h1>Åtkomst nekad</h1><a href="/kpi">Tillbaka</a></section></main>;
  const client=admin();
  const params=await searchParams;
  const {data:members}=client?await client.from("hub_tenant_members").select("user_id,display_name,role,status").eq("tenant_id",owner.tenant_id).order("display_name"): {data:[]};
  const {data:users}=client?await client.auth.admin.listUsers({page:1,perPage:1000}):{data:{users:[]}};
  const emails=new Map((users?.users??[]).map(u=>[u.id,u.email]));
  return <div className="kpi-app"><main className="content" style={{maxWidth:950,margin:"0 auto",padding:24}}>
    <a href="/kpi/kontrollpanel">← Kontrollpanelen</a><h1>Användare & behörigheter</h1>
    <p>Skapa arbetsledarkonton med e-postadress och lösenord. Kontona får rollen arbetsledare, inte administratör.</p>
    {!client&&<p role="alert">Serverinställningen SUPABASE_SERVICE_ROLE_KEY saknas. Kontohanteringen är därför avstängd tills den konfigurerats säkert.</p>}
    {params.error&&<p role="alert">Åtgärden kunde inte genomföras ({params.error}). Inga lösenord visas eller sparas här.</p>}
    {params.success&&<p role="status">Åtgärden har genomförts.</p>}
    <section className="panel"><h2>Skapa arbetsledare</h2><form action={createForeman} style={{display:"grid",gap:12,maxWidth:440}}>
      <label>Namn<input name="name" required maxLength={120}/></label>
      <label>E-postadress<input name="email" type="email" autoComplete="off" required/></label>
      <label>Tillfälligt lösenord (minst 12 tecken)<input name="password" type="password" minLength={12} autoComplete="new-password" required/></label>
      <button className="primary" disabled={!client}>Skapa konto</button>
    </form></section>
    <section className="panel"><h2>Befintliga användare</h2>{(members??[]).map(m=><details key={m.user_id} style={{padding:"12px 0",borderBottom:"1px solid #8884"}}>
      <summary><strong>{m.display_name??"Utan namn"}</strong> · {emails.get(m.user_id)??"E-post saknas"} · {m.role==="owner"?"Ägare":m.role==="supervisor"?"Arbetsledare":m.role} · {m.status==="active"?"Aktiv":"Spärrad"}</summary>
      {m.role==="supervisor"&&<div style={{display:"grid",gap:12,padding:12}}>
        <form action={changeStatus}><input type="hidden" name="id" value={m.user_id}/><input type="hidden" name="status" value={m.status==="active"?"inactive":"active"}/><button disabled={!client}>{m.status==="active"?"Spärra konto":"Aktivera konto"}</button></form>
        <form action={resetPassword} style={{display:"flex",gap:8,flexWrap:"wrap"}}><input type="hidden" name="id" value={m.user_id}/><label>Nytt lösenord <input type="password" name="password" minLength={12} required autoComplete="new-password"/></label><button disabled={!client}>Byt lösenord</button></form>
      </div>}
    </details>)}</section>
    <p>Områdesbehörigheter styrs fortsatt av Humlas befintliga tilldelningar. Kontoskapandet ger inte automatiskt åtkomst till alla verksamhetsområden.</p>
  </main></div>;
}
