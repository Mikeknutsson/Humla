'use client';

import Link from 'next/link';
import {BarChart3, ChevronRight, Construction, FolderKanban, Gauge, Recycle, Truck, Users, Wrench} from 'lucide-react';
import styles from './kpi-followup-nav.module.css';

const areas = [
  {title:'Lastbilar', icon:Truck, links:[
    {id:'trucks', label:'Enhetsuppföljning', path:'/kpi', params:{view:'kpi',cost_center:'30'}, icon:BarChart3},
    {id:'drivers', label:'Chaufförsvy', path:'/chauffor', icon:Truck, keepPeriod:false},
    {id:'foremen', label:'Arbetsledarvyer', path:'/kpi/mina-enheter', icon:Users, keepPeriod:false},
    {id:'fleet', label:'Fordon & TCO', path:'/kpi/fordon', icon:Gauge},
  ]},
  {title:'Återvinning', icon:Recycle, links:[
    {id:'recycling', label:'Enhetsuppföljning', path:'/kpi', params:{view:'kpi',cost_center:'20'}, icon:BarChart3},
  ]},
  {title:'Verkstad', icon:Wrench, links:[
    {id:'workshop', label:'Verkstaden', path:'/kpi/verkstad', icon:Gauge},
    {id:'workshop-orders', label:'Arbetsorder', path:'/kpi/verkstad/arbetsorder', icon:Wrench, keepPeriod:false},
  ]},
  {title:'Maskiner', icon:Construction, links:[
    {id:'machines', label:'Maskinuppföljning', path:'/kpi/maskiner', icon:BarChart3},
  ]},
  {title:'Entreprenad', icon:FolderKanban, links:[
    {id:'projects', label:'Projektuppföljning', path:'/kpi/projekt', params:{center:'10'}, icon:BarChart3},
  ]},
] as const;

export type FollowupPage = (typeof areas)[number]['links'][number]['id'];

export function KpiFollowupNav({query, active, expanded = Boolean(active), onNavigate}:{
  query:string;
  active?:FollowupPage;
  expanded?:boolean;
  onNavigate?:() => void;
}) {
  const selection = new URLSearchParams(query);
  const period = new URLSearchParams();
  for (const key of ['fiscal_year','months','period_mode','from','to','date_from','date_to']) {
    const value = selection.get(key);
    if (value) period.set(key,value);
  }

  return <details className={styles.followup} open={expanded}>
    <summary><BarChart3 size={18}/>Uppföljning<ChevronRight size={16} className={styles.chevron}/></summary>
    <div className={styles.areas}>
      {areas.map(({title,icon:AreaIcon,links}) =>
        <details key={title} className={styles.area} open={links.some(link => link.id === active)}>
          <summary><AreaIcon size={16}/>{title}<ChevronRight size={14} className={styles.chevron}/></summary>
          <div className={styles.links}>
            {links.map(link => {
              const {id,label,path,icon:Icon} = link;
              const params = new URLSearchParams('keepPeriod' in link && !link.keepPeriod ? undefined : period);
              const mode = params.get('period_mode');
              if (id === 'workshop' || id === 'machines') {
                if (params.has('months') && !mode) params.set('period_mode','months');
              } else if (mode !== 'ytd') {
                params.delete('period_mode');
              }
              if ('params' in link) for (const [key,value] of Object.entries(link.params)) params.set(key,value);
              const current = id === active;
              return <Link key={id} prefetch={false} href={params.size ? path+'?'+params : path}
                className={current ? 'active' : undefined} aria-current={current ? 'page' : undefined} onClick={onNavigate}>
                <Icon size={16}/>{label}
              </Link>;
            })}
          </div>
        </details>
      )}
    </div>
  </details>;
}
