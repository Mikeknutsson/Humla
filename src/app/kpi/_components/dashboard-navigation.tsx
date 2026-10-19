"use client";
import Link from "next/link";
import {usePathname} from "next/navigation";
const menu=[{href:"/kpi",name:"KPI-översikt"},{href:"/kpi/ekonomi",name:"Ekonomi"},{href:"/kpi/transport-styrning",name:"Transportledare"}];
export function DashboardNavigation({showEconomy,showTransport}:{showEconomy:boolean;showTransport:boolean}){
 const path=usePathname();
 if(path==="/kpi/login"||path.startsWith("/kpi/ekonomi/login"))return null;
 const entries=menu.filter(e=>e.href==="/kpi"||(e.href.endsWith("/ekonomi")?showEconomy:showTransport));
 return <nav aria-label="Dashboard-arbetsytor" style={{display:"flex",gap:10,alignItems:"center",flexWrap:"wrap",padding:"10px 20px",background:"#17191b",borderBottom:"1px solid #363638",color:"#eee",fontFamily:"Arial, sans-serif",fontSize:13}}>
 <span style={{color:"#f2c500",fontSize:11,fontWeight:800,letterSpacing:1.2,marginRight:14}}>HUMLA DASHBOARD</span>
 {entries.map(e=><Link key={e.href} href={e.href} aria-current={path===e.href||path.startsWith(e.href+"/")?"page":undefined}
 style={{borderBottom:path===e.href||path.startsWith(e.href+"/")?"2px solid #f2c500":"2px solid transparent",padding:"8px 10px",fontWeight:path.startsWith(e.href)?700:400}}>{e.name}</Link>)}
 </nav>;
}
