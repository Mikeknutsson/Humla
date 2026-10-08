'use client';
import {useState} from 'react';
import Link from 'next/link';
import {parsePaymentCsv} from '@/lib/hub/payment-import';
import type {Payment,PaymentForecast} from '@/lib/hub/payment-forecast';
const money=(n:number|null)=>n===null?'Underlag saknas':new Intl.NumberFormat('sv-SE',{style:'currency',currency:'SEK',maximumFractionDigits:0}).format(n);
function download(name:string,text:string){const url=URL.createObjectURL(new Blob([text],{type:'text/csv;charset=utf-8'}));const a=document.createElement('a');a.href=url;a.download=name;a.click();setTimeout(()=>URL.revokeObjectURL(url),1000)}
export function PaymentForecastWorkspace(){
 const [asOf,setAsOf]=useState(()=>new Intl.DateTimeFormat('sv-SE',{timeZone:'Europe/Stockholm',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date()));
 const [historyFrom,setHistoryFrom]=useState(''),[historyTo,setHistoryTo]=useState('');
 const [ledger,setLedger]=useState<Payment[]|null>(null),[history,setHistory]=useState<Payment[]>([]);
 const [files,setFiles]=useState({ledger:'',history:''});
 const [basis,setBasis]=useState<'payment'|'booked'>('payment'),[inDays,setInDays]=useState(30),[outDays,setOutDays]=useState(30);
 const [result,setResult]=useState<PaymentForecast|null>(null),[error,setError]=useState(''),[busy,setBusy]=useState(false);
 const invalidate=()=>{setResult(null);setError('')};
 async function upload(file:File|undefined,kind:'ledger'|'history'){
  invalidate();if(!file)return;setBusy(true);if(kind==='ledger'){setLedger(null)}else setHistory([]);setFiles(p=>({...p,[kind]:''}));
  try{if(file.size>4_000_000)throw Error('Max 4 MB per fil');const rows=parsePaymentCsv(await file.text());if(kind==='ledger')setLedger(rows);else setHistory(rows);setFiles(p=>({...p,[kind]:file.name}))}catch(e){setError(e instanceof Error?e.message:'Import misslyckades')}finally{setBusy(false)}
 }
 async function calculate(){setBusy(true);setError('');setResult(null);try{
  const res=await fetch('/api/kpi/payment-forecast',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({asOf,ledger,history,historyFrom,historyTo,basis,inDays,outDays})});
  const body=await res.json();if(!res.ok)throw Error(body.error||'Beräkningen misslyckades');setResult(body);
 }catch(e){setError(e instanceof Error?e.message:'Beräkningen misslyckades')}finally{setBusy(false)}}
 function exportCsv(){if(!result)return;
  const rows:(string|number)[][]=[['Humla – avdelningens betalningsprognos'],['Rapportdatum',result.asOf],['Reskontra',files.ledger],['Utfall',files.history],['Historik från',historyFrom,'till',historyTo],['Metod',result.method],['Vecka','Från','Till','KST','Avdelning','Kända inbetalningar','Prognos inbetalningar','Kända utbetalningar','Prognos utbetalningar','Netto']];
  for(const w of result.weeks){for(const p of [...w.parts,{center:'20+30+40',name:'Totalt',...w.total}])rows.push([`${w.year}-V${w.number}`,w.from,w.to,p.center,p.name,p.incoming.known,p.incoming.forecast??'Underlag saknas',p.outgoing.known,p.outgoing.forecast??'Underlag saknas',p.net??'Underlag saknas'])}
  rows.push([],['Andra / saknade kostnadsställen – ingår inte i totalen'],['Rad-ID','KST','Typ','Datum','Restbelopp']);result.unknown.forEach(r=>rows.push([r.id,r.center,r.kind,r.date,r.amount]));
  rows.push([],['Förfallna poster – ingår inte i framtida veckor'],['Rad-ID','KST','Typ','Datum','Restbelopp']);result.overdue.forEach(r=>rows.push([r.id,r.center,r.kind,r.date,r.amount]));
  rows.push([],['Interna körningar / överföringar – ingår inte i betalningsprognos eller trend'],['Underlag','Rad-ID','KST','Typ','Datum','Belopp']);
  for(const [source,items] of Object.entries(result.internal))items.forEach(r=>rows.push([source==='ledger'?'Reskontra':'Historiskt utfall',r.id,r.center,r.kind,r.date,r.amount]));
  const csv=rows.map(row=>row.map(v=>'"'+String(typeof v==='number'?String(v).replace('.',','):String(v).replace(/^[=+@-]/,"'$&")).replaceAll('"','""')+'"').join(';')).join('\r\n');
  download(`Betalningsprognos_${result.asOf}.csv`,'\uFEFF'+csv);
 }
 return <main className="content" style={{maxWidth:1400,margin:'auto',padding:24}}>
  <Link href="/kpi" prefetch={false}>← Översikt</Link><h1>Betalningsprognos till ekonomi</h1>
  <p>Hela avdelningen: <strong>30 Transport · 20 Sortergården · 40 Verkstad</strong>. Vecka 1 visar vecka 5–8. Fordons- och projektfilter används inte.</p>
  <section className="panel"><h2>1. Underlag</h2><p>Automatisk reskontrakoppling är inte ansluten. Importera en komplett öppen kund- och leverantörsreskontra per rapportdatum. Ange återstående betalning <strong>inklusive moms</strong>. Markera interna överföringar.</p>
   <label>Rapportdatum <input type="date" disabled={busy} value={asOf} onChange={e=>{invalidate();setAsOf(e.target.value)}}/></label>
   <p><label>Öppen reskontra (CSV) <input type="file" disabled={busy} accept=".csv" onChange={e=>void upload(e.target.files?.[0],'ledger')}/></label><br/>{files.ledger&&`${files.ledger} — ${ledger?.length} rader`}</p>
   <p><label>Föregående års och årets utfall (CSV) <input type="file" disabled={busy} accept=".csv" onChange={e=>void upload(e.target.files?.[0],'history')}/></label><br/>{files.history&&`${files.history} — ${history.length} rader`}</p>
   <label>Historikens datum avser <select disabled={busy} value={basis} onChange={e=>{invalidate();setBasis(e.target.value as 'payment'|'booked')}}><option value="payment">Faktisk betalningsdag</option><option value="booked">Bokfört utfall (omräknat inklusive moms)</option></select></label>
   {basis==='booked'&&<p><label>Antagen tid till kundbetalning (dagar) <input type="number" min={0} max={180} value={inDays} disabled={busy} onChange={e=>{invalidate();setInDays(Number(e.target.value))}}/></label> <label>Antagen tid till leverantörsbetalning (dagar) <input type="number" min={0} max={180} value={outDays} disabled={busy} onChange={e=>{invalidate();setOutDays(Number(e.target.value))}}/></label></p>}
   <p><label>Komplett utfallsperiod från <input type="date" disabled={busy} value={historyFrom} onChange={e=>{invalidate();setHistoryFrom(e.target.value)}}/></label> <label> till <input type="date" disabled={busy} value={historyTo} onChange={e=>{invalidate();setHistoryTo(e.target.value)}}/></label></p>
   <details><summary>Format och prognosmetod</summary><p>Semikolonseparerade kolumner: <code>id;kst;typ;datum;belopp;intern</code>. Typ: <code>in/out</code>. Intern: <code>ja/nej</code>. Datum: ÅÅÅÅ-MM-DD. Unikt rad-ID även för delad faktura. Kreditposter med minus.</p><p>Föregående års motsvarande vecka × årets trend för 13 avslutade veckor jämfört med samma period förra året. Veckor matchas 52 veckor bakåt. Reskontra minskar den ännu inte fakturerade prognosen. Komplett historik måste inkludera båda åren och även dagar utan utfall. Saknad trend ger ”Underlag saknas”. Bokfört utfall förskjuts med vald betalningstid; ingen automatisk momsberäkning.</p><button type="button" onClick={()=>download('Betalningsunderlag_mall.csv','\uFEFFid;kst;typ;datum;belopp;intern\r\n')}>Hämta tom CSV-mall</button></details>
   <p>Första versionen sparar inte underlag automatiskt. Exportera rapporten innan du lämnar sidan.</p>
   <button className="primary" disabled={busy||ledger===null} onClick={()=>void calculate()}>{busy?'Beräknar i Hubben…':'2. Beräkna prognos'}</button>
  </section>
  {error&&<p role="alert">{error}</p>}
  {result&&<><section className="panel"><h2>3. Granska och leverera</h2><p>Rapportdatum {result.asOf}. {result.excludedInternal} interna rader uteslutna. {result.unknown.length} poster har annat/saknat kostnadsställe; {result.overdue.length} poster är förfallna. Dessa visas separat i exporten.</p><button className="primary" onClick={exportCsv}>Exportera till ekonomi (Excel-kompatibel CSV)</button><p>Inte en fullständig likviditetsprognos: lön, skatt och lån ingår bara om de finns i underlagen. Förfallodatum är antagen betalningsdag. Ingen banksaldoprognos.</p></section>
   {['total','30','20','40'].map(center=><section className="panel" key={center}><h2>{center==='total'?'Sammanlagt — 30 + 20 + 40':result.weeks[0].parts.find(p=>p.center===center)?.name+' — KST '+center}</h2><div style={{overflowX:'auto'}}><table className="data-table"><thead><tr><th scope="col">Betalningar</th>{result.weeks.map(w=><th scope="col" key={w.from}>V{w.number} / {w.year}<br/><small>{w.from} – {w.to}</small></th>)}</tr></thead><tbody>{[['incoming','known','Kundinbetalningar — kända'],['incoming','forecast','Kundinbetalningar — prognos'],['outgoing','known','Leverantörsutbetalningar — kända'],['outgoing','forecast','Leverantörsutbetalningar — prognos'],['net','','Netto']].map(([kind,field,label])=><tr key={label}><th scope="row">{label}</th>{result.weeks.map(w=>{const p=center==='total'?w.total:w.parts.find(p=>p.center===center)!;const v=kind==='net'?p.net:p[kind as 'incoming'|'outgoing'][field as 'known'|'forecast'];return <td key={w.from}>{money(v)}</td>})}</tr>)}</tbody></table></div></section>)}
   <section className="panel"><h2>Interna körningar — särredovisning</h2><p>Beloppen nedan avser hela respektive importunderlaget, inte bara de fyra prognosveckorna. De ingår inte i prognosen, föregående års bas eller årets trend. Externa kostnader för att utföra interna körningar ska fortfarande finnas med.</p><div style={{overflowX:'auto'}}><table className="data-table"><thead><tr><th scope="col">Underlag</th><th scope="col">KST</th><th scope="col">Intern intäkt</th><th scope="col">Intern kostnad</th></tr></thead><tbody>{Object.entries(result.internal).flatMap(([source,items])=>['30','20','40'].map(center=><tr key={source+center}><th scope="row">{source==='ledger'?'Reskontra':'Historiskt utfall'}</th><td>{center}</td><td>{money(items.filter(r=>r.center===center&&r.kind==='in').reduce((sum,r)=>sum+r.amount,0))}</td><td>{money(items.filter(r=>r.center===center&&r.kind==='out').reduce((sum,r)=>sum+r.amount,0))}</td></tr>))}</tbody></table></div><p>Samtliga interna rader, även utan rätt kostnadsställe, finns i exporten.</p></section>
  </>}
 </main>;
}
