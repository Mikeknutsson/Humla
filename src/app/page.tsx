const modules = [
  { name: "Styrning & ekonomi", desc: "Nyckeltal, ekonomi, projektuppföljning och drilldown.", href: "/styrning", meta: "KPI & uppföljning" },
  { name: "Resurser", desc: "Fordon, maskiner, verkstad och gemensam resursplanering.", href: "/resurser", meta: "Fordon & maskin" },
  { name: "Transportledning", desc: "Order, chaufförer, ekipage, status och faktureringsflöde.", href: "/transport", meta: "Order & trafik" },
  { name: "KMA", desc: "Riskanalyser, arbetsberedningar, egenkontroll och signering.", href: "/kma", meta: "Kvalitet & miljö" },
];

export default function Home() {
  return <div className="shell">
    <aside className="sidebar">
      <div className="brand">Humla</div><div className="brandline"/>
      <div className="systemname">DIGITAL SYSTEM</div>
      <nav className="nav">
        <a className="navitem active" href="/">Översikt</a>
        <a className="navitem" href="/styrning">Styrning & ekonomi</a>
        <a className="navitem" href="/resurser">Resurser</a>
        <a className="navitem" href="/transport">Transportledning</a>
        <a className="navitem" href="/kma">KMA</a>
        <a className="navitem" href="/admin">Admin · Integrationer</a>
      </nav>
    </aside>
    <main className="main">
      <header className="topbar"><div><div className="eyebrow">Humla · Översikt</div><h1 className="title">Digital arbetsyta</h1></div><div className="user">MK</div></header>
      <p className="lead intro">Gemensam ingång till Elleholms operativa system. Samma resurser, behörigheter och objekt följer med mellan modulerna.</p>
      <div className="statusrow">
        <div className="status"><span className="dot"/>Humla Hub anslutningsklar</div>
        <div className="status neutral">Mobilanpassad grund</div>
        <div className="status neutral">Rollstyrning förberedd</div>
      </div>
      <section className="grid">{modules.map((m)=><a className="card" href={m.href} key={m.name}><span className="label">{m.meta}</span><strong>{m.name}</strong><p>{m.desc}</p><span className="open">Öppna modul →</span></a>)}</section>
      <section className="workspace"><div><span className="label">GEMENSAM ARBETSYTA</span><h2>En planeringsmotor. Flera verksamheter.</h2><p>Resursbokningar ska kunna skapas i sin källmodul och visas som låsta referenser i andra relevanta delar av Humla.</p></div><div className="flow"><span>Entreprenad</span><b>↔</b><span>Transport</span><b>↔</b><span>Verkstad</span></div></section>
    </main>
  </div>
}
