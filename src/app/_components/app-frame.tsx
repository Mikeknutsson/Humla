"use client";
import Link from "next/link";
import {usePathname} from "next/navigation";

const hubNavigation = [
  {href:"/hub",label:"Hub – översikt"},
  {href:"/integrationer",label:"Integrationer"},
  {href:"/floden",label:"Flöden"},
  {href:"/datakvalitet",label:"Datakvalitet"},
  {href:"/granskning",label:"Granskning & mappning"},
  {href:"/klimat",label:"Klimat"},
  {href:"/logg",label:"Händelser & logg"},
  {href:"/admin",label:"Administration"},
  {href:"/kpi",label:"KPI & Ekonomi"},
];

export function AppFrame({children}:{children:React.ReactNode}) {
  const path=usePathname();
  // The portal owns the root landing page. Existing operational routes retain
  // their shell and URLs until they are migrated into separately tested modules.
  if(path==="/") return <main className="portal-root">{children}</main>;
  return <div className="shell">
    <aside className="sidebar">
      <Link href="/" className="brand" aria-label="Till Humla Portal">Humla</Link>
      <div className="brandline"/>
      <div className="systemname">HUB · ARBETSYTOR</div>
      <nav className="nav" aria-label="Huvudnavigation">
        <Link className="navitem portal-navitem" href="/">← Humla Portal</Link>
        {hubNavigation.map(item=><Link key={item.href} href={item.href}
          aria-current={path===item.href || (item.href!=="/hub" && path.startsWith(item.href+"/"))?"page":undefined}
          className={"navitem"+(path===item.href || (item.href!=="/hub" && path.startsWith(item.href+"/"))?" active":"")}>
            {item.label}</Link>)}
      </nav>
      <div className="sidefoot"><span className="liveDot"/>HUMLA HUB</div>
    </aside>
    <main className="main">{children}</main>
  </div>;
}
