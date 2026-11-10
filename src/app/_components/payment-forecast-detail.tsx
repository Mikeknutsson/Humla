'use client';
import {useMemo,useState} from 'react';
import type {AutomaticForecast,ForecastBreakdown,Outcome} from '@/lib/hub/payment-outcome-forecast';
const money=(n:number|null)=>n===null?'Underlag saknas':new Intl.NumberFormat('sv-SE',{style:'currency',currency:'SEK',maximumFractionDigits:2}).format(n);
export type ForecastSelection={from:string;center:string;kind:string;field:string;label:string};
type Tab='baselineRows'|'knownRows'|'trendPreviousRows'|'trendCurrentRows';
const tabs:Record<Tab,string>={baselineRows:'Fjolårets bas',knownRows:'Registrerade poster',trendPreviousRows:'Trend – föregående år',trendCurrentRows:'Trend – i år'};
export function PaymentForecastDetail({forecast,selection,busy,onClose,onSaved}:{forecast:AutomaticForecast;selection:ForecastSelection;busy:boolean;onClose:()=>void;onSaved:()=>Promise<void>}){
 const [tab,setTab]=useState<Tab>(selection.field==='known'?'knownRows':'baselineRows');
 const [page,setPage]=useState(0);
 const [checked,setChecked]=useState<string[]>([]),[saving,setSaving]=useState(false),[error,setError]=useState('');
 const [note,setNote]=useState('Engångskostnad – ska inte antas återkomma');
 const internal=selection.kind==='internal';
 const entries=useMemo(()=>forecast.automatic.breakdown.filter(d=>d.weekFrom===selection.from&&(selection.center==='total'||d.center===selection.center)&&d.internal===internal&&(selection.kind==='net'||d.kind===((internal?selection.field:selection.kind)==='incoming'?'in':'out'))),[forecast,selection.from,selection.center,selection.kind,selection.field,internal]);
 const week=forecast.weeks.find(w=>w.from===selection.from)!;
 const audit=useMemo(()=>new Map(forecast.automatic.auditRows.map(r=>[r.id,r])),[forecast]);
 const rows=useMemo(()=>entries.flatMap(d=>d[tab].flatMap(id=>{const r=audit.get(id);return r?[r]:[];})).sort((a,b)=>a.date.localeCompare(b.date)||a.party.localeCompare(b.party)||Number(b.amount)-Number(a.amount)),[entries,tab,audit]);
 const pageSize=100,pageCount=Math.max(1,Math.ceil(rows.length/pageSize));
 const currentPage=Math.min(page,pageCount-1),visibleRows=rows.slice(currentPage*pageSize,(currentPage+1)*pageSize);
 const selectable=Array.from(new Set(visibleRows.flatMap(r=>r.kind==='out'&&r.rowId?[r.rowId]:[])));
 const locked=busy||saving;
 async function save(excluded:boolean){
  setSaving(true);setError('');try{
   const res=await fetch('/api/kpi/payment-forecast',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({action:'set-one-off',rowIds:checked,excluded,note})});
   const body=await res.json();if(!res.ok)throw Error(body.error||'Kunde inte spara');setChecked([]);await onSaved();
  }catch(e){setError(e instanceof Error?e.message:'Kunde inte spara')}finally{setSaving(false)}
 }
 function rowKey(r:Outcome,i:number){return (r.id??r.party+r.date)+':'+i;}
 return <section className="panel" aria-label="Siffrorna bakom prognosen" tabIndex={-1} ref={el=>{if(el&&!el.dataset.focused){el.dataset.focused='true';el.focus();el.scrollIntoView({behavior:'smooth',block:'start'});}}}>
  <button type="button" onClick={onClose}>Stäng detaljer</button>
  <h2>{selection.label} · V{week.number} / {week.year} · {selection.center==='total'?'Sammanlagt':`KST ${selection.center}`}</h2>
  <p>Beloppen är exklusive moms. Registrerat + återstående prognos = total prognos. Registrerade belopp ingår alltså redan i totalen.</p>
  {selection.kind==='payroll'?<><p>Löner ligger utanför kostnader och netto.</p>{forecast.automatic.payroll?.details.filter(d=>d.payDate>=week.from&&d.payDate<=week.to&&(selection.center==='total'||d.center===selection.center)).map(d=><p key={d.center+d.payDate}>KST {d.center}: {money(d.amount)} · arbetsmånad {d.workMonth} · utbetalning {d.payDate} · metod {d.method}</p>)}</>:<>
  <div style={{overflowX:'auto'}}><table className="data-table"><thead><tr><th>KST / typ</th><th>Historisk bas</th><th>Trend fg. år</th><th>Trend i år</th><th>Förändring</th><th>Registrerat</th><th>Återstående prognos</th><th>Total</th></tr></thead><tbody>{entries.map((d:ForecastBreakdown)=><tr key={d.center+d.kind+d.scope}><th>{d.center} {d.kind==='in'?'In':'Ut'} · {d.scope==='stena'?'Stena':'Ordinarie'}</th><td>{money(d.baseline)}<br/><small>{d.method==='stena_month'?'Leveransmånad':'13 veckors snitt'} · {d.baselineFrom}–{d.baselineTo}</small></td><td>{money(d.trendPrevious)}</td><td>{money(d.trendCurrent)}</td><td>{d.trendStatus==='historical_only'?'Utan tillväxtpåslag':d.factor===null?'Underlag saknas':`${((d.factor-1)*100).toFixed(2)} %`}<br/><small>{d.reviewedTrendMonths.length} avstämda månadspar</small></td><td>{money(d.known)}</td><td>{money(d.forecast)}</td><td>{money(d.total)}</td></tr>)}</tbody></table></div>
  <p>Trendperiod {forecast.automatic.trendFrom}–{forecast.automatic.trendTo}, jämförd med samma datum föregående år. Ordinarie bas är genomsnittet av 13 historiska veckor. Stena använder en egen leveransmånad. Återstående prognos = max(0, respektive bas × trendfaktor − registrerat); en avstämd Stena-månad har ingen återstående reserv. Engångskostnader används inte i bas eller trend.</p>
  {entries.some(d=>d.spike)&&<p role="note"><strong>Kontrollera kostnadstoppen:</strong> en leverantör står för minst hälften av basens kostnader och basen är minst 50 000 kr. Bedöm om kostnaden ska återkomma i år.</p>}
  {entries.some(d=>d.excludedBaseline!==0)&&<p>Markerade engångskostnader i jämförelseveckan: {money(entries.reduce((s,d)=>s+d.excludedBaseline,0))}. Dessa ligger kvar i historiskt resultat.</p>}
  <div role="group" aria-label="Välj underlag" style={{display:'flex',gap:8,flexWrap:'wrap'}}>{Object.entries(tabs).map(([key,label])=><button key={key} aria-pressed={tab===key} onClick={()=>{setTab(key as Tab);setPage(0);setChecked([]);}}>{label}</button>)}</div>
  <h3>{tabs[tab]}</h3>
  {selectable.length>0&&<><p><label><input type="checkbox" disabled={locked||selectable.length>200} checked={selectable.length>0&&selectable.every(id=>checked.includes(id))} onChange={e=>setChecked(e.target.checked?selectable:[])}/> Välj kostnadsrader på denna sida ({selectable.length})</label> · {checked.length} valda</p><label>Anteckning <input value={note} maxLength={500} disabled={locked} onChange={e=>setNote(e.target.value)}/></label><p><button disabled={locked||!checked.length||checked.length>200} onClick={()=>void save(true)}>Engångskostnad – använd inte i prognosen</button>{' '}<button disabled={locked||!checked.length||checked.length>200} onClick={()=>void save(false)}>Ångra engångsmarkering</button></p><p>Markeringen gäller valda kostnadsrader, även efter ny import. Den påverkar inte historiskt resultat eller redan registrerade betalningar. Högst 200 rader kan ändras samtidigt.</p></>}
  {error&&<p role="alert">{error}</p>}{saving&&<p role="status">Sparar och räknar om prognosen…</p>}
  <div style={{overflowX:'auto',maxHeight:600}}><table className="data-table"><thead><tr><th>Välj</th><th>KST</th><th>Bokfört / levererat</th><th>Beräknad betalning</th><th>Kund / leverantör</th><th>Order / faktura</th><th>Projekt</th><th>Konto</th><th>Belopp</th><th>Beloppsgrund</th><th>Användning</th></tr></thead><tbody>{visibleRows.map((r,i)=><tr key={rowKey(r,i)}><td>{r.kind==='out'&&r.rowId&&<input type="checkbox" aria-label={`Välj ${r.reference||r.party} ${r.date}`} disabled={locked} checked={checked.includes(r.rowId)} onChange={e=>setChecked(ids=>e.target.checked?Array.from(new Set([...ids,r.rowId!])):ids.filter(id=>id!==r.rowId))}/>}</td><td>{r.center}</td><td>{r.date}</td><td>{r.paymentDate??'—'}</td><td>{r.party||'Saknas'}</td><td>{r.reference||r.description||'—'}</td><td>{r.project||'—'}</td><td>{r.account||'—'}</td><td>{money(Number(r.amount))}</td><td>{r.amountStatus==='settled'?'Stena – avräknat':r.amountStatus==='history'?'Stena – historik, beräknat':r.source??'Registrerat'}</td><td>{r.oneOff?(tab==='knownRows'?'Engångskostnad – registrerad betalning kvarstår':'Engångskostnad – utesluten ur beräkningen'):'Ingår'}</td></tr>)}</tbody></table></div>
  {pageCount>1&&<nav aria-label="Sidor med prognosunderlag"><button disabled={currentPage===0} onClick={()=>{setPage(currentPage-1);setChecked([]);}}>Föregående</button>{' '}Sida {currentPage+1} av {pageCount} · {rows.length} rader totalt{' '}<button disabled={currentPage+1>=pageCount} onClick={()=>{setPage(currentPage+1);setChecked([]);}}>Nästa</button></nav>}
  {!rows.length&&<p>Inga registrerade rader i detta urval.</p>}
  <p>Källbelopp i hela urvalet, alla sidor (13 veckors bas divideras med 13): {money(rows.reduce((s,r)=>s+Number(r.amount),0))}. {tab==='knownRows'?'Alla registrerade poster räknas med.':`Efter engångsmarkeringar: ${money(rows.filter(r=>!r.oneOff).reduce((s,r)=>s+Number(r.amount),0))}.`}</p>
  </>}
 </section>;
}
