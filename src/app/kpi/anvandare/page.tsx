import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { FunctionsHttpError } from "@supabase/supabase-js";

export const dynamic = "force-dynamic";

async function ownerContext() {
  const db = await createClient();
  const { data: { user } } = await db.auth.getUser();
  if (!user) redirect("/kpi/login");
  const { data: membership } = await db.from("hub_tenant_members").select("tenant_id,role").eq("user_id", user.id).eq("status","active").eq("role","owner").limit(1).maybeSingle();
  if (!membership) return null;
  return { db, tenantId: membership.tenant_id };
}

type OwnerContext = NonNullable<Awaited<ReturnType<typeof ownerContext>>>;
type Member = {user_id:string; display_name:string|null; role:string; status:string; email:string|null};
const errors:Record<string,string> = {
  access:"Du saknar behörighet att hantera det här kontot.",
  duplicate:"E-postadressen används redan av ett konto.",
  validation:"Kontrollera uppgifterna. Lösenordet behöver vara minst 12 tecken och högst 72 byte.",
  create:"Kontot kunde inte skapas.",
  membership:"Arbetsledarkontot kunde inte knytas till arbetsytan.",
  update:"Kontostatusen kunde inte ändras.",
  reset:"Lösenordet kunde inte ändras.",
  shared_account:"Kontot används i flera arbetsytor. Användaren behöver själv återställa sitt lösenord.",
  unavailable:"Kontohanteringen kunde inte nås. Försök igen.",
};

async function accountRequest(owner:OwnerContext, payload:Record<string,unknown>) {
  const { data, error } = await owner.db.functions.invoke("kpi-foreman-accounts", {
    body:{ ...payload, tenantId:owner.tenantId },
  });
  if (!error) return {data,error:null};
  if (error instanceof FunctionsHttpError) {
    const body=await error.context.json().catch(()=>null);
    if (typeof body?.error==="string" && Object.hasOwn(errors,body.error)) return {data:null,error:body.error};
  }
  return {data:null,error:"unavailable"};
}

async function changeAccount(action:string, success:string, fields:Record<string,unknown>) {
  const owner=await ownerContext();
  if(!owner) redirect("/kpi");
  const result=await accountRequest(owner,{action,...fields});
  redirect("/kpi/anvandare?"+new URLSearchParams(result.error?{error:result.error}:{success}));
}

async function createForeman(formData:FormData) {
  "use server";
  await changeAccount("create","created",{
    name:formData.get("name"),email:formData.get("email"),password:formData.get("password"),
  });
}
async function changeStatus(formData:FormData) {
  "use server";
  await changeAccount("status","updated",{id:formData.get("id"),status:formData.get("status")});
}
async function resetPassword(formData:FormData) {
  "use server";
  await changeAccount("reset","reset",{id:formData.get("id"),password:formData.get("password")});
}

export default async function UsersPage({searchParams}:{searchParams:Promise<{error?:string;success?:string}>}) {
  const owner=await ownerContext();
  if(!owner)return <main className="kpi-app"><section className="panel"><h1>Åtkomst nekad</h1><a href="/kpi">Tillbaka</a></section></main>;
  const [params, accounts]=await Promise.all([searchParams,accountRequest(owner,{action:"list"})]);
  const members=(accounts.data?.members??[]) as Member[];
  return <div className="kpi-app"><main className="content" style={{maxWidth:950,margin:"0 auto",padding:24}}>
    <a href="/kpi/kontrollpanel">← Kontrollpanelen</a><h1>Användare & behörigheter</h1>
    <p>Skapa arbetsledarkonton med e-postadress och lösenord. Kontona får rollen arbetsledare, inte administratör.</p>
    {accounts.error&&<p role="alert">Användarlistan kunde inte hämtas. Uppdatera sidan för att försöka igen.</p>}
    {params.error&&<p role="alert">{Object.hasOwn(errors,params.error)?errors[params.error]:"Åtgärden kunde inte genomföras."}</p>}
    {params.success&&<p role="status">{params.success==="created"?"Arbetsledarkontot har skapats.":"Ändringen har sparats."}</p>}
    <section className="panel"><h2>Skapa arbetsledare</h2><form action={createForeman} style={{display:"grid",gap:12,maxWidth:440}}>
      <label>Namn<input name="name" required maxLength={120}/></label>
      <label>E-postadress<input name="email" type="email" autoComplete="off" required/></label>
      <label>Tillfälligt lösenord (minst 12 tecken)<input name="password" type="password" minLength={12} autoComplete="new-password" required/></label>
      <button className="primary">Skapa konto</button>
    </form></section>
    <section className="panel"><h2>Befintliga användare</h2>{(members??[]).map(m=><details key={m.user_id} style={{padding:"12px 0",borderBottom:"1px solid #8884"}}>
      <summary><strong>{m.display_name??"Utan namn"}</strong> · {m.email??"E-post saknas"} · {m.role==="owner"?"Ägare":m.role==="supervisor"?"Arbetsledare":m.role} · {m.status==="active"?"Aktiv":"Spärrad"}</summary>
      {m.role==="supervisor"&&<div style={{display:"grid",gap:12,padding:12}}>
        <form action={changeStatus}><input type="hidden" name="id" value={m.user_id}/><input type="hidden" name="status" value={m.status==="active"?"inactive":"active"}/><button>{m.status==="active"?"Spärra konto":"Aktivera konto"}</button></form>
        <form action={resetPassword} style={{display:"flex",gap:8,flexWrap:"wrap"}}><input type="hidden" name="id" value={m.user_id}/><label>Nytt lösenord <input type="password" name="password" minLength={12} required autoComplete="new-password"/></label><button>Byt lösenord</button></form>
      </div>}
    </details>)}</section>
    <p>Områdesbehörigheter styrs fortsatt av Humlas befintliga tilldelningar. Kontoskapandet ger inte automatiskt åtkomst till alla verksamhetsområden.</p>
  </main></div>;
}
