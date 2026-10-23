'use client';
import {useEffect,useState} from 'react';
import {parseMonthPeriod,fiscalMonths,monthLabels} from '@/lib/kpi/period';
type Week={week_start:string;selected_from:string;selected_to:string;week:string;invoiced:number;cost:number;balance:number;cumulative_balance:number;rows:number};
type Balance={status:'ready'|'no_data';invoiced:number|null;cost:number|null;balance:number|null;gauge_position:number|null;latest_date:string|null;weeks:Week[];pending_invoice:{rows:number;amount:number};unknown_party:{rows:number;amount:number};basis:string};
const money=new Intl.NumberFormat('sv-SE',{style:'currency',currency:'SEK',maximumFractionDigits:0});
const signed=(n:number)=>`${n>0?'+':''}${money.format(n)}`;
export function KpiBillingBalance({query}:{query:string}){
 const [loaded,setLoaded]=useState<{query:string;data?:Balance;error?:string}|null>(null);
 const [attempt,setAttempt]=useState(0);
 const current=loaded?.query===query?loaded:null,data=current?.data;
 useEffect(()=>{const controller=new AbortController();let active=true;
  fetch('/api/kpi/billing-balance?'+query,{signal:AbortSignal.any([controller.signal,AbortSignal.timeout(35000)])})
   .then(async r=>{if(!r.ok)throw Error();const value:Balance=await r.json();if(active)setLoaded({query,data:value});})
   .catch(()=>{if(active)setLoaded({query,error:'Faktureringsbalansen kunde inte hämtas.'});});
  return()=>{active=false;controller.abort();};
 },[query,attempt]);
 const tone=data?.balance==null||data.balance===0?'neutral':data.balance>0?'positive':'negative';
 const scale=Math.max(1,...(data?.weeks??[]).map(w=>Math.abs(w.balance)));
 const params=new URLSearchParams(query);
 const selected=parseMonthPeriod(params.get('fiscal_year')??undefined,params.get('months')??undefined,new Date(),params.get('period_mode')??undefined);
 const periodLabel=selected.mode==='ytd'?`YTD till ${selected.to}`:selected.months.map(m=>`${monthLabels[fiscalMonths.indexOf(m)]} ${selected.fiscalYear+(m<9?1:0)}`).join(', ');
 const dateFrom=params.get('date_from'),dateTo=params.get('date_to');
 const scopeLabel=[params.get('cost_center')?`KST ${params.get('cost_center')}`:'Alla kostnadsställen',...['group','unit','vehicle','project'].filter(k=>params.get(k)).map(k=>`${({group:'Grupp',unit:'Enhet',vehicle:'Fordon',project:'Projekt'} as Record<string,string>)[k]}: ${params.get(k)}`)].join(' · ');
 return <section className={`panel billing-balance ${tone}`} aria-labelledby="billing-balance-title" aria-busy={!current}>
  <div className="panel-head"><div><span className="section-kicker">Vald period · externa affärer</span><h2 id="billing-balance-title">Faktureringsbalans</h2></div><span className="balance-badge">{data?.balance==null?'Underlag':data.balance>0?'Faktureringen ligger före':data.balance<0?'Kostnaderna ligger före':'I balans'}</span></div>
  <p className="balance-caption"><strong>{periodLabel}</strong>{dateFrom||dateTo?` · Datumgräns ${dateFrom??'periodstart'} – ${dateTo??'periodslut'}`:''}<br/>{scopeLabel}</p>
  {current?.error?<p role="alert">{current.error} <button className="secondary" onClick={()=>{setLoaded(null);setAttempt(n=>n+1);}}>Försök igen</button></p>:!data?<p role="status">Hämtar faktureringsbalans…</p>:<>
   <strong className="balance-value">{data.balance==null?'Underlag saknas':signed(data.balance)}</strong>
   <div className="balance-scale" role="img" aria-label={data.balance==null?'Balans saknas':`Faktureringsbalans ${signed(data.balance)}. Minus till vänster, plus till höger.`}>
    <div className="balance-track"><span className="balance-zero"/>{data.gauge_position!=null&&<span className="balance-pointer" style={{left:`${data.gauge_position}%`}}/>}</div>
    <div className="balance-labels"><span>− Kostnader före</span><span>0</span><span>Fakturering före +</span></div>
   </div>
   <div className="balance-amounts"><span>Fakturerat <strong>{data.invoiced==null?'—':money.format(data.invoiced)}</strong></span><span>Externa kostnader <strong>{data.cost==null?'—':money.format(data.cost)}</strong></span></div>
   {data.status==='ready'&&<><p className="balance-caption">Veckans plus/minus · håll markören över en stapel för belopp</p><svg className="balance-weeks" viewBox="0 0 640 108" role="img" aria-label="Veckovis fakturerat minus externa kostnader. Gröna staplar över noll är plus, röda under noll är minus.">
    <line x1="0" x2="640" y1="52" y2="52" stroke="#94a3b8"/>
    {data.weeks.map((w,i)=>{const slot=640/data.weeks.length,h=Math.abs(w.balance)/scale*45;return <g key={w.week_start}><title>{`${w.week}: ${signed(w.balance)} · Fakturerat ${money.format(w.invoiced)} · Kostnader ${money.format(w.cost)}`}</title><rect x={i*slot+slot*.15} width={slot*.7} y={w.balance>=0?52-h:52} height={Math.max(h,1)} rx="2" fill={w.balance>0?'#15803d':w.balance<0?'#b91c1c':'#94a3b8'}/>{data.weeks.length<=14&&<text x={i*slot+slot/2} y="107" textAnchor="middle" fontSize="10" fill="#475569">{w.week.split('-')[1]}</text>}</g>;})}
   </svg></>}
   <p className="balance-caption">Exklusive moms och interna överföringar. Fakturering jämförs med bokförda kostnader; detta visar inte betalningsdagar.{data.latest_date?` Senaste datum i beräkningen: ${data.latest_date}.`:''}</p>
   {data.pending_invoice.rows>0&&<p>{money.format(data.pending_invoice.amount)} på {data.pending_invoice.rows} rader saknar faktureringsstatus eller fakturadatum och ingår inte i fakturerat.</p>}
   {data.unknown_party.rows>0&&<p>Balansen är preliminär: {data.unknown_party.rows} rader med totalt {money.format(data.unknown_party.amount)} i absoluta belopp saknar kund/leverantör och ingår inte. Dessa behöver granskas.</p>}
   <details><summary>Visa veckor och underlag</summary><p>{data.basis}</p><div style={{overflowX:'auto'}}><table className="data-table"><thead><tr><th>Vecka</th><th>Fakturerat</th><th>Kostnader</th><th>Veckans balans</th><th>Ackumulerat</th></tr></thead><tbody>{data.weeks.map(w=><tr key={w.week_start}><th scope="row">{w.week}<br/><small>{w.selected_from}–{w.selected_to}</small></th><td>{money.format(w.invoiced)}</td><td>{money.format(w.cost)}</td><td>{signed(w.balance)}</td><td>{signed(w.cumulative_balance)}</td></tr>)}</tbody></table></div></details>
  </>}
  <style jsx>{`
   .billing-balance{border-top:4px solid #eab308}.balance-badge{font-size:.8rem;border-radius:999px;background:#f1f5f9;padding:7px 12px}.positive .balance-badge{background:#dcfce7;color:#166534}.negative .balance-badge{background:#fee2e2;color:#991b1b}.balance-value{display:block;font-size:clamp(1.7rem,4vw,2.8rem);margin:12px 0 24px;font-variant-numeric:tabular-nums}.positive .balance-value{color:#15803d}.negative .balance-value{color:#b91c1c}.balance-track{height:14px;position:relative;border-radius:8px;background:linear-gradient(to right,#fca5a5,#fee2e2 46%,#dcfce7 54%,#86efac)}.balance-zero{position:absolute;left:50%;height:24px;top:-5px;border-left:2px solid #475569}.balance-pointer{position:absolute;top:-7px;width:8px;height:28px;border:2px solid white;border-radius:4px;background:#111827;transform:translateX(-50%);box-shadow:0 1px 4px #0004}.balance-labels{display:flex;justify-content:space-between;margin-top:12px;font-size:.75rem;color:#475569}.balance-amounts{display:flex;flex-wrap:wrap;gap:16px 40px;margin:24px 0 12px}.balance-amounts strong{display:block;margin-top:4px;font-size:1.15rem}.balance-weeks{width:100%;height:110px;display:block}.balance-caption{font-size:.8rem;color:#475569}.billing-balance details{margin-top:16px}.billing-balance summary{cursor:pointer}.billing-balance small{white-space:nowrap}
  `}</style>
 </section>;
}
