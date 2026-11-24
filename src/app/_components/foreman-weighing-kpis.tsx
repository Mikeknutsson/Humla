const tonnes = new Intl.NumberFormat('sv-SE', {maximumFractionDigits: 1});
const count = new Intl.NumberFormat('sv-SE');

type Flow = {
  incoming_tonnes: number;
  outgoing_tonnes: number;
  incoming_count: number;
  outgoing_count: number;
};

type Material = Flow & {material: string | null};
type StockLocation = Flow & {location: string | null; materials: Material[]};

export type ForemanWeighingReport = Flow & {
  count: number;
  days: number;
  latest_weighing: string | null;
  locations: StockLocation[];
};

export function ForemanWeighingKpis({report}: {report: ForemanWeighingReport | null}) {
  return <section className="panel" aria-labelledby="foreman-weighing-kpis">
    <h2 id="foreman-weighing-kpis">Flöden över fordonsvågen</h2>
    {!report ? <p role="status">Vågunderlaget kunde inte hämtas.</p> : report.count === 0
      ? <p>Det finns inga in- eller utvägningar i det valda urvalet.</p>
      : <>
        <p>Flintab · Senaste vägning i urvalet {report.latest_weighing}</p>
        <div className="metrics-grid">
          <article className="metric-card">
            <span>Invägt</span>
            <strong>{tonnes.format(report.incoming_tonnes)} ton</strong>
            <small>{count.format(report.incoming_count)} vägningar</small>
          </article>
          <article className="metric-card">
            <span>Utvägt</span>
            <strong>{tonnes.format(report.outgoing_tonnes)} ton</strong>
            <small>{count.format(report.outgoing_count)} vägningar</small>
          </article>
          <article className="metric-card">
            <span>Vägningar totalt</span>
            <strong>{count.format(report.count)}</strong>
            <small>Fördelat på {count.format(report.days)} vägningsdagar</small>
          </article>
        </div>
        <details className="monthly-values">
          <summary>Visa lagerplatser och material</summary>
          {report.locations.map(location => <details key={location.location ?? ''}>
            <summary>
              <strong>{location.location ?? 'Lagerplats saknas'}</strong>{' · '}
              {tonnes.format(location.incoming_tonnes)} ton in · {tonnes.format(location.outgoing_tonnes)} ton ut
            </summary>
            <div className="table-wrap">
              <table aria-label={location.location ?? 'Vägningar utan lagerplats'}>
                <thead><tr><th>Material</th><th>Ton in</th><th>Ton ut</th><th>Vägningar in</th><th>Vägningar ut</th></tr></thead>
                <tbody>{location.materials.map(material => <tr key={material.material ?? ''}>
                  <td>{material.material ?? 'Material saknas'}</td>
                  <td>{tonnes.format(material.incoming_tonnes)}</td>
                  <td>{tonnes.format(material.outgoing_tonnes)}</td>
                  <td>{count.format(material.incoming_count)}</td>
                  <td>{count.format(material.outgoing_count)}</td>
                </tr>)}</tbody>
              </table>
            </div>
          </details>)}
        </details>
      </>}
  </section>;
}
