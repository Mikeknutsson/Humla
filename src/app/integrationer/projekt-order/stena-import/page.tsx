"use client";
import {useState} from "react";
import * as XLSX from "xlsx";

type Preview={sheet:string;row:number;registration:string;amount:number;status:string};
const numeric=(v:unknown)=>{if(typeof v==="number")return Number.isFinite(v)?v:0;const s=String(v??"").replace(/\s/g,"").replace(",",".");const n=Number(s);return Number.isFinite(n)?n:0};
const normalize=(v:unknown)=>String(v??"").trim().toUpperCase();
export default function StenaImportPage(){
 const [rows,setRows]=useState<Preview[]>([]);const [error,setError]=useState("");const [filename,setFilename]=useState("");
 async function read(file:File){setError("");setRows([]);setFilename(file.name);
 try{const workbook=XLSX.read(await file.arrayBuffer(),{type:"array",cellDates:true});const result:Preview[]=[];
 const hist=workbook.Sheets["Historik"];if(!hist)throw Error("Fliken Historik saknas.");
 const data=XLSX.utils.sheet_to_json<unknown[]>(hist,{header:1,defval:""});
 data.forEach((r,i)=>{if(i===0||!Array.isArray(r))return;const reg=normalize(r[1]);const h=numeric(r[7]),j=numeric(r[8]),n=numeric(r[13]);if(!reg&&!h&&!j&&!n)return;
 const amount=Math.round((h+j)*n*100)/100;
 result.push({sheet:"Historik",row:i+1,registration:reg||"INHYRDA LASTBILAR",amount,status:!n?"Kontrollera prisfaktor":!reg?"Saknar regnr – inhyrd":"Förhandsgranskning"});});
 const av=workbook.Sheets["Avräknade"];if(av){const ar=XLSX.utils.sheet_to_json<Record<string,unknown>>(av,{defval:""});ar.forEach((r,i)=>{const key=Object.keys(r).find(k=>normalize(k)==="PRIS SEK");if(!key)return;const amount=numeric(r[key]);if(!amount)return;result.push({sheet:"Avräknade",row:i+2,registration:"Kräver radmatchning",amount,status:"Avräknat belopp – kontrollera koppling"});});}
 if(!result.length)throw Error("Inga beräkningsbara rader hittades. Kontrollera Stenas filformat.");
 setRows(result);
 }catch(e){setError(e instanceof Error?e.message:"Kunde inte läsa filen.");}}
 const historik=rows.filter(r=>r.sheet==="Historik");const sum=historik.reduce((s,r)=>s+r.amount,0);
 return <main style={{padding:24,maxWidth:1100}}><h1>Stena – import av avräkningsunderlag</h1><p>Läs in Stenas Excelunderlag och granska poster innan de förs över till Humla Hub.</p>
 <input type="file" accept=".xlsx,.xls" onChange={e=>{const f=e.target.files?.[0];if(f)void read(f)}} aria-label="Välj Stena Excelunderlag"/>
 {error&&<p role="alert">{error}</p>}
 {rows.length>0&&<><h2>Förhandsgranskning: {filename}</h2><p>Historik: {historik.length} rader · beräknat {sum.toLocaleString("sv-SE",{style:"currency",currency:"SEK"})}. Avräknade: {rows.length-historik.length} rader.</p>
 <p><strong>Ingen data sparas ännu.</strong> Historik beräknas som (H + I) × N med registreringsnummer i kolumn B. Avräknade visas separat tills säker radmatchning och dubblettskydd är inkopplade.</p>
 <div style={{overflowX:"auto"}}><table><thead><tr><th>Flik</th><th>Rad</th><th>Fordon</th><th>Belopp</th><th>Status</th></tr></thead><tbody>{rows.slice(0,500).map((r,i)=><tr key={i}><td>{r.sheet}</td><td>{r.row}</td><td>{r.registration}</td><td>{r.amount.toLocaleString("sv-SE")} kr</td><td>{r.status}</td></tr>)}</tbody></table></div>{rows.length>500&&<p>Visar de första 500 raderna.</p>}</>}
 </main>;
}
