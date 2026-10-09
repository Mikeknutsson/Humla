'use client';

import {useMemo,useState} from 'react';
import type {ProjectRow} from '@/lib/hub/project-report';
import {projectReportHref} from '@/lib/kpi/project-period';
import styles from '@/app/kpi/projekt/project-report.module.css';

const PAGE_SIZE=100;
const currency=new Intl.NumberFormat('sv-SE',{style:'currency',currency:'SEK',maximumFractionDigits:0});
const percentage=new Intl.NumberFormat('sv-SE',{maximumFractionDigits:1});

export function ProjectList({projects,query}:{projects:ProjectRow[];query:string}){
 const [hideWithoutRevenue,setHideWithoutRevenue]=useState(false);
 const [page,setPage]=useState(0);
 const visible=useMemo(()=>hideWithoutRevenue?projects.filter(p=>p.revenue!==0):projects,[projects,hideWithoutRevenue]);
 const lastPage=Math.max(0,Math.ceil(visible.length/PAGE_SIZE)-1);
 const currentPage=Math.min(page,lastPage),start=currentPage*PAGE_SIZE;
 const params=useMemo(()=>new URLSearchParams(query),[query]);
 const href=(id:string,kind:string|null)=>projectReportHref(params,{project:id,kind});
 return <section className="panel" id="projektlista">
  <h2>Projekt med underlag ({visible.length})</h2>
  <p className={styles.note}>Klicka på projekt eller belopp för att se underlaget. Projekt utan poster i perioden visas inte. Sökningen och knappen nedan begränsar bara listan; totalsummor och export omfattar hela urvalet.</p>
  <button type="button" aria-pressed={hideWithoutRevenue} onClick={()=>{setHideWithoutRevenue(v=>!v);setPage(0);}}>{hideWithoutRevenue?'Visa projekt utan intäkter':'Dölj projekt utan intäkter'}</button>
  <nav className={styles.pager} aria-label="Sidor i projektlistan">
   <button type="button" disabled={currentPage===0} onClick={()=>setPage(currentPage-1)}>← Föregående projekt</button>
   <span aria-live="polite">{visible.length?`Visar ${start+1}–${Math.min(start+PAGE_SIZE,visible.length)} av ${visible.length} projekt`:'Inga projekt att visa'}</span>
   <button type="button" disabled={currentPage===lastPage} onClick={()=>setPage(currentPage+1)}>Nästa projekt →</button>
  </nav>
  <div className={styles.scroll}><table className={styles.table}><thead><tr><th>Projekt</th><th>KST</th><th>Projektledare / grupp</th><th>Intäkter</th><th>Kostnader</th><th>Intern intäkt (ingår)</th><th>Intern kostnad (ingår)</th><th>Resultat</th><th>Marginal</th><th>Personal</th></tr></thead>
   <tbody>{visible.slice(start,start+PAGE_SIZE).map(p=>{
    const all=href(p.id,null),revenue=href(p.id,'revenue'),cost=href(p.id,'cost');
    return <tr key={p.id}><th><a href={all}>{p.project_number} · {p.project_name}</a></th><td>{p.cost_center}</td><td>{p.project_manager}<br/><small>{p.business_group??'—'}</small></td><td className={styles.number}><a href={revenue}>{currency.format(p.revenue)}</a></td><td className={styles.number}><a href={cost}>{currency.format(p.cost)}</a></td><td className={styles.number}><a href={revenue}>{currency.format(p.internal_revenue)}</a></td><td className={styles.number}><a href={cost}>{currency.format(p.internal_cost)}</a></td><td className={`${styles.number} ${p.result<0?styles.negative:''}`}><a href={all}>{currency.format(p.result)}</a></td><td className={styles.number}><a href={all}>{p.margin===null?'—':percentage.format(p.margin)+' %'}</a></td><td className={styles.number}><a href={cost}>{currency.format(p.personnel)}</a></td></tr>;
   })}</tbody></table></div>
 </section>;
}
