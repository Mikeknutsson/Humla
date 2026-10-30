import styles from './kpi-margin-gauge.module.css';

const percent = new Intl.NumberFormat('sv-SE', {maximumFractionDigits: 1});
const finite = (value: number | null | undefined): value is number => typeof value === 'number' && Number.isFinite(value);

/** Presentation only. Margins and dated, weighted targets come from Hub. */
export function KpiMarginGauge({margin, target, label}: {margin: number | null | undefined; target: number | null | undefined; label: string}) {
  const hasMargin = finite(margin);
  const hasTarget = finite(target);
  const min = -50, max = 50;
  const point = (value: number, radius = 76) => {
    const angle = Math.PI * (1 - (Math.max(min, Math.min(max, value)) - min) / (max - min));
    return {x: 110 + Math.cos(angle) * radius, y: 94 - Math.sin(angle) * radius};
  };
  const arc = (from: number, to: number) => {
    const a = point(from), b = point(to);
    return `M ${a.x} ${a.y} A 76 76 0 0 1 ${b.x} ${b.y}`;
  };
  const status = !hasMargin ? 'Marginal saknas' : margin < 0 ? 'Negativt resultat' : !hasTarget ? 'Mål saknas' : margin >= target ? 'Målet uppnått' : 'Under mål';
  const color = !hasMargin ? '#64748b' : margin < 0 ? '#b91c1c' : !hasTarget ? '#475569' : margin >= target ? '#15803d' : '#a16207';
  const needle = point(hasMargin ? margin : 0, 65);
  const targetStart = point(hasTarget ? target : 0, 65), targetEnd = point(hasTarget ? target : 0, 88);
  return <div className={styles.gauge}>
    <svg viewBox="0 0 220 126" role="img" aria-label={`${label}: ${hasMargin ? percent.format(margin) + ' procent marginal' : 'marginal saknas'}. ${hasTarget ? 'Mål ' + percent.format(target) + ' procent.' : 'Mål saknas.'} ${status}.`}>
      <path d={arc(min,max)} fill="none" stroke="#e2e8f0" strokeWidth="15"/>
      <path d={arc(min,0)} fill="none" stroke="#ef4444" strokeWidth="15"/>
      {hasTarget && target > 0 && <path d={arc(0,target)} fill="none" stroke="#fbbf24" strokeWidth="15"/>}
      {hasTarget && target < max && <path d={arc(Math.max(0,target),max)} fill="none" stroke="#22c55e" strokeWidth="15"/>}
      {hasTarget && <line x1={targetStart.x} y1={targetStart.y} x2={targetEnd.x} y2={targetEnd.y} stroke="#0f172a" strokeWidth="3"><title>{`Mål ${percent.format(target)} %`}</title></line>}
      <text x="21" y="119" fontSize="11" fill="currentColor">−50 %</text><text x="110" y="9" textAnchor="middle" fontSize="11" fill="currentColor">0</text><text x="199" y="119" textAnchor="end" fontSize="11" fill="currentColor">+50 %</text>
      {hasMargin && <><line x1="110" y1="94" x2={needle.x} y2={needle.y} stroke="#0f172a" strokeWidth="3.5" strokeLinecap="round"/><circle cx="110" cy="94" r="6" fill="#0f172a"/></>}
    </svg>
    <strong className={styles.value} style={{color}}>{hasMargin ? `${percent.format(margin)} %` : '–'}</strong>
    <span style={{color}}>{status}</span>
    <small>{hasTarget ? `Mål ${percent.format(target)} % · svart markering` : 'Inget fullständigt mål för perioden'}</small>
    {hasMargin && (margin < min || margin > max) && <small>Visaren är vid skalans gräns. Exakt värde visas ovan.</small>}
  </div>;
}
