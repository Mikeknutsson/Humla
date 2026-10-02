'use client';

import {createContext,useContext,useState} from 'react';
import {PanelLeftClose,PanelLeftOpen} from 'lucide-react';
import styles from './kpi-workspace.module.css';

const SidebarContext=createContext<{collapsed:boolean;toggle:()=>void}|null>(null);

export function KpiWorkspace({children}:{children:React.ReactNode}) {
 const [collapsed,setCollapsed]=useState(false);
 return <SidebarContext.Provider value={{collapsed,toggle:()=>setCollapsed(value=>!value)}}>
  <div className={`app-shell ${styles.workspace} ${collapsed?styles.collapsed:''}`}>{children}</div>
 </SidebarContext.Provider>;
}

export function KpiSidebarToggle() {
 const sidebar=useContext(SidebarContext);
 if(!sidebar)return null;
 const label=sidebar.collapsed?'Visa vänstermenyn':'Dölj vänstermenyn';
 return <button type="button" className={`icon-button ${styles.desktopToggle}`} aria-label={label} title={label} aria-expanded={!sidebar.collapsed} aria-controls="kpi-sidebar" onClick={sidebar.toggle}>
  {sidebar.collapsed?<PanelLeftOpen size={20}/>:<PanelLeftClose size={20}/>}
 </button>;
}
