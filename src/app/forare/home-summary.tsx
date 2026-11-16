import Link from 'next/link';
import type {DriverReport} from '@/lib/hub/driver-self';

const formatDay=(value:string)=>new Intl.DateTimeFormat('sv-SE',{day:'numeric',month:'short',year:'numeric',timeZone:'UTC'}).format(new Date(value+'T00:00:00Z'));

export function HomeSummary({report,period,demo=false}:{report?:DriverReport|null;period?:{from:string;to:string};demo?:boolean}){
 const ready=report?.status==='ready';
 return <section className="driver-home-summary" aria-label="Min sammanfattning">
  <h2>Min sammanfattning</h2>
  {period&&ready&&<p>{formatDay(period.from)} – {formatDay(period.to)} · {demo?'Exempeldata':'Senast inlästa period'}</p>}
  {ready?<dl>
   <div><dt>Tidrapportering</dt><dd>{report.reporting==='good'?'Tider inskickade':report.reporting==='attention'?'Se över dina tider':'Inget underlag'}</dd></div>
   <div><dt>Senast registrerade arbetsdag</dt><dd>{report.latest_work_date?formatDay(report.latest_work_date):'Inget underlag'}</dd></div>
   {report.vehicle_context?.map(vehicle=>{
    const gap=vehicle.goal_gap_pp;
    return <div key={vehicle.name}><dt>{vehicle.name} · Fordonets mål</dt><dd>{gap==null?'Underlag saknas':gap===0?'På målet':new Intl.NumberFormat('sv-SE',{maximumFractionDigits:1}).format(Math.abs(gap))+' procentenheter '+(gap<0?'under':'över')+' målet'}</dd></div>;
   })}
  </dl>:<p>Inget personligt underlag tillgängligt.</p>}
  <div className="driver-home-actions">
   <Link className="driver-link driver-primary" href="/forare/tid">Rapportera tid</Link>
   {!demo&&<Link className="driver-link" href="/chauffor">Hela chaufförsvyn</Link>}
  </div>
  <details>
   <summary>Tanka med B.SMART</summary>
   <p>Öppna PIUSI B.SMART på mobilen och använd ditt befintliga tankkonto.</p>
   <div className="driver-home-actions">
    <a className="driver-link" href="https://apps.apple.com/se/app/piusi-b-smart/id1440012334" target="_blank" rel="noreferrer">App Store</a>
    <a className="driver-link" href="https://play.google.com/store/apps/details?id=com.piusi.sssa" target="_blank" rel="noreferrer">Google Play</a>
   </div>
  </details>
 </section>;
}
