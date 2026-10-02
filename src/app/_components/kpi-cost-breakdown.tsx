import Link from 'next/link';
import {analysisHref} from '@/lib/kpi/analysis';
const categories = [
  ["personnel", "Personal"], ["fuel", "Bränsle"],
  ["service_repair", "Service & Rep"], ["depreciation", "Avskrivning"],
  ["fixed", "Fasta kostnader"], ["material", "Material / Ballast"],
  ["tipp_deponi", "Tipp / Deponi"], ["hired", "Inhyrda"], ["other", "Övrigt"],
] as const;
const money = new Intl.NumberFormat("sv-SE", { style: "currency", currency: "SEK", maximumFractionDigits: 0 });
function amount(value: number | string | null | undefined) {
  return value == null || value === "" || !Number.isFinite(Number(value)) ? "–" : money.format(Number(value));
}

export function KpiCostBreakdown({ values, total, query, personnelBasis }: {
  values: Record<string, number | string | null | undefined>;
  total: number | string | null | undefined;
  query: string;
  personnelBasis?: string;
}) {
  function detail(category: string) {
    const params = new URLSearchParams(query);
    params.set("category", category);
    params.set("kind", "cost");
    params.set("level", "group");
    return analysisHref(params.toString());
  }
  return <section className="panel cost-breakdown" aria-label="Kostnadsfördelning">
    <div className="panel-head"><div><span className="section-kicker">Kostnader i valt urval</span><h2>Kostnadsfördelning</h2></div><div><span>Total kostnad</span><Link prefetch={false} href={analysisHref(query,{category:null,kind:"cost"})}><strong>{amount(total)}</strong></Link></div></div>
    <div className="cost-breakdown-grid">{categories.map(([key, label]) => <Link prefetch={false} key={key} href={detail(key)}>
      <span>{label}</span><strong>{amount(values[key])}</strong><small>Visa underlag →</small>
    </Link>)}</div>
    <p>Beloppen ingår redan i total kostnad. Klicka på en kategori för detaljer med samma period, kostnadsställe, verksamhetsgrupp och enhetsurval.</p>
    {personnelBasis && <p>{personnelBasis}</p>}
  </section>;
}
