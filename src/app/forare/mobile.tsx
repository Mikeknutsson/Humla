'use client';
import {useCallback,useEffect,useState} from 'react';
import {Truck,MapPin,Phone,RefreshCw,LogOut,ChevronLeft,Play,Pause,CheckCircle2} from 'lucide-react';
import {logout} from './login/actions';
type ReportItem={articleId:string;siteId:string|null;quantity:number;label?:string;unit?:string;siteLabel?:string|null;comment?:string};
type ArticleDraft=Omit<ReportItem,'quantity'>&{quantity:string};
type CatalogArticle={id:string;label:string;unit:string;siteKind:string;sites:{id:string;label:string}[]};
type Report={items?:ReportItem[];hours?:number;loads?:number;tonnes?:number;note?:string};
type Order={id:string;number:string;version:number;title:string;status:string;execution:string|null;start:string;end:string;customer:string;project:string;location:string;instruction:string;vehicle:string;contactName:string;contactPhone:string;submittedAt?:string|null;report:Report|null;lines:{id:string;label:string;quantity:number;unit:string}[]};
const demoCatalog:CatalogArticle[]=[
 {id:'transport',label:'Lastbil med släp',unit:'tim',siteKind:'none',sites:[]},
 {id:'material',label:'Bergkross 0–32',unit:'ton',siteKind:'pickup',sites:[{id:'demo-quarry',label:'Demotäkt'}]},
 {id:'returtra',label:'Tippavgift Returträ',unit:'ton',siteKind:'delivery',
  sites:['Stena Karlshamn','Stena Kristianstad','Elleholms Pukavik','Ragn-Sells Kallinge'].map((label,i)=>({id:'demo-tip-'+i,label}))},
];
const today=()=>new Intl.DateTimeFormat('sv-SE',{timeZone:'Europe/Stockholm',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
export default function Mobile({demo=false}:{demo?:boolean}){const [orders,setOrders]=useState<Order[]>([]),[error,setError]=useState(''),[loading,setLoading]=useState(true),[selected,setSelected]=useState(''),[filter,setFilter]=useState('active');
 const [catalog,setCatalog]=useState<CatalogArticle[]>([]);
 const reload=useCallback(async()=>{if(demo){setOrders(previous=>previous.length?previous:[demoOrder()]);setLoading(false);return;}setLoading(true);setError('');try{const r=await fetch('/api/forare',{cache:'no-store',signal:AbortSignal.timeout(20000)});const j=await r.json();if(!r.ok)throw Error(j.error);setOrders(j.orders);setCatalog(j.catalog||[]);}catch(e){setError(e instanceof Error?e.message:'Kunde inte hämta uppdrag.');}finally{setLoading(false);}},[demo]);
 useEffect(()=>{void reload();},[reload]);const order=orders.find(o=>o.id===selected);const current=orders.filter(o=>filter==='done'?!!o.submittedAt:filter==='report'?o.status==='Utförd'&&!o.submittedAt:filter==='today'?o.start.slice(0,10)<=today()&&o.end.slice(0,10)>=today():['Planerad','Pågående'].includes(o.status)&&!o.submittedAt);
 return <main><header><strong>HUMLA <span>CHAUFFÖR</span></strong>{demo?<button onClick={()=>{setOrders([demoOrder()]);setSelected('');setFilter('active');}}>Börja om</button>:<form action={logout}><button aria-label="Logga ut"><LogOut size={20}/></button></form>}</header><div className="driver-development">{demo?'TESTORDER · Simulering, inget sparas i Humla':'UNDER UTVECKLING · Ingen fakturering'}</div>{error&&<p className="driver-error" role="alert">{error}</p>}{order?<><button className="driver-back" onClick={()=>setSelected('')}><ChevronLeft size={18}/>Mina uppdrag</button><Details key={order.id} order={order} catalog={demo?demoCatalog:catalog} reload={reload} simulate={demo?(action,report)=>setOrders(items=>items.map(item=>item.id!==order.id?item:{...item,version:item.version+1,submittedAt:action==='submit'?new Date().toISOString():item.submittedAt,status:action==='submit'?'Rapporterad':action==='complete'?'Utförd':action==='start'?'Pågående':item.status,execution:action==='pause'?'paused':action==='complete'?'finished':action==='start'||action==='resume'?'running':item.execution,report:['complete','report','submit'].includes(action)?report:item.report})):undefined}/></>:<><div className="driver-heading"><div><p className="driver-kicker">ELLEHOLMS MASKIN AB</p><h1>Mina uppdrag</h1><p>{today()} · Bara uppdrag tilldelade dig</p></div><button aria-label="Uppdatera uppdrag" disabled={loading} onClick={()=>void reload()}><RefreshCw size={22}/></button></div><nav aria-label="Visa uppdrag">{[['active','Uppdrag'],['report','Att rapportera'],['done','Inskickade']].map(([v,l])=><button key={v} aria-pressed={filter===v} onClick={()=>setFilter(v)}>{l}</button>)}</nav>{loading&&<p role="status">Hämtar uppdrag…</p>}{!loading&&!error&&!current.length&&<section className="driver-card"><Truck size={34}/><h2>Inga uppdrag här ännu</h2><p>Tilldelade order från Transportappen visas här. Testportalens order ingår inte.</p></section>}{current.map(o=><button key={o.id} className="driver-order" onClick={()=>setSelected(o.id)}><div className={'driver-status '+(o.submittedAt?'done':o.status==='Utförd'?'to-report':o.status==='Pågående'?'running':'')}><b>{o.number}</b><span>{o.execution==='paused'?'Pausad':o.status}</span></div><div><p className="driver-time">{o.start.replace('T',' ')} – {o.end.slice(11,16)}</p><h2>{o.title}</h2><p>{o.customer}</p><p><Truck size={18}/>{o.vehicle||'Fordon ej angivet'}</p>{o.location&&<p><MapPin size={18}/>{o.location}</p>}<strong>Öppna uppdrag →</strong></div></button>)}</>}<footer>Humla Chaufför · Utvecklingsversion<br/>Internet krävs för att läsa och spara. Rapportering ändrar inte priser eller fakturaunderlag automatiskt.</footer></main>;
}
function Details({order:o,catalog,reload,simulate}:{order:Order;catalog:CatalogArticle[];reload:()=>Promise<void>;simulate?:(action:string,report:Report)=>void}){
 const [busy,setBusy]=useState(false),[error,setError]=useState(''),[ok,setOk]=useState(''),[note,setNote]=useState(o.report?.note||'');
 const [items,setItems]=useState<ReportItem[]>(o.report?.items||[]);
 const [editor,setEditor]=useState<{index:number;draft:ArticleDraft}|null>(null);
 function patchItem(patch:Partial<ArticleDraft>){
  setEditor(current=>current?{...current,draft:{...current.draft,...patch}}:null);
 }

 const [attempt,setAttempt]=useState<{signature:string;id:string}|null>(null);
 const [savedVersion,setSavedVersion]=useState(o.version);
 const version=simulate?o.version:savedVersion;
 const active=!o.submittedAt&&['Planerad','Pågående','Utförd'].includes(o.status);
 async function command(action:string,reportItems=items){
  setBusy(true);setError('');setOk('');
  const data=['report','complete','submit'].includes(action)?{items:reportItems.map(({articleId,siteId,quantity,comment})=>({articleId,siteId,quantity,comment})),note}:{};
  const signature=JSON.stringify({action,data,version});
  const requestId=attempt?.signature===signature?attempt.id:crypto.randomUUID();
  setAttempt({signature,id:requestId});
  try{
   if(simulate){
    simulate(action,{items:reportItems,note});
    setOk('Teståtgärden är klar. Inget har sparats i Humla.');
   }else{
    const response=await fetch('/api/forare',{method:'POST',signal:AbortSignal.timeout(20000),headers:{'Content-Type':'application/json'},body:JSON.stringify({id:o.id,version,requestId,action,data})});
    const result=await response.json();
    if(!response.ok)throw Error(result.error);
    setSavedVersion(result.version);
    setOk(action==='submit'?'Skickad till transportledningen. Ordern är nu låst.':'Sparat i Humla.');
    await reload();
   }
   return true;
  }catch(e){
   setError(e instanceof Error?e.message:'Kunde inte spara. Uppgifterna finns kvar i formuläret. Försök igen.');
   return false;
  }finally{setBusy(false);}
 }
 async function saveArticle(){
  if(!editor||busy)return;
  const {index,draft}=editor;
  const article=catalog.find(entry=>entry.id===draft.articleId);
  if(!article)return;
  if(items.some((item,i)=>i!==index&&item.articleId===draft.articleId&&item.siteId===draft.siteId)){
   setError('Samla mängden på en rad per artikel och plats.');
   return;
  }
  const line={...draft,quantity:Number(draft.quantity),comment:draft.comment?.trim(),label:article.label,unit:article.unit,
   siteLabel:article.sites.find(site=>site.id===draft.siteId)?.label};
  const next=index===items.length?[...items,line]:items.map((item,i)=>i===index?line:item);
  if(await command('report',next)){setItems(next);setEditor(null);}
 }
 async function removeArticle(index:number){
  const next=items.filter((_,i)=>i!==index);
  if(await command('report',next)){setItems(next);setEditor(null);}
 }
 const article=catalog.find(entry=>entry.id===editor?.draft.articleId);
 const whole=article?.unit==='st'||article?.unit==='lass';
 return <section className="driver-card"><p className="driver-kicker">{o.number} · {o.execution==='paused'?'Pausad':o.status}</p><ol className="driver-progress" aria-label="Orderstatus">{['Planerad','Pågående','Utförd','Rapporterad'].map((step,i)=><li key={step} className={(o.submittedAt?3:['Planerad','Pågående','Utförd'].indexOf(o.status))>=i?'reached':''}>{step==='Utförd'?'Att rapportera':step}</li>)}</ol>{o.submittedAt&&<div className="driver-locked" role="status"><strong>Rapporterad · Låst för ändringar</strong><p>Skickad till transportledningen {new Date(o.submittedAt).toLocaleString('sv-SE',{timeZone:'Europe/Stockholm'})}. Kontakta transportledningen om något behöver rättas.</p></div>}<h1>{o.title}</h1><p>{o.customer}{o.project?' · '+o.project:''}</p><p><Truck size={18}/> {o.vehicle||'Fordon ej angivet'}</p><p>{o.start.replace('T',' ')}<br/>till {o.end.replace('T',' ')} · svensk tid</p><h2>Instruktioner</h2><p className="driver-instruction">{o.instruction||'Inga instruktioner angivna.'}</p>{o.location&&<><h2>Plats</h2><p>{o.location}</p><a className="driver-link" href={'https://www.google.com/maps/search/?api=1&query='+encodeURIComponent(o.location)} target="_blank" rel="noreferrer"><MapPin size={20}/>Öppna i kartor</a></>}{o.contactPhone&&<a className="driver-link" href={'tel:'+o.contactPhone.replace(/[^+\d]/g,'')}><Phone size={20}/>{o.contactName||'Ring kontakt'} · {o.contactPhone}</a>}<h2>Planerade artiklar</h2>{o.lines.length?o.lines.map((l,i)=><p className="driver-line" key={l.id||i}><strong>{l.label}</strong><span>{l.quantity} {l.unit}</span></p>):<p>Inga artiklar angivna.</p>}
 {active&&o.status!=='Utförd'&&<div className="driver-controls">{o.status==='Planerad'?<button className="driver-primary" disabled={busy} onClick={()=>void command('start')}><Play size={20}/>Starta uppdrag</button>:<button disabled={busy} onClick={()=>void command(o.execution==='paused'?'resume':'pause')}><Pause size={20}/>{o.execution==='paused'?'Fortsätt uppdrag':'Pausa uppdrag'}</button>}</div>}
 <h2>Återrapportering</h2>
 {o.report&&(o.report.hours!=null||o.report.loads!=null||o.report.tonnes!=null)&&
  <p>Äldre rapport: {[o.report.hours!=null&&o.report.hours+' tim',o.report.loads!=null&&o.report.loads+' lass',o.report.tonnes!=null&&o.report.tonnes+' ton'].filter(Boolean).join(' · ')}</p>}
 {(active?items:o.report?.items||[]).map((item,index)=><div key={item.articleId+':'+item.siteId} className="driver-saved-item">
  <div className="driver-saved-heading"><strong>{item.label}</strong><b>{item.quantity} {item.unit}</b></div>
  {item.siteLabel&&<div>{item.siteLabel}</div>}
  {item.comment&&<div className="driver-item-comment">{item.comment}</div>}
  {active&&<button type="button" disabled={busy||!!editor} onClick={()=>{setError('');setEditor({index,draft:{...item,quantity:String(item.quantity)}});}}>Redigera</button>}
 </div>)}
 {active&&editor&&<form className="driver-report-item" onSubmit={e=>{e.preventDefault();void saveArticle();}}><fieldset disabled={busy}>
  <label>Artikel<select required value={article?.id||''} onChange={e=>patchItem({articleId:e.target.value,siteId:null,quantity:''})}>
   <option value="">Välj artikel</option>
   {catalog.map(entry=><option key={entry.id} value={entry.id}>{entry.label}</option>)}
  </select></label>
  {article&&article.siteKind!=='none'&&<label>{article.siteKind==='pickup'?'Täkt / hämtplats':'Tippplats / mottagare'}
   <select required value={article.sites.some(site=>site.id===editor.draft.siteId)?editor.draft.siteId||'':''} onChange={e=>patchItem({siteId:e.target.value||null})}>
    <option value="">Välj plats</option>{article.sites.map(site=><option key={site.id} value={site.id}>{site.label}</option>)}
   </select>
  </label>}
  {article&&<label>Mängd ({article.unit})<input type="number" min={whole?1:.0001} max="100000" step={whole?'1':'.0001'}
   inputMode={whole?'numeric':'decimal'} value={editor.draft.quantity} required onChange={e=>patchItem({quantity:e.target.value})}/></label>}
  <label>Artikelkommentar (valfri)<textarea rows={2} maxLength={500} value={editor.draft.comment||''} onChange={e=>patchItem({comment:e.target.value})}/></label>
  <div className="driver-item-actions">
   <button type="submit" className="driver-primary">Spara</button>
   <button type="button" onClick={()=>{setEditor(null);setError('');}}>Avbryt</button>
   {editor.index<items.length&&<button type="button" onClick={()=>void removeArticle(editor.index)}>Ta bort</button>}
  </div>
 </fieldset></form>}
 {active&&!editor&&<button type="button" disabled={busy||!catalog.length||items.length>=30} onClick={()=>{setError('');setEditor({index:items.length,draft:{articleId:'',siteId:null,quantity:''}});}}>+ Lägg till artikel</button>}
 {active&&!catalog.length&&<p>Transportledningen behöver aktivera artiklar för återrapportering.</p>}
 <form onSubmit={e=>{e.preventDefault();void command('report');}}><fieldset disabled={busy||!active||!!editor}>
  <label>Kommentar / avvikelse för hela ordern<textarea rows={3} maxLength={4000} value={note} onChange={e=>setNote(e.target.value)}/></label>
  {active&&<button className="driver-primary">Spara utkast</button>}
  {o.status==='Pågående'&&<button type="button" onClick={()=>{if(window.confirm('Markera arbetet som utfört? Du kan komplettera innan du skickar rapporten.'))void command('complete');}}><CheckCircle2 size={20}/>Arbetet utfört – gå till rapportering</button>}
  {active&&o.status==='Utförd'&&<button className="driver-submit" type="button" onClick={()=>{if(window.confirm('Skicka till transportledningen? Ordern blir Rapporterad och du kan inte längre ändra uppgifterna.'))void command('submit');}}><CheckCircle2 size={20}/>Rapporterad – skicka till transportledningen</button>}
 </fieldset></form>{error&&<p className="driver-error" role="alert">{error}</p>}{ok&&<p role="status">{ok}</p>}<button disabled={busy} onClick={()=>{if(window.confirm('Hämta senaste orderversion? Osparade ändringar försvinner.'))window.location.reload();}}>Uppdatera uppdraget</button></section>;
}

function demoOrder():Order{return {id:'demo-order',number:'TEST-001',version:1,title:'Leverans av bergkross 0–32',status:'Planerad',execution:null,start:today()+'T07:00',end:today()+'T11:00',customer:'Exempelkund AB · fiktiv',project:'Testprojekt – markarbete',location:'Pukavik, Sölvesborg',instruction:'TESTUPPDRAG – ska inte utföras.\nHämta två lass bergkross 0–32. Kontrollera leveransplatsen med arbetsledaren före lossning. Väg varje lass och ange total levererad mängd efter avslutad körning.',vehicle:'DEMO – lastbil med släp',contactName:'',contactPhone:'',report:null,lines:[{id:'transport',label:'Lastbil med släp',quantity:4,unit:'Tim'},{id:'material',label:'Bergkross 0–32',quantity:60,unit:'ton'}]};}
