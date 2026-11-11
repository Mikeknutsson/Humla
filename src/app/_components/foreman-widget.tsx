import Link from 'next/link';
import type {TransportScorecard} from '@/lib/kpi/transport-leader';
import {foremanWidgetHref} from '@/lib/kpi/foreman-widget';
import {KpiMarginGauge} from './kpi-margin-gauge';
import styles from './foreman-widget.module.css';

const money = new Intl.NumberFormat('sv-SE', {style:'currency', currency:'SEK', maximumFractionDigits:0});
const percent = new Intl.NumberFormat('sv-SE', {maximumFractionDigits:1});

export function ForemanWidget({period, profile, report, detailHref, dates, title}: {
  period:'month'|'ytd'; profile:string|null; report:TransportScorecard|null;
  detailHref:string; dates:string; title:string;
}) {
  const summary = report?.summary;
  const target = summary?.target_margin_percent;
  return <main className={styles.frame}><article className={styles.window}>
    <header className={styles.chrome}><span className={styles.icon} aria-hidden="true">H</span>Humla · Arbetsledarvy</header>
    <div className={styles.body}>
      <h1>{title}</h1>
      <nav className={styles.period} aria-label="Period">
        <Link prefetch={false} aria-current={period==='month'?'page':undefined} href={foremanWidgetHref('month',profile)}>Den här månaden</Link>
        <Link prefetch={false} aria-current={period==='ytd'?'page':undefined} href={foremanWidgetHref('ytd',profile)}>Verksamhetsåret hittills</Link>
      </nav>
      {summary?<><Link prefetch={false} href={detailHref} className={styles.gaugeLink} aria-label="Öppna Arbetsledarvyn för samma period">
        <KpiMarginGauge label={title} margin={summary.margin_percent} target={target}/>
      </Link>
      <dl className={styles.metrics}>
        <div><dt>Målmarginal</dt><dd>{target==null?'–':percent.format(target)+' %'}</dd></div>
        <div><dt>Resultat</dt><dd>{summary.result==null?'–':money.format(summary.result)}</dd></div>
      </dl></>:<p role="status">Inget underlag kunde visas för perioden.</p>}
      <footer className={styles.footer}><span>{dates}</span><Link prefetch={false} href={detailHref}>Öppna Arbetsledarvyn ↗</Link></footer>
    </div>
  </article></main>;
}
