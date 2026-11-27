import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { FunctionsHttpError } from "@supabase/supabase-js";
import { ForemanPasswordForm, type PasswordResult } from "./foreman-password-form";

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
type Member = {user_id:string; display_name:string|null; role:string; status:string; email:string|null; emailConfirmed:boolean};
const errors:Record<string,string> = {
  access:"Du saknar behörighet att hantera det här kontot.",
  duplicate:"E-postadressen används redan av ett konto.",
  validation:"Kontrollera uppgifterna. Lösenordet behöver vara minst 12 tecken och högst 72 byte.",
  create:"Kontot kunde inte skapas.",
  membership:"Kontot kunde inte knytas till arbetsytan.",
  update:"Kontostatusen kunde inte ändras.",
  reset:"Lösenordet kunde inte ändras.",
  confirm_email:"E-postadressen kunde inte bekräftas.",
  email_changed:"E-postadressen har ändrats. Uppdatera sidan och kontrollera adressen igen.",
  shared_account:"Kontot används i flera arbetsytor. Användaren behöver själv använda en inloggningslänk.",
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

async function createAccount(formData:FormData) {
  "use server";
  await changeAccount("create","created",{
    role:formData.get("role"),name:formData.get("name"),email:formData.get("email"),password:formData.get("password"),
  });
}
async function changeStatus(formData:FormData) {
  "use server";
  await changeAccount("status","updated",{id:formData.get("id"),status:formData.get("status")});
}
async function confirmEmail(formData:FormData) {
  "use server";
  await changeAccount("confirm_email","email_confirmed",{id:formData.get("id"),email:formData.get("email")});
}
async function resetPassword(_previous:PasswordResult, formData:FormData):Promise<PasswordResult> {
  "use server";
  const owner=await ownerContext();
  if(!owner)return {success:false,message:errors.access};
  const result=await accountRequest(owner,{
    action:"reset",id:formData.get("id"),password:formData.get("password"),
  });
  if(result.error)return {success:false,message:errors[result.error]??errors.unavailable};
  return {success:true,message:"Lösenordet har ändrats. Användaren kan logga in med det nya lösenordet."};
}

export default async function UsersPage({searchParams}:{searchParams:Promise<{error?:string;success?:string}>}) {
  const owner=await ownerContext();
  if(!owner)return <main className="kpi-app"><section className="panel"><h1>Åtkomst nekad</h1><a href="/kpi">Tillbaka</a></section></main>;
  const [params, accounts]=await Promise.all([searchParams,accountRequest(owner,{action:"list"})]);
  const members=(accounts.data?.members??[]) as Member[];
  return <div className="kpi-app"><main className="content" style={{maxWidth:950,margin:"0 auto",padding:24}}>
    <a href="/kpi/kontrollpanel">← Kontrollpanelen</a><h1>Användare & behörigheter</h1>
    <p>Skapa konton för arbetsledare eller transportadministration.</p>
    {accounts.error&&<p role="alert">Användarlistan kunde inte hämtas. Uppdatera sidan för att försöka igen.</p>}
    {params.error&&<p role="alert">{Object.hasOwn(errors,params.error)?errors[params.error]:"Åtgärden kunde inte genomföras."}</p>}
    {params.success&&<p role="status">{params.success==="created"?"Kontot har skapats.":params.success==="email_confirmed"?"E-postadressen har bekräftats.":"Ändringen har sparats."}</p>}
    <section className="panel"><h2>Skapa konto</h2><form action={createAccount} style={{display:"grid",gap:12,maxWidth:440}}>
      <label>Profil<select name="role" defaultValue="supervisor">
        <option value="supervisor">Arbetsledare</option>
        <option value="transport_admin">Transportadministration – transportdokument</option>
      </select></label>
      <label>Namn<input name="name" required maxLength={120}/></label>
      <label>E-postadress<input name="email" type="email" autoComplete="off" required/></label>
      <label>Tillfälligt lösenord (minst 12 tecken)<input name="password" type="password" minLength={12} autoComplete="new-password" required/></label>
      <button className="primary">Skapa konto</button>
    </form></section>
    <section className="panel"><h2>Befintliga användare</h2>{(members??[]).map(m=><details key={m.user_id} style={{padding:"12px 0",borderBottom:"1px solid #8884"}}>
      <summary><strong>{m.display_name??"Utan namn"}</strong> · {m.email??"E-post saknas"} · {m.role==="owner"?"Ägare":m.role==="supervisor"?"Arbetsledare":m.role==="transport_admin"?"Transportadministration":m.role} · {m.status==="active"?"Aktiv":"Spärrad"}</summary>
      {(m.role==="supervisor"||m.role==="transport_admin")&&<div style={{display:"grid",gap:12,padding:12}}>
        <form action={changeStatus}><input type="hidden" name="id" value={m.user_id}/><input type="hidden" name="status" value={m.status==="active"?"inactive":"active"}/><button>{m.status==="active"?"Spärra konto":"Aktivera konto"}</button></form>
        {m.email&&<div>
          <p>{m.emailConfirmed?"E-post bekräftad":"E-post väntar på bekräftelse"}</p>
          {!m.emailConfirmed&&<form action={confirmEmail}>
            <input type="hidden" name="id" value={m.user_id}/>
            <input type="hidden" name="email" value={m.email}/>
            <p>Bekräfta adressen när du har kontrollerat att den tillhör användaren.</p>
            <button type="submit" className="secondary">Bekräfta e-postadress</button>
          </form>}
        </div>}
        <ForemanPasswordForm accountId={m.user_id} action={resetPassword}/>
      </div>}
    </details>)}</section>
    <p>Områdesbehörigheter styrs fortsatt av Humlas befintliga tilldelningar. Kontoskapandet ger inte automatiskt åtkomst till alla verksamhetsområden.</p>
  </main></div>;
}
