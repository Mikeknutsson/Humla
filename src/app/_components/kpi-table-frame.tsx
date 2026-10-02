'use client';
import {useLayoutEffect,useRef,useState,type ReactNode} from 'react';
import styles from './kpi-table-frame.module.css';

/** Keep a page-sticky heading and scrollbar outside the table's overflow container. */
export function KpiTableFrame({head,children}:{head:ReactNode;children:ReactNode}) {
 const body=useRef<HTMLDivElement>(null),heading=useRef<HTMLDivElement>(null),bar=useRef<HTMLDivElement>(null);
 const [widths,setWidths]=useState<number[]>([]),[top,setTop]=useState(132);
 const width=widths.reduce((sum,w)=>sum+w,0);
 useLayoutEffect(()=>{
  const container=body.current,table=container?.querySelector('table');
  if(!container||!table)return;
  const measure=()=>{const next=Array.from(table.querySelectorAll('thead th')).map(cell=>cell.getBoundingClientRect().width);setWidths(previous=>previous.length===next.length&&previous.every((w,i)=>Math.abs(w-next[i])<.5)?previous:next);};
  const topbar=container.closest(".kpi-app")?.querySelector(".topbar");
  const refresh= document.querySelector(".kpi-refresh-bar");
  const layout=()=>{measure();setTop((refresh?.getBoundingClientRect().height??0)+(topbar?.getBoundingClientRect().height??0));};
  layout();const observer=new ResizeObserver(layout);observer.observe(table);observer.observe(container);if(topbar)observer.observe(topbar);if(refresh)observer.observe(refresh);
  return()=>observer.disconnect();
 },[]);
 function sync(left:number){for(const ref of [body,heading,bar])if(ref.current&&Math.abs(ref.current.scrollLeft-left)>.5)ref.current.scrollLeft=left;}
 return <div className={styles.frame}>
  <div className={styles.sticky} style={{top}}>
   <div ref={heading} className={styles.heading} aria-hidden="true"><table style={{width:width||2600,tableLayout:'fixed'}}><colgroup>{widths.map((w,i)=><col key={i} style={{width:w}}/>)}</colgroup>{head}</table></div>
   <div ref={bar} className={styles.bar} role="region" aria-label="Rulla KPI-tabellen i sidled" tabIndex={0} onScroll={e=>sync(e.currentTarget.scrollLeft)}><div style={{width:width||2600,height:1}}/></div>
  </div>
  <div ref={body} className={`table-wrap unit-metrics-table ${styles.body}`} onScroll={e=>sync(e.currentTarget.scrollLeft)}>{children}</div>
 </div>;
}
