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
};

export default function MailAttachments({files}: {files: Attachment[]}) {
 const [showAll, setShowAll] = useState(false);
 const [busy, setBusy] = useState<string | null>(null);
 const [error, setError] = useState("");
 const [excel, setExcel] = useState<File>();
 const visible = showAll ? files : files.filter(file =>
  /stena|självfaktur|avräkn|mina transporter/i.test([file.filename, file.subject, file.sender].join(" ")));
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

 return <section className="panel">
  <h2>Underlag från mejl</h2>
  <p>Visar sparade PDF- och Excelbilagor. Öppna självfakturan för kontroll eller läs in en Excelbilaga i Stena-importen.</p>
  <label><input type="checkbox" checked={showAll} onChange={event => setShowAll(event.target.checked)}/> Visa även bilagor utan Stena-ord i filnamn, avsändare eller ämne</label>
  {error && <p role="alert">{error}</p>}
  {visible.length === 0 ? <p>Inga matchande bilagor bland de senaste hämtade filerna.</p> :
   <div className="table-wrap"><table className="data-table">
    <thead><tr><th>Bilaga</th><th>Mejl</th><th>Mottaget</th><th>Åtgärd</th></tr></thead>
    <tbody>{visible.map(file => <tr key={file.id}>
     <td>{file.filename}</td><td>{file.sender}<br/>{file.subject}</td>
     <td>{timestamp.format(new Date(file.received_at))}</td>
     <td>{/\.xlsx?$/i.test(file.filename) &&
      <button type="button" disabled={busy !== null} onClick={() => void open(file, true)}>Läs i Stena-importen</button>}
      <button type="button" disabled={busy !== null} onClick={() => void open(file, false)}>Hämta fil</button>
      {busy === file.id && <span role="status"> Hämtar…</span>}
     </td>
    </tr>)}</tbody>
   </table></div>}
  {excel && <div><p>Vald bilaga: <strong>{excel.name}</strong></p>
   <StenaImport initialFile={excel}/>
   <button type="button" onClick={() => setExcel(undefined)}>Stäng bilageimport</button>
  </div>}
 </section>;
}
