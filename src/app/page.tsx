const nav=["Översikt","Integrationer","Flöden","Datakvalitet","Händelser & logg","Administration"];
const integrations=[
 {name:"Fordonskontrollen",type:"Fordon & resurser",status:"Aktiv",detail:"Tvåvägssynk och dokumentflöden"},
 {name:"B.Smart / Piusi",type:"Bränsle",status:"Aktiv",detail:"Tankningar och bränsledata"},
 {name:"Circle K",type:"Bränsle",status:"Aktiv",detail:"Fleet-anslutning"},
];
const stats=[
 ["3","Aktiva anslutningar","Konfigurerade tenant-anslutningar"],
 ["440","Humla-objekt","Normaliserade objekt i Hubben"],
 ["13","Händelser","Registrerade Hub-events"],
 ["1","Behöver granskas","Post i review queue"],
];
export default function Home(){return <div className="shell">
 <aside className="sidebar"><div className="brand">Humla</div><div className="brandline"/><div className="systemname">HUB</div><nav className="nav">{nav.map((n,i)=><a key={n} className={"navitem "+(i===0?"active":"")} href={i===0?"/":"#"+n.toLowerCase().replaceAll(" ","-")}>{n}</a>)}</nav></aside>
 <main className="main"><header className="topbar"><div><div className="eyebrow">Humla Hub · Systemadministration</div><h1>Översikt</h1><p>Integrationsnavet mellan Humla och externa system.</p></div><div className="health"><span/>HUB ONLINE</div></header>
 <section className="stats">{stats.map(([v,l,d])=><article key={l}><b>{v}</b><strong>{l}</strong><small>{d}</small></article>)}</section>
 <section className="section" id="integrationer"><div className="sectionhead"><div><span className="label">ANSLUTNINGAR</span><h2>Integrationer</h2></div><button>+ Ny anslutning</button></div>
 <div className="table"><div className="tr th"><span>System</span><span>Typ</span><span>Status</span><span>Funktion</span><span/></div>{integrations.map(x=><div className="tr" key={x.name}><strong>{x.name}</strong><span>{x.type}</span><span className="ok"><i/> {x.status}</span><span>{x.detail}</span><span className="arrow">→</span></div>)}</div></section>
 <div className="twocol"><section className="section"><span className="label">DATAMOTOR</span><h2>Normalisering</h2><div className="metric"><span>Externa referenser</span><b>404</b></div><div className="metric"><span>Identitetsnycklar</span><b>211</b></div><div className="metric"><span>Objektversioner</span><b>863</b></div><div className="metric"><span>Connector-kontrakt</span><b>12</b></div></section>
 <section className="section"><span className="label">DRIFT</span><h2>Hub-status</h2><div className="metric"><span>Connector-definitioner</span><b>46</b></div><div className="metric"><span>Flödesmallar</span><b>8</b></div><div className="metric warn"><span>Granskningskö</span><b>1</b></div><div className="metric"><span>Dead letter queue</span><b>0</b></div></section></div>
 <section className="section architecture"><span className="label">PRINCIP</span><h2>En väg in. Ett gemensamt språk. Kontrollerad väg ut.</h2><div className="pipeline"><span>Källsystem</span><b>→</b><span>Ingress</span><b>→</b><span className="yellow">Humla Object ID</span><b>→</b><span>Normalisering</span><b>→</b><span>Routing</span><b>→</b><span>Målsystem</span></div></section>
 </main></div>}