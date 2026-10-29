'use client';
import {useTransition} from 'react';
import {useRouter} from 'next/navigation';
import {foremanPeriodQuery,type ForemanPeriod} from '@/lib/kpi/foreman-period';
import {fiscalMonths,monthLabels} from '@/lib/kpi/period';
import styles from './foreman-period-picker.module.css';

export function ForemanPeriodPicker({period,userId,cutoffError=false}:{period:ForemanPeriod;userId?:string|null;cutoffError?:boolean}) {
 const router=useRouter(),[pending,start]=useTransition();
 function choose(mode:ForemanPeriod['mode'],month=period.month,year=period.fiscalYear){
  const next={...period,mode:mode==='ytd'&&year>period.currentFiscalYear?'year' as const:mode,month,fiscalYear:year};
  start(()=>router.replace('/kpi/mina-enheter?'+foremanPeriodQuery(next,userId),{scroll:false}));
 }
 const years=Array.from(new Set([period.fiscalYear,...Array.from({length:5},(_,i)=>period.currentFiscalYear-i)])).sort((a,b)=>b-a);
 return <div className={styles.picker} aria-label="Period" aria-busy={pending}>
 <div className={styles.top}><label className={styles.year}>Verksamhetsår<select aria-label="Verksamhetsår" value={period.fiscalYear} disabled={pending} onChange={e=>choose(period.mode,period.month,Number(e.target.value))}>{years.map(y=><option key={y} value={y}>{y}/{y+1}</option>)}</select></label>
 <div className={styles.shortcuts}>{([['ytd','YTD'],['revenue','Intäkter fram till'],['year','Helår']]as const).map(([mode,label])=><button key={mode} type="button" aria-pressed={period.mode===mode} disabled={pending||(mode==='revenue'&&(cutoffError||!period.revenueThrough))} title={mode==='revenue'?'Intäkter och kostnader till senaste datum med giltiga importerade intäkter':mode==='ytd'?'Från 1 september till dagens datum':'1 september–31 augusti'} onClick={()=>choose(mode)}>{label}</button>)}</div></div>
 <div className={styles.months} aria-label="Välj en månad">{fiscalMonths.map((m,i)=><button type="button" key={m} aria-pressed={period.mode==='month'&&period.month===m} disabled={pending} onClick={()=>choose('month',m)}>{monthLabels[i]}</button>)}</div>
 <p className={styles.caption} aria-live="polite">{pending?'Hämtar underlag…':period.to?`${period.from} – ${period.to}`:'Intäktsunderlag saknas för verksamhetsåret.'}{!pending&&period.mode==='revenue'&&period.to?' · Samma slutdatum för intäkter och kostnader':''}{!pending&&period.mode!=='revenue'&&period.revenueThrough?` · Intäkter inlästa t.o.m. ${period.revenueThrough}`:''}{!pending&&cutoffError?' · Senaste intäktsdatum kunde inte hämtas.':''}</p>
 </div>;
}
