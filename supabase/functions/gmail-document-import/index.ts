import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const db = createClient(supabaseUrl, serviceKey, {auth:{persistSession:false}});
const callback = supabaseUrl + "/functions/v1/gmail-document-import";
const appUrl = "https://humla-humla.vercel.app/integrationer/dokument-ovrigt/gmail";
const mailboxEmail = "humlaimport@gmail.com";
const cors = {
 "Access-Control-Allow-Origin":"https://humla-humla.vercel.app",
 "Access-Control-Allow-Headers":"authorization, apikey, content-type, x-client-info",
 "Access-Control-Allow-Methods":"POST, OPTIONS",
};
const reply = (data:unknown,status=200) => Response.json(data,{status,headers:{...cors,"Cache-Control":"no-store"}});
const checked = <T>(result:{data:T;error:unknown}) => {if(result.error)throw Error("Humla kunde inte spara importen.");return result.data;};
const random = () => crypto.randomUUID() + crypto.randomUUID();
const sha256 = async (bytes:Uint8Array) => [...new Uint8Array(await crypto.subtle.digest("SHA-256",bytes))].map(x=>x.toString(16).padStart(2,"0")).join("");
const base64url = (bytes:Uint8Array) => btoa(String.fromCharCode(...bytes)).replace(/\+/g,"-").replace(/\//g,"_").replace(/=+$/,"");
const decode = (data:string) => Uint8Array.from(atob(data.replace(/-/g,"+").replace(/_/g,"/")),c=>c.charCodeAt(0));

async function credentials(connection:{tenant_id:string;connection_id:string}) {
 return checked(await db.rpc("hub_get_connection_credentials",{p_tenant_id:connection.tenant_id,p_connection_id:connection.connection_id})) as Record<string,string>;
}
async function exchange(client:Record<string,string>,params:Record<string,string>) {
 const response=await fetch("https://oauth2.googleapis.com/token",{
  method:"POST",headers:{"Content-Type":"application/x-www-form-urlencoded"},
  body:new URLSearchParams({client_id:client.client_id,client_secret:client.client_secret,...params}),
  signal:AbortSignal.timeout(20000),
 });
 if(!response.ok)throw Error("Google-anslutningen behöver kontrolleras eller anslutas igen.");
 return response.json() as Promise<{access_token:string;refresh_token?:string}>;
}
async function google<T>(token:string,path:string):Promise<T> {
 const response=await fetch("https://gmail.googleapis.com/gmail/v1/users/me/"+path,{
  headers:{Authorization:"Bearer "+token},signal:AbortSignal.timeout(20000),
 });
 if(!response.ok) {
  const error=new Error("Gmail kunde inte läsas (HTTP "+response.status+"). Nästa körning försöker igen.");
  Object.assign(error,{httpStatus:response.status});
  throw error;
 }
 return response.json();
}
type Mailbox={connection_id:string;tenant_id:string;start_on:string;scan_after:number|null;scan_until:number|null;page_token:string|null;};
type Part={partId:string;filename?:string;mimeType:string;body?:{size?:number;attachmentId?:string;data?:string};parts?:Part[]};
function attachments(part:Part):Part[] {
 return [...(part.filename?[part]:[]),...(part.parts??[]).flatMap(attachments)];
}
function documentMime(name:string) {
 const extension=name.toLowerCase().split(".").pop();
 const types:Record<string,string>={pdf:"application/pdf",xlsx:"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",xls:"application/vnd.ms-excel",csv:"text/csv",png:"image/png",jpg:"image/jpeg",jpeg:"image/jpeg",tif:"image/tiff",tiff:"image/tiff"};
 return types[extension??""];
}
async function saveAttachment(box:Mailbox,messageId:string,part:Part,message:{internalDate:string;payload:{headers?:{name:string;value:string}[]}},token:string) {
 const filename=part.filename!;
 const partId=part.partId||part.body?.attachmentId;
 if(!partId)throw Error("Gmail-bilagan saknar identitet.");
 const existing=checked(await db.from("hub_gmail_attachments").select("status").eq("connection_id",box.connection_id).eq("message_id",messageId).eq("part_id",partId).maybeSingle());
 if(existing?.status==="stored"||existing?.status==="unsupported")return false;
 const header=(name:string)=>message.payload.headers?.find(h=>h.name.toLowerCase()===name)?.value??"";
 const mime=documentMime(filename);
 const unsupported=!mime||(part.body?.size??0)>20*1024*1024;
 const row=checked(await db.from("hub_gmail_attachments").upsert({
  tenant_id:box.tenant_id,connection_id:box.connection_id,message_id:messageId,part_id:partId,
  filename,mime_type:mime||part.mimeType,sender:header("from"),subject:header("subject"),
  received_at:new Date(Number(message.internalDate)).toISOString(),byte_size:part.body?.size??null,
  status:unsupported?"unsupported":"pending",error:unsupported?"Filtypen stöds inte eller filen är större än 20 MB.":null,
 },{onConflict:"connection_id,message_id,part_id"}).select("id").single());
 if(unsupported)return false;
 try {
  const body=part.body?.attachmentId?await google<{data:string}>(token,"messages/"+encodeURIComponent(messageId)+"/attachments/"+encodeURIComponent(part.body.attachmentId)):part.body;
  if(!body?.data)throw Error("Bilagan saknar filinnehåll.");
  const bytes=decode(body.data);
  if(bytes.length>20*1024*1024)throw Error("Bilagan är större än 20 MB.");
  const hash=await sha256(bytes);
  let document=checked(await db.from("hub_documents").select("id").eq("tenant_id",box.tenant_id).eq("sha256",hash).limit(1).maybeSingle());
  if(!document) {
   const path=box.tenant_id+"/gmail/"+hash;
   const uploaded=await db.storage.from("hub-documents").upload(path,bytes,{contentType:mime,upsert:false});
   if(uploaded.error&&uploaded.error.message!=="The resource already exists")throw Error("Dokumentfilen kunde inte sparas.");
   document=checked(await db.from("hub_documents").insert({
    tenant_id:box.tenant_id,document_type:"email_attachment",filename,mime_type:mime,sha256:hash,
    storage_provider:"supabase",storage_reference:path,
    metadata:{source:"gmail",connection_id:box.connection_id,message_id:messageId,part_id:partId},
   }).select("id").single());
  }
  checked(await db.from("hub_gmail_attachments").update({document_id:document.id,sha256:hash,status:"stored",error:null}).eq("id",row.id));
  return true;
 } catch(error) {
  checked(await db.from("hub_gmail_attachments").update({status:"error",error:error instanceof Error?error.message:"Bilagan kunde inte sparas."}).eq("id",row.id));
  throw error;
 }
}
async function sync(box:Mailbox) {
 const lease=crypto.randomUUID();
 if(!checked(await db.rpc("hub_gmail_claim_v1",{p_connection:box.connection_id,p_lease:lease})))return {busy:true};
 try {
  const client=await credentials(box);
  if(!client.refresh_token)throw Error("Godkänn Gmail-anslutningen för att starta importen.");
  const fresh=await exchange(client,{grant_type:"refresh_token",refresh_token:client.refresh_token});
  const profile=await google<{emailAddress:string}>(fresh.access_token,"profile");
  if(profile.emailAddress.toLowerCase()!==mailboxEmail)throw Error("Anslutningen gäller fel Gmail-konto.");
  const deadline=Date.now()+110000;
  const after=box.scan_after??Math.floor(Date.parse(box.start_on+"T00:00:00Z")/1000);
  const until=box.scan_until??Math.floor(Date.now()/1000);
  const params=new URLSearchParams({q:"has:attachment after:"+after+" before:"+until,maxResults:"10"});
  if(box.page_token)params.set("pageToken",box.page_token);
  let page:{messages?:{id:string}[];nextPageToken?:string};
  try {
   page=await google(fresh.access_token,"messages?"+params);
  } catch(error) {
   // Restart an expired Gmail page token against the same fixed time window.
   if(box.page_token&&error instanceof Error&&"httpStatus" in error&&error.httpStatus===400) {
    checked(await db.from("hub_gmail_mailboxes").update({page_token:null}).eq("connection_id",box.connection_id).eq("lease_id",lease));
   }
   throw error;
  }
  let stored=0;
  for(const item of page.messages??[]) {
   if(Date.now()>deadline)throw Error("Hämtningen fortsätter vid nästa körning.");
   const message=await google<{internalDate:string;payload:Part&{headers?:{name:string;value:string}[]}}>(fresh.access_token,"messages/"+encodeURIComponent(item.id)+"?format=full");
   for(const part of attachments(message.payload)) {
    if(Date.now()>deadline)throw Error("Hämtningen fortsätter vid nästa körning.");
    if(await saveAttachment(box,item.id,part,message,fresh.access_token))stored++;
   }
  }
  checked(await db.from("hub_gmail_mailboxes").update({
   page_token:page.nextPageToken??null,scan_until:page.nextPageToken?until:null,
   scan_after:page.nextPageToken?after:Math.max(after,until-86400),
   last_success_at:new Date().toISOString(),last_error:null,
  }).eq("connection_id",box.connection_id).eq("lease_id",lease));
  return {stored,more:Boolean(page.nextPageToken)};
 } catch(error) {
  const message=error instanceof Error?error.message:"Importen misslyckades.";
  checked(await db.from("hub_gmail_mailboxes").update({last_error:message}).eq("connection_id",box.connection_id).eq("lease_id",lease));
  return {error:message};
 } finally {
  await db.from("hub_gmail_mailboxes").update({lease_id:null,lease_until:null}).eq("connection_id",box.connection_id).eq("lease_id",lease);
 }
}
Deno.serve(async req=>{
 if(req.method==="OPTIONS")return new Response("ok",{headers:cors});
 const url=new URL(req.url);
 if(req.method==="GET") {
  try {
   const state=url.searchParams.get("state");
   if(!state)throw Error("Ogiltig anslutning.");
   const request=checked(await db.rpc("hub_gmail_oauth_state_v1",{p_state:state}));
   const box=checked(await db.from("hub_gmail_mailboxes").select("*").eq("connection_id",request.connection_id).single());
   const code=url.searchParams.get("code");
   if(!code)throw Error("Google-anslutningen avbröts.");
   const client=await credentials(box);
   const tokens=await exchange(client,{grant_type:"authorization_code",code,redirect_uri:callback,code_verifier:request.verifier});
   const profile=await google<{emailAddress:string}>(tokens.access_token,"profile");
   if(profile.emailAddress.toLowerCase()!==mailboxEmail)throw Error("Välj humlaimport@gmail.com vid anslutning.");
   if(!tokens.refresh_token)throw Error("Google gav ingen behörighet för automatisk hämtning. Anslut igen.");
   checked(await db.rpc("hub_set_connection_secret",{p_tenant_id:box.tenant_id,p_connection_id:box.connection_id,p_credential_name:"refresh_token",p_secret_value:tokens.refresh_token}));
   checked(await db.from("hub_gmail_mailboxes").update({enabled:true,last_error:null}).eq("connection_id",box.connection_id));
   checked(await db.from("hub_connections").update({status:"active"}).eq("id",box.connection_id));
   return Response.redirect(appUrl+"?connected=1",303);
  } catch {return Response.redirect(appUrl+"?connection_error=1",303);}
 }
 if(req.method!=="POST")return reply({error:"POST required"},405);
 try {
  const body=await req.json();
  const worker=req.headers.get("x-humla-worker-key");
  if(worker) {
   if(!checked(await db.rpc("hub_verify_worker_key",{p_key:worker})))return reply({error:"Unauthorized"},401);
   if(body.action!=="sync")return reply({error:"Invalid worker action"},400);
   const boxes=checked(await db.from("hub_gmail_mailboxes").select("*").eq("enabled",true));
   const results=[];
   for(const box of boxes)results.push(await sync(box));
   return reply({results});
  }
  const bearer=req.headers.get("Authorization")?.replace(/^Bearer /,"");
  if(!bearer)return reply({error:"Logga in i Humla."},401);
  const {data:{user},error}=await db.auth.getUser(bearer);
  if(error||!user)return reply({error:"Logga in i Humla."},401);
  const member=checked(await db.from("hub_tenant_members").select("tenant_id").eq("user_id",user.id).eq("role","owner").eq("status","active").maybeSingle());
  if(!member)return reply({error:"Ägarbehörighet krävs."},403);
  const box=checked(await db.from("hub_gmail_mailboxes").select("*").eq("tenant_id",member.tenant_id).single());
  if(body.action==="connect") {
   if(body.start_on&&!box.last_success_at) {
    if(typeof body.start_on!=="string"||!/^\d{4}-\d{2}-\d{2}$/.test(body.start_on)||!Number.isFinite(Date.parse(body.start_on))||new Date(body.start_on).toISOString().slice(0,10)!==body.start_on)return reply({error:"Välj ett giltigt startdatum."},400);
    checked(await db.from("hub_gmail_mailboxes").update({start_on:body.start_on,scan_after:null,page_token:null,scan_until:null}).eq("connection_id",box.connection_id));
   }
   if(typeof body.client_id==="string"&&typeof body.client_secret==="string"&&body.client_id.endsWith(".apps.googleusercontent.com")&&body.client_secret) {
    for(const name of ["client_id","client_secret"])checked(await db.rpc("hub_set_connection_secret",{p_tenant_id:box.tenant_id,p_connection_id:box.connection_id,p_credential_name:name,p_secret_value:body[name]}));
   }
   const client=await credentials(box);
   if(!client.client_id||!client.client_secret)return reply({error:"Google OAuth-klientens klient-ID och klienthemlighet behövs."},400);
   const state=random(),verifier=random();
   checked(await db.rpc("hub_gmail_oauth_state_v1",{p_state:state,p_connection:box.connection_id,p_verifier:verifier}));
   const authorize=new URL("https://accounts.google.com/o/oauth2/v2/auth");
   const challenge=base64url(new Uint8Array(await crypto.subtle.digest("SHA-256",new TextEncoder().encode(verifier))));
   for(const [k,v] of Object.entries({client_id:client.client_id,redirect_uri:callback,response_type:"code",scope:"https://www.googleapis.com/auth/gmail.readonly",access_type:"offline",prompt:"consent",login_hint:mailboxEmail,state,code_challenge:challenge,code_challenge_method:"S256"}))authorize.searchParams.set(k,v);
   return reply({url:authorize.toString()});
  }
  if(body.action==="sync")return reply(await sync(box));
  if(body.action==="pause") {
   checked(await db.from("hub_gmail_mailboxes").update({enabled:false}).eq("connection_id",box.connection_id));
   return reply({ok:true});
  }
  if(body.action==="resume") {
   if(!(await credentials(box)).refresh_token)return reply({error:"Anslut Gmail först."},400);
   checked(await db.from("hub_gmail_mailboxes").update({enabled:true}).eq("connection_id",box.connection_id));
   return reply({ok:true});
  }
  if(body.action==="download") {
   const file=checked(await db.from("hub_gmail_attachments").select("document_id,filename").eq("id",body.id).eq("tenant_id",member.tenant_id).single());
   const doc=checked(await db.from("hub_documents").select("storage_reference,storage_provider").eq("id",file.document_id).eq("tenant_id",member.tenant_id).single());
   if(doc.storage_provider!=="supabase")return reply({error:"Dokumentet behöver öppnas i sin källmodul."},400);
   const signed=checked(await db.storage.from("hub-documents").createSignedUrl(doc.storage_reference,60,{download:file.filename}));
   return reply({url:signed.signedUrl});
  }
  return reply({error:"Okänd åtgärd."},400);
 } catch {return reply({error:"Dokumentimporten kunde inte genomföras. Försök igen."},500);}
});
