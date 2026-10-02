import Link from 'next/link';
import { BarChart3, LayoutDashboard, ArrowLeft } from 'lucide-react';
import styles from './kpi-detail-shell.module.css';
import {KpiWorkspace,KpiSidebarToggle} from './kpi-workspace';

export function KpiDetailShell({query,children}:{query:string;children:React.ReactNode}) {
 const p=new URLSearchParams(query);
 for(const k of ['level','grain','page','view','auth_retry']) p.delete(k);
 const overview=`/kpi?${p}`;
 const kpi=`/kpi?view=kpi&${p}`;
 return <div className="kpi-app"><KpiWorkspace>
  <aside id="kpi-sidebar" className="sidebar"><div className="brand-wrap"><div className="brand-mark">H</div><div><div className="brand">Humla</div><div className="brand-sub">DASHBOARD</div></div></div>
   <nav className="nav" aria-label="Dashboard"><Link href={overview} prefetch={false}><LayoutDashboard size={18}/>Översikt</Link><Link href={kpi} prefetch={false}><BarChart3 size={18}/>KPI</Link><span className={styles.active}>Kostnader & underlag</span></nav>
  </aside>
  <main className={styles.main}><header className="topbar"><KpiSidebarToggle/><div><span className="breadcrumb">Humla Dashboard / Transport / Underlag</span><h1>Kostnader & underlag</h1></div><Link href={kpi} prefetch={false} className="secondary"><ArrowLeft size={16}/>Till KPI med samma urval</Link></header>{children}</main>
 </KpiWorkspace></div>;
}
