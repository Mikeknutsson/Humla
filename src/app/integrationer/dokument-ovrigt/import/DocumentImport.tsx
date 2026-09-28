"use client";
import {useRef,useState} from "react";
import {createBrowserClient} from "@supabase/ssr";

type Row={date?:string;article_number?:string;description?:string;quantity?:number;unit_price?:number;amount?:number;note?:string};
type Order={order_number?:string;project_reference?:string;title?:string;vehicle?:string;rows?:Row[];total?:number;validation?:{total_matches?:boolean;warnings?:string[]}};
type Result={ok:boolean;parser_key?:string;extraction?:{orders?:Order[];order_count?:number};canonicalization?:{accepted?:boolean;orders?:number;rows?:number;events?:number};reason?:string;error?:string;detail?:string};

const tenant="944597b6-9c46-4bef-998d-f19e23c4245b";
const money=(n?:number)=>new Intl.NumberFormat("sv-SE",{style:"currency",currency:"SEK"}).format(n??0);

export default function DocumentImport(){
 const input=useRef<HTMLInputElement>(null); const [file,setFile]=useState<File|null>(null); const [busy,setBusy]=useState(false); const [result,setResult]=useState<Result|null>(null); const [error,setError]=useState("");
 async function run(){
  if(!file)return; setBusy(true);setError("");setResult(null);
  try{
   const supabase=createBrowserClient(process.env.NEXT_PUBLIC_SUPABASE_URL!,process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!);
   const {data:{session}}=await supabase.auth.getSession(); if(!session)throw new Error("Du behöver vara inloggad för att importera.");
   const fd=new FormData();fd.append("file",file);fd.append("tenant_id",tenant);
   const res=await fetch(process.env.NEXT_PUBLIC_SUPABASE_URL+"/functions/v1/hub-document-import",{method:"POST",headers:{Authorization:"Bearer "+session.access_token,apikey:process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!},body:fd});
   const json=await res.json();if(!res.ok)throw new Error(json.detail||json.error||"Importen misslyckades.");setResult(json);
  }catch(e){setError(e instanceof Error?e.message:"Importen misslyckades.");}finally{setBusy(false)}
 }
 const orders=result?.extraction?.orders||[]; const rows=orders.reduce((n,o)=>n+(o.rows?.length||0),0); const warnings=orders.reduce((n,o)=>n+(o.validation?.warnings?.length||0),0);
 return <div>
  <section className="importDrop" onClick={()=>input.current?.click()} onDragOver={e=>e.preventDefault()} onDrop={e=>{e.preventDefault();const f=e.dataTransfer.files[0];if(f?.type==="application/pdf")setFile(f)}}>
   <input ref={input} type="file" accept="application/pdf" hidden onChange={e=>setFile(e.target.files?.[0]||null)}/>
   <div className="importIcon">PDF</div><div><b>{file?file.name:"Släpp en PDF här"}</b><p>{file?Math.round(file.size/1024)+" kB · Klar att importera":"eller klicka för att välja fil · max 20 MB"}</p></div>
   <button type="button" onClick={e=>{e.stopPropagation();run()}} disabled={!file||busy}>{busy?"Tolkar…":"Importera"}</button>
  </section>
  {error&&<div className="importAlert bad"><b>Importen stoppades</b><span>{error}</span></div>}
  {result&&<><div className="importSummary">
   <article><small>STATUS</small><b className={result.ok?"green":""}>{result.ok?"Godkänd":"Kontroll krävs"}</b></article>
   <article><small>ORDRAR</small><b>{orders.length}</b></article><article><small>ORDERRADER</small><b>{rows}</b></article>
   <article><small>VARNINGAR</small><b>{warnings}</b></article><article><small>CANONICAL</small><b>{result.canonicalization?.accepted?"Skapad":"Ej skapad"}</b></article>
  </div>
  <section className="section"><div className="sectionhead"><div><span className="label">FÖRHANDSGRANSKNING</span><h2>Hittade ordrar</h2></div><span className="badge good">{result.parser_key||"Dokumentparser"}</span></div>
   <div className="orderPreview">{orders.map((o,i)=><details key={(o.order_number||"order")+i} open={i===0}><summary><span><small>ORDER</small><strong>{o.order_number||"Saknas"}</strong></span><span><small>PROJEKT / LITTRA</small><strong>{o.project_reference||"Saknar matchning"}</strong></span><span><small>RADER</small><strong>{o.rows?.length||0}</strong></span><span><small>SUMMA</small><strong>{money(o.total)}</strong></span><i className={o.validation?.total_matches?"pass":"stop"}>{o.validation?.total_matches?"✓":"!"}</i></summary>
    <div className="orderRows"><div className="orow head"><span>Datum</span><span>Artikel</span><span>Beskrivning</span><span>Antal</span><span>Á-pris</span><span>Belopp</span></div>{(o.rows||[]).map((r,j)=><div className="orow" key={j}><span>{r.date}</span><span>{r.article_number}</span><span>{r.description}{r.note&&<small>{r.note}</small>}</span><span>{r.quantity}</span><span>{money(r.unit_price)}</span><span>{money(r.amount)}</span></div>)}</div>
   </details>)}</div>
  </section></>}
 </div>
}