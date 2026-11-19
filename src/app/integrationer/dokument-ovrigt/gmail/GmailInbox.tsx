"use client";
import {useState} from "react";
import {useRouter} from "next/navigation";
import {createClient} from "@/lib/supabase/client";

type Mailbox={email:string;enabled:boolean;start_on:string;last_success_at:string|null;last_error:string|null};
type Attachment={id:string;message_id:string;filename:string;sender:string|null;subject:string|null;received_at:string;status:string;error:string|null};
const statuses:Record<string,string>={pending:"Hämtas",stored:"Sparat dokument",unsupported:"Filtypen eller storleken stöds inte",error:"Hämtningen misslyckades"};
const date=(value:string)=>new Intl.DateTimeFormat("sv-SE",{dateStyle:"short",timeStyle:"short",timeZone:"Europe/Stockholm"}).format(new Date(value));
export default function GmailInbox({mailbox,files,connected,connectionError}:{mailbox:Mailbox|null;files:Attachment[];connected:boolean;connectionError:boolean}) {
 const router=useRouter();
 const [busy,setBusy]=useState(false),[error,setError]=useState(""),[notice,setNotice]=useState("");
 const [clientId,setClientId]=useState(""),[secret,setSecret]=useState("");
 const [startOn,setStartOn]=useState(mailbox?.start_on??"");
 async function action(name:string,extra:Record<string,string>={}) {
  setBusy(true);setError("");setNotice("");
  try {
   const {data:{session}}=await createClient().auth.getSession();
   if(!session)throw Error("Logga in i Humla för att fortsätta.");
   const response=await fetch(process.env.NEXT_PUBLIC_SUPABASE_URL+"/functions/v1/gmail-document-import",{
    method:"POST",headers:{"Content-Type":"application/json",Authorization:"Bearer "+session.access_token,apikey:process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!},
    body:JSON.stringify({action:name,...extra}),
   });
   const result=await response.json();
   if(!response.ok||result.error)throw Error(result.error??"Åtgärden misslyckades.");
   if(result.url) {window.location.assign(result.url);return;}
   setNotice(result.busy?"En hämtning pågår redan.":name==="sync"?"Hämtningen är klar. "+(result.stored??0)+" bilagor sparades.":"Inställningen är sparad.");
   router.refresh();
  }catch(e){setError(e instanceof Error?e.message:"Åtgärden misslyckades.");}
  finally{setBusy(false);}
 }
 return <>
  <section className="section">
   <h2>{mailbox?.enabled?"Automatisk hämtning är aktiv":"Anslut Gmail för att starta hämtningen"}</h2>
   <p>PDF, Excel, CSV och bilder sparas i dokumentinkorgen. Varje bilaga får avsändare, mejlrubrik och importstatus. Dokument som redan är sparade återanvänds vid en ny hämtning.</p>
   <p>Hämtning från {mailbox?.start_on??"valt startdatum"}. Senast genomförd hämtning {mailbox?.last_success_at?date(mailbox.last_success_at):"saknas"}.</p>
   {connected&&<p role="status">Google-anslutningen är godkänd. Automatisk hämtning är aktiverad.</p>}
   {connectionError&&<p role="alert">Google-anslutningen kunde inte slutföras. Använd humlaimport@gmail.com och godkänn läsåtkomsten. Kontrollera också OAuth-inställningarna nedan.</p>}
   {mailbox?.last_error&&<p role="alert">{mailbox.last_error}</p>}
   {error&&<p role="alert">{error}</p>}{notice&&<p role="status">{notice}</p>}
   <div className="actions">
    <button disabled={busy||!mailbox?.enabled} onClick={()=>void action("sync")}>{busy?"Arbetar…":"Hämta nu"}</button>
    {mailbox?.last_success_at&&<button disabled={busy} onClick={()=>void action(mailbox.enabled?"pause":"resume")}>{mailbox.enabled?"Pausa hämtning":"Återuppta hämtning"}</button>}
   </div>
   <details open={!mailbox?.enabled&&!mailbox?.last_success_at}><summary>Anslut eller förnya Google-anslutningen</summary>
    <p>Skapa en OAuth-klient för en webbapplikation i Google Cloud och aktivera Gmail API. Lägg till nedanstående adress som godkänd omdirigeringsadress. Ge humlaimport@gmail.com åtkomst till OAuth-appen.</p>
    <p><code>https://vuurtaafxvevbhdzgttq.supabase.co/functions/v1/gmail-document-import</code></p>
    <div className="formgrid">
     <label>Google klient-ID<input value={clientId} onChange={e=>setClientId(e.target.value)} autoComplete="off"/></label>
     <label>Google klienthemlighet<input type="password" value={secret} onChange={e=>setSecret(e.target.value)} autoComplete="new-password"/></label>
     {!mailbox?.last_success_at&&<label>Hämta dokument från<input type="date" value={startOn} onChange={e=>setStartOn(e.target.value)}/></label>}
    </div>
    <p>Vid förnyad anslutning kan de sparade klientuppgifterna användas. När Google ber dig välja konto, välj humlaimport@gmail.com.</p>
    <button disabled={busy||!mailbox} onClick={()=>void action("connect",{client_id:clientId.trim(),client_secret:secret,...(!mailbox?.last_success_at?{start_on:startOn}:{})})}>Anslut humlaimport@gmail.com</button>
   </details>
  </section>
  <section className="section"><h2>Dokumentinkorg</h2>
   <p>De senaste 100 bilagorna visas. Öppna ett dokument för granskning och vidare import.</p>
   {!files.length?<p>Inga bilagor har hämtats ännu.</p>:<div className="table-wrap"><table className="data-table">
    <thead><tr><th>Dokument</th><th>Avsändare och mejlrubrik</th><th>Mottaget</th><th>Importstatus</th><th>Mejl</th></tr></thead>
    <tbody>{files.map(file=><tr key={file.id}>
     <td>{file.status==="stored"?<button disabled={busy} onClick={()=>void action("download",{id:file.id})}>{file.filename}</button>:file.filename}</td>
     <td>{file.sender}<br/>{file.subject}</td><td>{date(file.received_at)}</td>
     <td>{statuses[file.status]??file.status}{file.error&&<><br/>{file.error}</>}</td>
     <td><a href={"https://mail.google.com/mail/u/?authuser=humlaimport%40gmail.com#all/"+encodeURIComponent(file.message_id)} target="_blank" rel="noreferrer">Öppna Gmail</a></td>
    </tr>)}</tbody>
   </table></div>}
  </section>
 </>;
}
