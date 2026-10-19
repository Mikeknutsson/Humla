"use client";
import Link from "next/link";
import {usePathname} from "next/navigation";
const nav=[["/","Översikt"],["/integrationer","Integrationer"],["/floden","Flöden"],["/datakvalitet","Datakvalitet"],["/granskning","Granskning & mappning"],["/klimat","Klimat"],["/logg","Händelser & logg"],["/admin","Administration"],["/kpi","Humla Dashboard"]];
export function RootFrame({children}:{children:React.ReactNode}){
 const path=usePathname();
 if(path==="/kpi"||path.startsWith("/kpi/")) return <>{children}</>;
 return <div className="shell"><aside className="sidebar"><Link href="/" className="brand">Humla</Link>
 <div className="brandline"/><div className="systemname">HUB</div>
 <nav className="nav">{nav.map(([h,n])=><Link className="navitem" href={h} key={h}>{n}</Link>)}</nav>
 <div className="sidefoot"><span className="liveDot"/>HUB CORE</div></aside><main className="main">{children}</main></div>;
}
