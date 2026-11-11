"use client";
import {useEffect,useMemo,useState} from "react";
import {ClipboardList,Plus,Search,SlidersHorizontal,Truck,CalendarDays,ChevronRight,Save,X,Trash2,LayoutDashboard,ArrowUpDown,Download,RefreshCw} from "lucide-react";
import "./orderportal.css";

type Status="Utkast"|"Planerad"|"Pågående"|"Utförd"|"Faktureringsklar"|"Fakturerad"|"Avbruten";
type Order={id:string;number:string;customer:string;project:string;description:string;date:string;status:Status;vehicle:string;driver:string;amount:number;notes:string;createdAt:string;updatedAt:string};
const STATUSES:Status[]=["Utkast","Planerad","Pågående","Utförd","Faktureringsklar","Fakturerad","Avbruten"];
const STORE="humla-orderportal-local-v1";
const blank=():Order=>({id:"",number:"",customer:"",project:"",description:"",date:new Date().toISOString().slice(0,10),status:"Utkast",vehicle:"",driver:"",amount:0,notes:"",createdAt:"",updatedAt:""});
const money=(v:number)=>new Intl.NumberFormat("sv-SE",{style:"currency",currency:"SEK",maximumFractionDigits:0}).format(v);
const dateText=(s:string)=>s?new Intl.DateTimeFormat("sv-SE").format(new Date(s+"T12:00:00")):"—";
const csvCell=(v:string|number)=>'"'+String(v).replace(/"/g,'""')+'"';
export default function OrderportalPage(){
  const [orders,setOrders]=useState<Order[]>([]);
  const [ready,setReady]=useState(false);
  const [query,setQuery]=useState("");
  const [status,setStatus]=useState("Alla statusar");
  const [from,setFrom]=useState("");
  const [to,setTo]=useState("");
  const [sort,setSort]=useState<"desc"|"asc">("desc");
  const [editor,setEditor]=useState<Order|null>(null);
  const [editingId,setEditingId]=useState<string|null>(null);
  const [error,setError]=useState("");
  const [tab,setTab]=useState<"orders"|"overview">("orders");
  useEffect(()=>{try{const stored=localStorage.getItem(STORE);if(stored){const parsed=JSON.parse(stored);if(Array.isArray(parsed))setOrders(parsed)}}catch{}setReady(true)},[]);
  useEffect(()=>{if(ready)localStorage.setItem(STORE,JSON.stringify(orders))},[orders,ready]);
  const filtered=useMemo(()=>orders.filter(o=>(status==="Alla statusar"||o.status===status)&&(!from||o.date>=from)&&(!to||o.date<=to)&&(!query||[o.number,o.customer,o.project,o.description,o.vehicle,o.driver].join(" ").toLocaleLowerCase("sv-SE").includes(query.toLocaleLowerCase("sv-SE")))).sort((a,b)=>sort==="desc"?b.number.localeCompare(a.number,"sv-SE",{numeric:true}):a.number.localeCompare(b.number,"sv-SE",{numeric:true})),[orders,query,status,from,to,sort]);
  const counts=useMemo(()=>({total:orders.length,active:orders.filter(o=>["Planerad","Pågående"].includes(o.status)).length,ready:orders.filter(o=>o.status==="Faktureringsklar").length,value:orders.filter(o=>o.status!=="Avbruten").reduce((sum,o)=>sum+(Number(o.amount)||0),0)}),[orders]);
  const start=()=>{setError("");setEditingId(null);setEditor({...blank(),number:String(Math.max(10000,...orders.map(o=>Number(o.number)||0))+1)})};
  const edit=(o:Order)=>{setError("");setEditingId(o.id);setEditor({...o})};
  const save=()=>{if(!editor)return;if(!editor.customer.trim()||!editor.number.trim()||!editor.date){setError("Ordernummer, kund och datum måste anges.");return}if(orders.some(o=>o.number.trim()===editor.number.trim()&&o.id!==editingId)){setError("Ordernumret finns redan.");return}const now=new Date().toISOString();const item:Order={...editor,id:editingId||crypto.randomUUID(),amount:Math.max(0,Number(editor.amount)||0),customer:editor.customer.trim(),number:editor.number.trim(),createdAt:editor.createdAt||now,updatedAt:now};setOrders(prev=>editingId?prev.map(o=>o.id===editingId?item:o):[item,...prev]);setEditor(null)};
  const remove=()=>{if(!editingId)return;if(window.confirm("Ta bort detta lokala orderutkast?")){setOrders(prev=>prev.filter(o=>o.id!==editingId));setEditor(null)}};
  const exportCsv=()=>{const rows=[["Ordernummer","Datum","Kund","Projekt","Beskrivning","Status","Fordon","Chaufför","Belopp SEK","Notering"],...filtered.map(o=>[o.number,o.date,o.customer,o.project,o.description,o.status,o.vehicle,o.driver,o.amount,o.notes])];const csv="\uFEFF"+rows.map(row=>row.map(csvCell).join(";")).join("\r\n");const blob=new Blob([csv],{type:"text/csv;charset=utf-8;"});const url=URL.createObjectURL(blob);const a=document.createElement("a");a.href=url;a.download="humla-orderportal.csv";a.click();URL.revokeObjectURL(url)};
  const field=(name:keyof Order,value:string|number)=>setEditor(p=>p?{...p,[name]:value}:p);
  return <div className="op-app">
    <aside className="op-side">
      <div className="op-brand"><div className="op-brandmark">H</div><div><strong>HUMLA</strong><small>ORDERPORTAL</small></div></div>
      <div className="op-navtitle">ARBETSPLATS</div>
      <button className={tab==="overview"?"op-nav active":"op-nav"} onClick={()=>setTab("overview")}><LayoutDashboard size={18}/>Översikt</button>
      <button className={tab==="orders"?"op-nav active":"op-nav"} onClick={()=>setTab("orders")}><ClipboardList size={18}/>Orderhantering</button>
      <div className="op-sidefooter"><span className="op-localdot"/> Lokal arbetsversion <small>Separat från Humlas KPI-dashboard</small></div>
    </aside>
    <main className="op-main">
      <div className="op-top"><span>Transportledning <ChevronRight size={14}/> {tab==="orders"?"Orderhantering":"Översikt"}</span><span className="op-topright">HUMLA / ORDERPORTAL</span></div>
      <header className="op-head"><div><div className="op-eyebrow">SEPARAT DASHBOARD</div><h1>{tab==="orders"?"Orderhantering":"Orderöversikt"}</h1><p>Arbeta med order, planering och faktureringsunderlag i ett eget gränssnitt.</p></div><button className="op-primary" onClick={start}><Plus size={18}/> Ny order</button></header>
      <div className="op-note"><strong>Arbetsversion:</strong> Order du skapar sparas endast i den här webbläsaren. Ingen koppling till Workify, Fortnox eller Humla Hub har aktiverats.</div>
      <section className="op-stats">
        <div className="op-stat"><span>Totalt antal order</span><b>{counts.total}</b><small>Lokalt registrerade</small></div>
        <div className="op-stat"><span>Planerade / pågående</span><b>{counts.active}</b><small>Aktiva uppdrag</small></div>
        <div className="op-stat"><span>Faktureringsklara</span><b>{counts.ready}</b><small>Väntar på hantering</small></div>
        <div className="op-stat"><span>Ordervärde</span><b>{money(counts.value)}</b><small>Exklusive avbrutna order</small></div>
      </section>
      {tab==="overview"?<section className="op-panel"><div className="op-panelhead"><h2>Snabböversikt</h2><button className="op-link" onClick={()=>setTab("orders")}>Visa alla order <ChevronRight size={15}/></button></div><div className="op-statusgrid">{STATUSES.map(s=><button key={s} onClick={()=>{setStatus(s);setTab("orders")}}><span>{s}</span><strong>{orders.filter(o=>o.status===s).length}</strong></button>)}</div></section>:
      <section className="op-panel">
        <div className="op-panelhead"><div><h2>Orderlista</h2><p>{filtered.length} av {orders.length} order</p></div><div className="op-actions"><button onClick={exportCsv} className="op-secondary"><Download size={15}/> Exportera CSV</button><button onClick={()=>{setQuery("");setStatus("Alla statusar");setFrom("");setTo("")}} className="op-secondary"><RefreshCw size={15}/> Rensa filter</button></div></div>
        <div className="op-filters"><label className="op-search"><Search size={17}/><input aria-label="Sök order" value={query} onChange={e=>setQuery(e.target.value)} placeholder="Sök ordernummer, kund, projekt, fordon..."/></label><label className="op-select"><SlidersHorizontal size={16}/><select aria-label="Filtrera status" value={status} onChange={e=>setStatus(e.target.value)}><option>Alla statusar</option>{STATUSES.map(s=><option key={s}>{s}</option>)}</select></label><label className="op-date"><CalendarDays size={15}/><input aria-label="Från datum" type="date" value={from} onChange={e=>setFrom(e.target.value)}/></label><label className="op-date"><span>till</span><input aria-label="Till datum" type="date" value={to} onChange={e=>setTo(e.target.value)}/></label></div>
        <div className="op-tablewrap"><table><thead><tr><th><button onClick={()=>setSort(v=>v==="desc"?"asc":"desc")}>Ordernr <ArrowUpDown size={13}/></button></th><th>Datum</th><th>Kund / Projekt</th><th>Uppdrag</th><th>Resurs</th><th>Status</th><th className="op-right">Belopp</th><th></th></tr></thead><tbody>{filtered.map(o=><tr key={o.id} onClick={()=>edit(o)} tabIndex={0} onKeyDown={e=>{if(e.key==="Enter")edit(o)}}><td><strong>#{o.number}</strong></td><td>{dateText(o.date)}</td><td><strong>{o.customer}</strong><small>{o.project||"—"}</small></td><td>{o.description||"—"}</td><td><span className="op-resource"><Truck size={14}/>{o.vehicle||"Ej tilldelad"}</span><small>{o.driver}</small></td><td><span className={"op-status op-status-"+STATUSES.indexOf(o.status)}>{o.status}</span></td><td className="op-right">{money(o.amount)}</td><td><ChevronRight size={17}/></td></tr>)}</tbody></table>{!filtered.length&&<div className="op-empty"><ClipboardList size={31}/><h3>{orders.length?"Inga order matchar filtreringen":"Inga order registrerade"}</h3><p>{orders.length?"Ändra filtreringen för att se fler order.":"Skapa din första order. Ingen exempeldata visas som riktiga affärsuppgifter."}</p><button className="op-primary" onClick={start}><Plus size={16}/> Skapa order</button></div>}</div>
      </section>}
    </main>
    {editor&&<div className="op-overlay" onMouseDown={e=>{if(e.target===e.currentTarget)setEditor(null)}}><div role="dialog" aria-modal="true" aria-label={editingId?"Redigera order":"Ny order"} className="op-editor"><div className="op-editorhead"><div><span className="op-eyebrow">ORDERDETALJER</span><h2>{editingId?"Redigera order":"Skapa ny order"}</h2></div><button aria-label="Stäng" className="op-iconbutton" onClick={()=>setEditor(null)}><X/></button></div><div className="op-form"><div className="op-fields"><label>Ordernummer *<input value={editor.number} onChange={e=>field("number",e.target.value)}/></label><label>Datum *<input type="date" value={editor.date} onChange={e=>field("date",e.target.value)}/></label><label>Kund *<input value={editor.customer} onChange={e=>field("customer",e.target.value)} placeholder="Kundnamn"/></label><label>Projekt / arbetsplats<input value={editor.project} onChange={e=>field("project",e.target.value)} placeholder="Projekt eller arbetsplats"/></label><label>Status<select value={editor.status} onChange={e=>field("status",e.target.value)}>{STATUSES.map(s=><option key={s}>{s}</option>)}</select></label><label>Belopp exkl. moms (SEK)<input type="number" min="0" step=".01" value={editor.amount} onChange={e=>field("amount",e.target.value)}/></label><label>Fordon<input value={editor.vehicle} onChange={e=>field("vehicle",e.target.value.toUpperCase())} placeholder="Registreringsnummer"/></label><label>Chaufför<input value={editor.driver} onChange={e=>field("driver",e.target.value)} placeholder="Namn"/></label></div><label>Uppdragsbeskrivning<textarea rows={3} value={editor.description} onChange={e=>field("description",e.target.value)} placeholder="Beskriv transporten eller arbetet"/></label><label>Interna anteckningar<textarea rows={3} value={editor.notes} onChange={e=>field("notes",e.target.value)}/></label>{error&&<div className="op-error" role="alert">{error}</div>}</div><div className="op-editorfoot">{editingId?<button className="op-danger" onClick={remove}><Trash2 size={16}/> Ta bort</button>:<span/>}<div><button className="op-secondary" onClick={()=>setEditor(null)}>Avbryt</button><button className="op-primary" onClick={save}><Save size={16}/> Spara order</button></div></div></div></div>}
  </div>
}