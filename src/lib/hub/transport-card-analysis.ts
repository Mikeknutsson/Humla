import type {TransportMetrics, TransportScorecard, TransportAnalysisInput, TransportCardAnalysis} from '../kpi/transport-leader';

const number = new Intl.NumberFormat('sv-SE', {maximumFractionDigits: 1});
const money = (value: number) => `${number.format(Math.round(value))} kr`;
const percent = (value: number) => `${number.format(value)} %`;
const share = (amount: number, revenue: number) => revenue > 0 ? amount / revenue * 100 : null;
const median = (values: number[]) => {
  const sorted = values.filter(Number.isFinite).sort((a,b) => a-b);
  const mid = Math.floor(sorted.length/2);
  return sorted.length ? sorted.length%2 ? sorted[mid] : (sorted[mid-1]+sorted[mid])/2 : null;
};

function combine(rows: TransportAnalysisInput[]): TransportAnalysisInput | null {
  if (!rows.length) return null;
  return {
    unit_id: rows[0].unit_id, unit_name: rows[0].unit_name,
    business_group: [...new Set(rows.filter(r=>r.revenue>0).map(r => r.business_group))].join(', '),
    revenue: rows.reduce((n,r) => n+r.revenue,0),
    personnel: rows.reduce((n,r) => n+r.personnel,0),
    service_repair: rows.reduce((n,r) => n+r.service_repair,0),
    fuel: rows.reduce((n,r) => n+r.fuel,0),
    worked_hours: rows.some(r=>r.personnel>0) && rows.filter(r=>r.personnel>0).every(r => r.worked_hours != null && r.worked_hours > 0)
      ? rows.reduce((n,r) => n+(r.worked_hours??0),0) : null,
  };
}

/** Server-side interpretation of authorized Hub aggregates; no financial mutations. */
export function analyzeTransportCard(
  metrics: TransportMetrics,
  current: TransportAnalysisInput | null,
  previous: TransportAnalysisInput | null,
  peers: TransportAnalysisInput[],
): TransportCardAnalysis {
  const hasTarget = metrics.target_margin_percent != null;
  const belowTarget = hasTarget && metrics.deviation_pp != null && metrics.deviation_pp < 0;
  const result: TransportCardAnalysis = {
    status: belowTarget ? 'warning' : !hasTarget ? 'unknown' : 'ok',
    summary: belowTarget
      ? `${number.format(Math.abs(metrics.deviation_pp!))} procentenheter under mål${metrics.deviation_amount == null ? '.' : ` · ${money(Math.abs(metrics.deviation_amount))} saknas till målresultatet.`}`
      : !hasTarget ? 'Mål saknas för hela eller delar av perioden. Jämförelserna nedan är inga målavvikelser.'
      : 'Marginalmålet är uppnått.',
    insights: [], limitations: [],
  };
  if (!current || current.revenue <= 0) {
    result.limitations.push('Positiva intäkter saknas. Kostnad per intäktskrona och intäkt per timme kan inte bedömas.');
    return result;
  }
  // Focus the card on deviations; a met target should not generate warning noise.
  if (hasTarget && !belowTarget) return result;
  const eligible = peers.filter(p => p.unit_id !== current.unit_id && p.revenue >= 10000);
  const comparable = eligible.length >= 2 ? eligible : [];
  const history = previous && previous.revenue >= 10000 ? previous : null;
  const candidates: {title:string; evidence:string[]; severity:number}[] = [];
  for (const [key,title] of [
    ['service_repair','Hög service- och reparationskostnad'],
    ['personnel','Hög personalkostnad i förhållande till intäkterna'],
    ['fuel','Hög bränslekostnad i förhållande till intäkterna'],
  ] as const) {
    const value = share(current[key], current.revenue)!;
    const own = history && (key!=='personnel' || history.personnel>=5000) ? share(history[key],history.revenue) : null;
    const costPeers=key==='personnel'?comparable.filter(p=>p.personnel>=5000):comparable;
    const peer = costPeers.length>=2?median(costPeers.map(p => share(p[key],p.revenue)!)):null;
    const evidence: string[] = [];
    let severity = 0;
    for (const [baseline,label] of [[own,'samma period föregående år'],[peer,`medianen för ${costPeers.length} andra enheter i ${current.business_group}`]] as const) {
      if (baseline != null && current[key] >= 10000 && value-baseline >= 5 && value >= baseline*1.5) {
        evidence.push(`${percent(value)} av intäkterna (${money(current[key])}), jämfört med ${percent(baseline)} ${label}.`);
        severity = Math.max(severity,value-baseline);
      }
    }
    if (evidence.length) candidates.push({title,evidence,severity});
  }
  if (current.worked_hours != null && current.worked_hours >= 40) {
    const hourly = current.revenue/current.worked_hours;
    const own = history?.worked_hours != null && history.worked_hours >= 40 ? history.revenue/history.worked_hours : null;
    const timedPeers = comparable.filter(p => p.worked_hours != null && p.worked_hours >= 40);
    const peer = timedPeers.length >= 2 ? median(timedPeers.map(p => p.revenue/p.worked_hours!)) : null;
    const evidence: string[] = [];
    let severity = 0;
    for (const [baseline,label] of [[own,'samma period föregående år'],[peer,`medianen för ${timedPeers.length} andra enheter i ${current.business_group}`]] as const) {
      if (baseline != null && baseline > 0 && hourly <= baseline*.7) {
        evidence.push(`${money(hourly)}/tim mot ${money(baseline)}/tim ${label} (${number.format(current.worked_hours)} TransPA-timmar).`);
        severity = Math.max(severity,(1-hourly/baseline)*100);
      }
    }
    if (evidence.length) candidates.push({title:'Hög arbetstid i förhållande till intäkterna',evidence,severity});
  } else result.limitations.push('Komplett, entydigt kopplad TransPA-tid saknas. Ingen slutsats om arbetstid visas.');
  result.insights = candidates.sort((a,b) => b.severity-a.severity).slice(0,2).map(({title,evidence}) => ({title,evidence}));
  if (!history) result.limitations.push('Jämförbar egen historik saknas för samma period föregående år.');
  if (!comparable.length) result.limitations.push('Minst två andra enheter med tillräckliga intäkter i samma verksamhetsområde krävs för gruppjämförelse.');
  if (!result.insights.length) result.limitations.unshift('Ingen tydlig avvikelse har kunnat beläggas för personal, service/reparation, bränsle eller intäkt per timme.');
  return result;
}

export function buildTransportCardAnalyses(report: TransportScorecard, previous: TransportScorecard | null) {
  const rows = report.analysis_inputs ?? [], old = previous?.analysis_inputs ?? [];
  const currentUnits = new Map([...new Set(rows.map(r=>r.unit_id))].map(id=>[id,combine(rows.filter(r=>r.unit_id===id))!]));
  const units: Record<string,TransportCardAnalysis> = {};
  for (const unit of report.units) {
    const current = unit.unit_id ? currentUnits.get(unit.unit_id) ?? null : null;
    const history = combine(old.filter(r => r.unit_id === unit.unit_id));
    const groups = new Set(rows.filter(r => r.unit_id === unit.unit_id && r.revenue>0).map(r => r.business_group));
    // Multi-area units have no single comparable peer group. Never compare them with a mix.
    const peers = groups.size === 1 && current?.business_group !== 'Ej klassificerat'
      ? [...currentUnits.values()].filter(r => r.business_group === current?.business_group) : [];
    units[unit.unit_id ?? 'unassigned'] = analyzeTransportCard(unit,current,history,peers);
  }
  const groups: Record<string,TransportCardAnalysis> = {};
  for (const group of report.groups) {
    const members = rows.filter(r => r.business_group === group.business_group);
    const analysis = analyzeTransportCard(group,combine(members),combine(old.filter(r => r.business_group === group.business_group)),[]);
    // Area cards surface unit evidence, then link through to those units.
    if (analysis.status !== 'ok') {
      const unitFindings = members.flatMap(row => {
        if(currentUnits.get(row.unit_id)?.business_group!==group.business_group)return [];
        return (units[row.unit_id]?.insights ?? []).map(i => ({...i,title:`${row.unit_name ?? 'Enhet'}: ${i.title}`}));
      });
      analysis.insights = [...analysis.insights,...unitFindings].slice(0,2);
      analysis.limitations = analysis.limitations.filter(x => !x.startsWith('Minst två andra'));
      if(analysis.insights.length)analysis.limitations=analysis.limitations.filter(x=>!x.startsWith('Ingen tydlig'));
    }
    groups[group.business_group] = analysis;
  }
  return {units,groups};
}
