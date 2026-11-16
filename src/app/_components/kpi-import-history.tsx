import Link from 'next/link';
import type { createClient } from '@/lib/supabase/server';

const kinds: Record<string,string> = {
  revenue:'Intäkter',cost:'Kostnader',stena_history:'Stena · Historik',stena_settled:'Stena · Avräknat',
  next_projects:'NeXT · Projektregister',fuel:'Bränsle',vehicle_activity:'Fordonsaktivitet',driver_time:'Förartid',next_historical_time:'NeXT · Historisk tid',
};
const sourceNames: Record<string,string> = {stena_portal:'Stena',workify_file:'Workify',next_file:'NeXT',next:'NeXT',next_cost_file:'NeXT',next_revenue_file:'NeXT'};
const statusNames: Record<string,string> = {completed:'Sparad',needs_review:'Sparad – kontrollera rader',failed:'Misslyckad',processing:'Bearbetning påbörjad',incomplete:'Ofullständig'};
const time = new Intl.DateTimeFormat('sv-SE',{dateStyle:'short',timeStyle:'short',timeZone:'Europe/Stockholm'});
const count = new Intl.NumberFormat('sv-SE');

type Entry = {
  entry_id: string; file_name: string; kind: string; status: string; imported_at: string;
  period_start: string|null; period_end: string|null; row_count: number; review_rows: number; sources: string[];
};

type ApiRun={
  id:string;source:string;status:string;run_at:string;entities:string[]|null;fetched_count:number|null;
  upserted_count:number|null;period_start:string|null;period_end:string|null;latest_only:boolean;
};
const entityNames:Record<string,string>={projects:'Projekt',timeReports:'Tidrapporter',employees:'Anställda',vehicles:'Fordon',
  shifts:'Arbetspass',customers:'Kunder',suppliers:'Leverantörer',workorders:'Arbetsorder',supplierInvoices:'Leverantörsfakturor'};
const apiStatusNames:Record<string,string>={completed:'Klar',partial:'Delvis klar',running:'Pågår',failed:'Misslyckad',error:'Misslyckad'};

function periodLabel(start: string|null,end: string|null){
  if(start&&end) return start===end?start:`${start} – ${end}`;
  return start??end??'Datum saknas';
}

export async function KpiImportHistory({db,tenantId,query}:{
  db: Awaited<ReturnType<typeof createClient>>;
  tenantId: string;
  query: { kind?: string; page?: string; apiPage?: string };
}){
  const kind=query.kind==='stena'||(typeof query.kind==='string'&&Object.hasOwn(kinds,query.kind))?query.kind:'';
  const page=typeof query.page==='string'&&/^\d{1,5}$/.test(query.page)?Math.min(Number(query.page),10000):0;
  const apiPage=typeof query.apiPage==='string'&&/^\d{1,5}$/.test(query.apiPage)?Math.min(Number(query.apiPage),10000):0;
  const [{data,error},automatic]=await Promise.all([
    db.rpc('hub_kpi_import_history',{t:tenantId,p_kind:kind||null,p_page:page}),
    db.rpc('hub_kpi_api_import_history',{t:tenantId,p_page:apiPage}),
  ]);
  const history=data as {imports:Entry[];has_more:boolean}|null;
  const filters={view:'importhistorik',history_kind:kind};
  const url=(targetPage:number)=>`/kpi?${new URLSearchParams({...filters,history_page:String(targetPage),api_page:String(apiPage)})}#manuell-import`;
  const automaticUrl=(targetPage:number)=>`/kpi?${new URLSearchParams({...filters,history_page:String(page),api_page:String(targetPage)})}#automatiska-hamtningar`;
  const runs=automatic.data as {runs:ApiRun[];has_more:boolean}|null;

  return <>
  <section className="panel" id="manuell-import" aria-labelledby="manuell-import-title" style={{minWidth:0}}>
    <h2 id="manuell-import-title">Manuell import</h2>
    <Link className="secondary" href="/kpi?view=import" prefetch={false}>Gå till Dataimport</Link>
    {error||!history?<p role="alert">{error?.code==='42501'?'Du saknar behörighet att se importhistoriken.':'Importhistoriken kunde inte hämtas.'}</p>:
      <>
        <form method="get" action="/kpi#manuell-import">
          <input type="hidden" name="view" value="importhistorik"/>
          <input type="hidden" name="api_page" value={apiPage}/>
          <label>Underlag <select name="history_kind" defaultValue={kind}>
            <option value="">Alla underlag</option><option value="stena">Alla Stena-underlag</option>
            {Object.entries(kinds).map(([value,label])=><option key={value} value={value}>{label}</option>)}
          </select></label>{' '}<button className="secondary" type="submit">Visa</button>
        </form>
        {!history.imports.length?<p>Inga filimporter att visa för urvalet.</p>:<div className="table-wrap">
          <table className="data-table">
            <thead><tr><th scope="col">Fil</th><th scope="col">Underlag</th><th scope="col">Importtid</th><th scope="col">Datum i underlaget</th><th scope="col">Rader</th><th scope="col">Status</th></tr></thead>
            <tbody>{history.imports.map(entry=><tr key={entry.entry_id}>
              <th scope="row">{entry.file_name}</th>
              <td>{kinds[entry.kind]??entry.kind}{!entry.kind.startsWith('stena_')&&entry.sources.length>0&&<small style={{display:'block'}}>{entry.sources.map(source=>sourceNames[source]??source).join(', ')}</small>}</td>
              <td><time dateTime={entry.imported_at}>{time.format(new Date(entry.imported_at))}</time></td>
              <td>{entry.kind==='next_projects'?'Projektregister':periodLabel(entry.period_start,entry.period_end)}</td>
              <td>{count.format(entry.row_count)}</td>
              <td>{statusNames[entry.status]??entry.status}{entry.review_rows>0&&entry.status!=='failed'&&<small style={{display:'block'}}>{count.format(entry.review_rows)} {entry.kind.startsWith('stena_')?'utan pris':'rader att kontrollera'}</small>}</td>
            </tr>)}</tbody>
          </table>
        </div>}
        <nav aria-label="Sidor i importhistoriken">
          {page>0&&<Link prefetch={false} className="secondary" href={url(page-1)}>Nyare importer</Link>}{' '}
          {history.has_more&&page<10000&&<Link prefetch={false} className="secondary" href={url(page+1)}>Äldre importer</Link>}
        </nav>
      </>}
  </section>
  <section className="panel" id="automatiska-hamtningar" aria-labelledby="automatiska-hamtningar-title" style={{minWidth:0}}>
    <h2 id="automatiska-hamtningar-title">Automatiska API-hämtningar</h2>
    <p>För integrationer som bara sparar senaste körningen visas senast registrerade resultat.</p>
    {automatic.error||!runs?<p role="alert">API-historiken kunde inte hämtas.</p>:runs.runs.length===0?<p>Inga API-hämtningar att visa.</p>:<>
      <div className="table-wrap"><table className="data-table">
        <thead><tr><th scope="col">Integration</th><th scope="col">Underlag</th><th scope="col">Körningstid</th><th scope="col">Datum i underlaget</th><th scope="col">Hämtade / sparade</th><th scope="col">Status</th></tr></thead>
        <tbody>{runs.runs.map(run=><tr key={run.id}>
          <th scope="row">{run.source}{run.latest_only&&<small style={{display:'block'}}>Senaste körningen</small>}</th>
          <td>{run.entities?.map(item=>entityNames[item]??kinds[item]??item).join(', ')||'–'}</td>
          <td><time dateTime={run.run_at}>{time.format(new Date(run.run_at))}</time></td>
          <td>{run.period_start||run.period_end?periodLabel(run.period_start,run.period_end):'Period ej sparad'}</td>
          <td>{run.fetched_count==null?'–':count.format(run.fetched_count)} / {run.upserted_count==null?'–':count.format(run.upserted_count)}</td>
          <td>{apiStatusNames[run.status]??statusNames[run.status]??run.status}</td>
        </tr>)}</tbody>
      </table></div>
      <nav aria-label="Sidor i API-historiken">
        {apiPage>0&&<Link prefetch={false} className="secondary" href={automaticUrl(apiPage-1)}>Nyare hämtningar</Link>}{' '}
        {runs.has_more&&apiPage<10000&&<Link prefetch={false} className="secondary" href={automaticUrl(apiPage+1)}>Äldre hämtningar</Link>}
      </nav>
    </>}
  </section>
  </>;
}
