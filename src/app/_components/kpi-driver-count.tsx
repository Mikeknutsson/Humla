export type DriverCount = {
  count: number;
  transpa_count: number;
  exception_count: number;
  people: { name: string; source: 'TransPA' | 'Fordonsundantag'; vehicles: string[] }[];
};

export function KpiDriverCount({ data }: { data?: DriverCount | null }) {
  if (!data) return null;

  return <details className="panel">
    <summary><strong>{data.count} chaufförer</strong> · {data.transpa_count} med arbetstid i TransPA
      {data.exception_count > 0 && ` · ${data.exception_count} via fordonsundantag`}
    </summary>
    {data.people.length > 0 && <div className="table-wrap">
      <table>
        <thead><tr><th scope="col">Chaufför</th><th scope="col">Källa</th><th scope="col">Fordon för undantag</th></tr></thead>
        <tbody>{data.people.map(({ name, source, vehicles }, index) => <tr key={index}>
          <th scope="row">{name}</th><td>{source}</td><td>{vehicles.join(', ') || '–'}</td>
        </tr>)}</tbody>
      </table>
    </div>}
    <p>Underlaget är positiv registrerad arbetstid i TransPA och godkända fordonsundantag med bokförd chaufförsfaktura i urvalet. Varje person räknas en gång.</p>
  </details>;
}
