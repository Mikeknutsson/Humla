"use client";

import {useState} from "react";
import {StenaImport} from "@/app/_components/stena-import";
import {createClient} from "@/lib/supabase/client";

export type Attachment = {
 id: string;
 filename: string;
 sender: string | null;
 subject: string | null;
 received_at: string;
 document_id: string | null;
};

export default function MailAttachments({files}: {files: Attachment[]}) {
 const [showAll, setShowAll] = useState(false);
 const [search,setSearch] = useState("");
 const [page,setPage] = useState(0);
 const [busy, setBusy] = useState<string | null>(null);
 const [error, setError] = useState("");
 const [excel, setExcel] = useState<File>();
 const [payout, setPayout] = useState<{id:string;invoice:string}>();
 const [confirmedDate,setConfirmedDate] = useState("");
 const [notice,setNotice] = useState("");

 async function recordPayout(id:string,date?:string) {
  setBusy(id);setError("");setNotice("");
  try {
   const response=await fetch("/api/kpi/stena-payout",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({id,confirmedDate:date})});
   const result=await response.json();
   if(!response.ok)throw Error(result.error??"Datumet kunde inte sparas.");
   if(result.needsConfirmation){setPayout({id,invoice:result.invoice});setConfirmedDate("");return;}
   setPayout(undefined);
   setNotice(`Faktura ${result.invoice}: utbetalningsdatum ${result.date} sparat för ${result.bookings} bokningar.`);
  }catch(e){setError(e instanceof Error?e.message:"Utbetalningsdatumet kunde inte sparas.");}
  finally{setBusy(null);}
 }
 const eligible = files.filter(file => showAll || /stena|självfaktur|avräkn|mina transporter/i.test([file.filename, file.subject, file.sender].join(" ")));
 const unique = Array.from(new Map(eligible.map(file => [file.document_id??file.id,file])).values());
 const visible = unique.filter(file => [file.filename,file.subject,file.sender].join(" ").toLocaleLowerCase("sv").includes(search.trim().toLocaleLowerCase("sv")));
 const pageSize = 20;
 const timestamp = new Intl.DateTimeFormat("sv-SE", {dateStyle: "short", timeZone: "Europe/Stockholm"});

 async function open(file: Attachment, prepareImport: boolean) {
  setBusy(file.id);
  setError("");
  try {
   const {data: {session}} = await createClient().auth.getSession();
   if (!session) throw new Error("Logga in i Humla igen.");
   const response = await fetch(process.env.NEXT_PUBLIC_SUPABASE_URL + "/functions/v1/gmail-document-import", {
    method: "POST",
    headers: {"Content-Type": "application/json", Authorization: "Bearer " + session.access_token, apikey: process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!},
    body: JSON.stringify({action: "download", id: file.id}),
   });
   const result = await response.json();
   if (!response.ok || !result.url) throw new Error("Bilagan kunde inte öppnas.");
   if (!prepareImport) {
    window.location.assign(result.url);
    return;
   }
   const attachment = await fetch(result.url);
   if (!attachment.ok) throw new Error("Bilagan kunde inte hämtas.");
   setExcel(new File([await attachment.blob()], file.filename));
  } catch (cause) {
   setError(cause instanceof Error ? cause.message : "Bilagan kunde inte hämtas.");
  } finally {
   setBusy(null);
  }
 }

 return <section className="panel weekly-panel">
  <h2>Underlag från mejl</h2>
  <p>Visar sparade PDF- och Excelbilagor. Öppna självfakturan för kontroll eller läs in en Excelbilaga i Stena-importen.</p>
  <label><input type="checkbox" checked={showAll} onChange={event => {setShowAll(event.target.checked);setPage(0);}}/> Visa även bilagor utan Stena-ord i filnamn, avsändare eller ämne</label>
  <p><label>Sök i de senaste bilagorna <input type="search" value={search} onChange={event=>{setSearch(event.target.value);setPage(0);}}/></label></p>
  {error && <p role="alert">{error}</p>}
  {notice && <p role="status">{notice}</p>}
  {payout&&<form onSubmit={event=>{event.preventDefault();void recordPayout(payout.id,confirmedDate);}}>
   <p>Humla kunde inte läsa ett entydigt utbetalningsdatum på faktura {payout.invoice}. Öppna PDF-filen och ange datumet som står där.</p>
   <label>Utbetalningsdatum <input type="date" required value={confirmedDate} onChange={event=>setConfirmedDate(event.target.value)}/></label>
   <button type="submit" className="secondary" disabled={busy!==null}>Spara datum</button>
   <button type="button" className="secondary" onClick={()=>{const file=files.find(item=>item.id===payout.id);if(file)void open(file,false);}}>Hämta PDF</button>
   <button type="button" className="secondary" onClick={()=>setPayout(undefined)}>Avbryt</button>
  </form>}
  {visible.length === 0 ? <p>Inga matchande bilagor bland de senaste hämtade filerna.</p> :
   <div className="table-wrap"><table className="data-table">
    <thead><tr><th>Bilaga</th><th>Mejl</th><th>Mottaget</th><th>Åtgärd</th></tr></thead>
    <tbody>{visible.slice(page*pageSize,(page+1)*pageSize).map(file => <tr key={file.id}>
     <td>{file.filename}</td><td>{file.sender}<br/>{file.subject}</td>
     <td>{timestamp.format(new Date(file.received_at))}</td>
     <td>{/\.xlsx?$/i.test(file.filename) &&
      <button className="secondary" type="button" disabled={busy !== null} onClick={() => void open(file, true)}>Läs i Stena-importen</button>}
      <button className="secondary" type="button" disabled={busy !== null} onClick={() => void open(file, false)}>Hämta fil</button>
      {/^[0-9]{5,16}\.pdf$/.test(file.filename)&&/Stena Recycling/i.test(file.subject??"")&&
       <button className="secondary" type="button" disabled={busy!==null} onClick={()=>void recordPayout(file.id)}>Läs utbetalningsdatum</button>}
      {busy === file.id && <span role="status"> Hämtar…</span>}
     </td>
    </tr>)}</tbody>
   </table></div>}
  {page>0&&<button type="button" className="secondary" onClick={()=>setPage(page-1)}>Föregående bilagor</button>}
  {(page+1)*pageSize<visible.length&&<button type="button" className="secondary" onClick={()=>setPage(page+1)}>Nästa bilagor</button>}
  {excel && <div><p>Vald bilaga: <strong>{excel.name}</strong></p>
   <StenaImport initialFile={excel} refreshOnImport/>
   <button className="secondary" type="button" onClick={() => setExcel(undefined)}>Stäng bilageimport</button>
  </div>}
 </section>;
}
