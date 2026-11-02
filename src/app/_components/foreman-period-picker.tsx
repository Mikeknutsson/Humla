'use client';
import {useState,useTransition} from 'react';
import {useRouter} from 'next/navigation';
import {foremanPeriodQuery,type ForemanPeriod} from '@/lib/kpi/foreman-period';
import {fiscalMonths,monthLabels} from '@/lib/kpi/period';
import styles from './foreman-period-picker.module.css';

function selectedMonths(period:ForemanPeriod){
 if(period.mode==='months')return period.months;
 if(period.mode==='month')return [period.month];
 if(period.mode==='year')return fiscalMonths;
 return fiscalMonths.filter(m=>period.to&&`${period.fiscalYear+(m<9?1:0)}-${String(m).padStart(2,'0')}-01`<=period.to);
}

export function ForemanPeriodPicker({period,userId,cutoffError=false,pathname='/kpi/mina-enheter',showRevenueShortcut=true}:{period:ForemanPeriod;userId?:string|null;cutoffError?:boolean;pathname?:string;showRevenueShortcut?:boolean}) {
 const router=useRouter(),[pending,start]=useTransition();
 const [draft,setDraft]=useState({base:period,months:selectedMonths(period)});
 const months=draft.base===period?draft.months:selectedMonths(period);
 const label=months.map(m=>monthLabels[fiscalMonths.indexOf(m)]).join(' + ');
 function choose(mode:ForemanPeriod['mode'],month=period.month,year=period.fiscalYear){
  const next={...period,months:mode==='months'?months:[],mode:mode==='ytd'&&year>period.currentFiscalYear?'year' as const:mode,month,fiscalYear:year};
  start(()=>router.replace(pathname+'?'+foremanPeriodQuery(next,userId),{scroll:false}));
 }
 function toggleMonth(m:number){
  setDraft({base:period,months:fiscalMonths.filter(n=>n===m?!months.includes(n):months.includes(n))});
 }
 const years=Array.from(new Set([period.fiscalYear,...Array.from({length:5},(_,i)=>period.currentFiscalYear-i)])).sort((a,b)=>b-a);
 return <div className={styles.picker} aria-label="Period" aria-busy={pending}>
 <div className={styles.top}><label className={styles.year}>Verksamhetsår<select aria-label="Verksamhetsår" value={period.fiscalYear} disabled={pending||(period.mode==='months'&&!months.length)} onChange={e=>choose(period.mode,period.month,Number(e.target.value))}>{years.map(y=><option key={y} value={y}>{y}/{y+1}</option>)}</select></label>
 <div className={styles.shortcuts}>{([['ytd','YTD'],['revenue','Intäkter fram till'],['year','Helår']]as const).filter(([mode])=>showRevenueShortcut||mode!=='revenue').map(([mode,name])=><button key={mode} type="button" aria-pressed={period.mode===mode} disabled={pending||(mode==='revenue'&&(cutoffError||!period.revenueThrough))} title={mode==='revenue'?'Intäkter och kostnader till senaste datum med giltiga importerade intäkter':mode==='ytd'?'Från 1 september till dagens datum':'1 september–31 augusti'} onClick={()=>choose(mode)}>{name}</button>)}</div></div>
 <fieldset className={styles.months} disabled={pending}><legend>Välj en eller flera månader</legend><div className={styles.monthGrid}>{fiscalMonths.map((m,i)=><label key={m} className={styles.month} data-selected={months.includes(m)}><input type="checkbox" checked={months.includes(m)} onChange={()=>toggleMonth(m)}/>{monthLabels[i]}</label>)}</div></fieldset>
 <div className={styles.monthActions}><button type="button" disabled={pending} onClick={()=>setDraft({base:period,months:[]})}>Rensa urval</button><button type="button" className={styles.apply} disabled={pending||!months.length} onClick={()=>choose('months')}>Visa valda månader{months.length?` (${months.length})`:''}</button></div>
 <p className={styles.caption} aria-live="polite">{pending?'Hämtar underlag…':months.length?`Månadsurval: ${label}. Tryck Visa valda månader för att uppdatera.`:'Välj minst en månad.'}</p>
 <p className={styles.caption}>{period.mode==='months'?`Visar endast ${period.months.map(m=>monthLabels[fiscalMonths.indexOf(m)]).join(' + ')} · ${period.fiscalYear}/${period.fiscalYear+1}`:period.to?`${period.from} – ${period.to}`:'Intäktsunderlag saknas för verksamhetsåret.'}{period.mode==='revenue'&&period.to?' · Samma slutdatum för intäkter och kostnader':''}{period.mode!=='revenue'&&period.revenueThrough?` · Intäkter inlästa t.o.m. ${period.revenueThrough}`:''}{cutoffError?' · Senaste intäktsdatum kunde inte hämtas.':''}</p>
 </div>;
}
