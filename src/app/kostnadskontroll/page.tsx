import { createClient } from "@/lib/supabase/server";
export const dynamic = "force-dynamic";

export default async function CostReviewPage() {
  const supabase = await createClient();
  const { data: batches, error: batchError } = await supabase
    .from("kpi_import_batches")
    .select("id,status,source_type,file_name")
    .in("status", ["completed", "failed", "needs_review"])
    .limit(500);
  const relevant = (batches ?? []).filter(b => b.source_type === "manual_excel");
  const ids = relevant.map(b => b.id);
  const { data: rows, error: rowError } = ids.length
    ? await supabase.from("kpi_import_rows")
        .select("id,batch_id,project_reference,occurred_on,amount,source_data")
        .in("batch_id", ids)
        .in("project_reference", ["227", "243", "9900"])
        .limit(2000)
    : { data: [], error: null };
  const status = new Map(relevant.map(b => [b.id, b.status]));
  const totals = new Map<string, { rows: number; amount: number }>();
  for (const r of rows ?? []) {
    const s = status.get(r.batch_id) ?? "unknown";
    const t = totals.get(s) ?? { rows: 0, amount: 0 };
    t.rows += 1;
    t.amount += Number(r.amount ?? 0);
    totals.set(s, t);
  }
  const fmt = (n: number) => new Intl.NumberFormat("sv-SE", { style: "currency", currency: "SEK" }).format(n);
  return <><header className="topbar"><div><span className="eyebrow">HUMLA HUB · READ ONLY</span><h1>Kostnadskontroll</h1><p>Kontroll av Next-importer för projekt 227, 243 och 9900. Ingen kostnad fördelas eller bokförs från denna vy.</p></div></header>
    {batchError || rowError ? <section className="card"><h2>Data kunde inte hämtas</h2><p>{batchError?.message ?? rowError?.message}</p></section> : <>
      <section className="stats">{["completed", "failed", "needs_review"].map(s => <article className="card" key={s}><b>{totals.get(s)?.rows ?? 0}</b><strong>{s}</strong><small>{fmt(totals.get(s)?.amount ?? 0)}</small></article>)}</section>
      <section className="section"><h2>Importunderlag för granskning</h2><p>Identiska belopp eller verifikationsnummer är inte ensamma bevis för dubbelimport. Granska ursprungsrader innan aktivering.</p>
      <table><thead><tr><th>Projekt</th><th>Datum</th><th>Verifikation</th><th>Importstatus</th><th>Belopp</th></tr></thead><tbody>
      {(rows ?? []).slice(0,150).map(r => { const source = r.source_data as Record<string, unknown> | null; return <tr key={r.id}><td>{r.project_reference}</td><td>{r.occurred_on}</td><td>{String(source?.["Verifikation nr"] ?? "Saknas")}</td><td>{status.get(r.batch_id) ?? "unknown"}</td><td>{fmt(Number(r.amount ?? 0))}</td></tr>; })}
      </tbody></table></section>
    </>}
  </>;
}
