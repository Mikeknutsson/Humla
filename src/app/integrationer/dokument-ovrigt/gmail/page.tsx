import Link from "next/link";
import {createClient} from "@/lib/supabase/server";
import GmailInbox from "./GmailInbox";

export const dynamic="force-dynamic";
export default async function Page({searchParams}:{searchParams:Promise<Record<string,string|undefined>>}) {
 const db=await createClient();
 const {data:{user}}=await db.auth.getUser();
 if(!user)return <section className="section"><h1>Gmail dokumentimport</h1><Link href="/kpi/login">Logga in i Humla</Link></section>;
 const {data:member}=await db.from("hub_tenant_members").select("tenant_id").eq("user_id",user.id).eq("role","owner").eq("status","active").maybeSingle();
 if(!member)return <section className="section"><h1>Ägarbehörighet krävs för dokumentinkorgen.</h1></section>;
 const [mailbox,files]=await Promise.all([
  db.from("hub_gmail_mailboxes").select("email,enabled,start_on,last_success_at,last_error").eq("tenant_id",member.tenant_id).maybeSingle(),
  db.from("hub_gmail_attachments").select("id,message_id,filename,sender,subject,received_at,status,error").eq("tenant_id",member.tenant_id).order("received_at",{ascending:false}).limit(100),
 ]);
 const params=await searchParams;
 return <>
  <Link href="/integrationer/dokument-ovrigt" className="backlink">← Dokument & övrigt</Link>
  <header className="topbar"><div><h1>Gmail dokumentimport</h1><p>Bilagor från humlaimport@gmail.com hämtas var femte minut.</p></div></header>
  {(mailbox.error||files.error)&&<p role="alert">Importstatus kunde inte hämtas. Försök igen.</p>}
  <GmailInbox mailbox={mailbox.data} files={files.data??[]} connected={params.connected==="1"} connectionError={params.connection_error==="1"}/>
 </>;
}
