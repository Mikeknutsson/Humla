import Link from 'next/link';
import { BarChart3, LayoutDashboard, ArrowLeft } from 'lucide-react';
import {logout} from "@/app/kpi/login/actions";
import styles from './kpi-detail-shell.module.css';
import {KpiFollowupNav, type FollowupPage} from './kpi-followup-nav';
import {KpiTransportAdministrationNav} from './kpi-transport-administration-nav';
import {KpiWorkspace,KpiSidebarToggle} from './kpi-workspace';

export function KpiDetailShell({query,children,title='Kostnader & underlag',breadcrumb='Humla Dashboard / Transport / Underlag',extraNavigation,followup,personal=false,transportAdministration=false}:{query:string;children:React.ReactNode;title?:string;breadcrumb?:string;extraNavigation?:React.ReactNode;followup?:FollowupPage;personal?:boolean;transportAdministration?:boolean|'material'}) {
 const p=new URLSearchParams(query);
 for(const k of ['level','grain','page','view','auth_retry']) p.delete(k);
 const overview=`/kpi?${p}`;
 const kpi=`/kpi?view=kpi&${p}`;
 return <div className="kpi-app"><KpiWorkspace>
  <aside id="kpi-sidebar" className="sidebar"><div className="brand-wrap"><div className="brand-mark">H</div><div><div className="brand">Humla</div><div className="brand-sub">DASHBOARD</div></div></div>
   <nav className="nav" aria-label="Dashboard">{!personal&&<><Link href={overview} prefetch={false}><LayoutDashboard size={18}/>Översikt</Link>{followup?<KpiFollowupNav query={query} active={followup}/>:<Link href={kpi} prefetch={false}><BarChart3 size={18}/>Enhetsuppföljning</Link>}{transportAdministration&&<KpiTransportAdministrationNav active={transportAdministration}/>}{extraNavigation}</>}{((!followup&&!transportAdministration)||personal)&&<span className={styles.active} aria-current="page">{title}</span>}</nav>
  </aside>
  <main className={styles.main}><header className="topbar"><KpiSidebarToggle/><div><span className="breadcrumb">{breadcrumb}</span><h1>{title}</h1></div>{personal?<form action={logout}><button type="submit" className="secondary">Logga ut</button></form>:<Link href={kpi} prefetch={false} className="secondary"><ArrowLeft size={16}/>{query?'Till enhetsuppföljning med samma urval':'Till enhetsuppföljning'}</Link>}</header>
   {followup&&!personal&&<nav className={`nav ${styles.mobileFollowup}`} aria-label="Uppföljningsmeny"><KpiFollowupNav query={query}/></nav>}
   {children}</main>
 </KpiWorkspace></div>;
}
