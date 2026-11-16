import Link from 'next/link';
import { redirect } from 'next/navigation';
import { createClient } from '@/lib/supabase/server';

export const dynamic = 'force-dynamic';

const kinds: Record<string,string> = {
  revenue:'Intäkter',cost:'Kostnader',stena_history:'Stena · Historik',stena_settled:'Stena · Avräknat',
  fuel:'Bränsle',vehicle_activity:'Fordonsaktivitet',driver_time:'Förartid',next_historical_time:'NeXT · Historisk tid',
};
const sourceNames: Record<string,string> = {stena_portal:'Stena',workify_file:'Workify',next_file:'NeXT',next:'NeXT',next_cost_file:'NeXT',next_revenue_file:'NeXT'};
const statusNames: Record<string,string> = {completed:'Sparad',needs_review:'Sparad – kontrollera rader',failed:'Misslyckad',processing:'Bearbetning påbörjad',incomplete:'Ofullständig'};
const time = new Intl.DateTimeFormat('sv-SE',{dateStyle:'short',timeStyle:'short',timeZone:'Europe/Stockholm'});
const count = new Intl.NumberFormat('sv-SE');

type Entry = {
  entry_id: string; file_name: string; kind: string; status: string; imported_at: string;
  period_start: string|null; period_end: string|null; row_count: number; review_rows: number; sources: string[];
};

function periodLabel(start: string|null,end: string|null){
  if(start&&end) return start===end?start:`${start} – ${end}`;
  return start??end??'Datum saknas';
}

export default async function ImportHistory({searchParams}:{searchParams:Promise<{kind?:string;page?:string}>}){
  const db=await createClient();
  const {data:{user}}=await db.auth.getUser();
  if(!user) redirect('/kpi/login');
  const {data:member}=await db.from('hub_tenant_members').select('tenant_id').eq('user_id',user.id).eq('status','active').limit(1).maybeSingle();
  if(!member) redirect('/kpi');

  const query=await searchParams;
  const kind=query.kind==='stena'||(typeof query.kind==='string'&&Object.hasOwn(kinds,query.kind))?query.kind:'';
  const page=typeof query.page==='string'&&/^\d{1,5}$/.test(query.page)?Math.min(Number(query.page),10000):0;
  const {data,error}=await db.rpc('hub_kpi_import_history',{t:member.tenant_id,p_kind:kind||null,p_page:page});
  const history=data as {imports:Entry[];has_more:boolean}|null;
  const url=(targetPage:number)=>`/kpi/importhistorik?${new URLSearchParams({kind,page:String(targetPage)})}`;

  return <main className="content">
    <header className="topbar"><div><h1>Importhistorik</h1><p>Filimporter i Humla, med den senaste först.</p></div>
      <Link prefetch={false} className="secondary" href="/kpi?view=import">Till Dataimport</Link>
    </header>
    {error||!history?<section className="panel" role="alert"><p>{error?.code==='42501'?'Du saknar behörighet att se importhistoriken.':'Importhistoriken kunde inte hämtas.'}</p></section>:
      <section className="panel">
        <form method="get" action="/kpi/importhistorik">
          <label>Underlag <select name="kind" defaultValue={kind}>
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
              <td>{periodLabel(entry.period_start,entry.period_end)}</td>
              <td>{count.format(entry.row_count)}</td>
              <td>{statusNames[entry.status]??entry.status}{entry.review_rows>0&&entry.status!=='failed'&&<small style={{display:'block'}}>{count.format(entry.review_rows)} {entry.kind.startsWith('stena_')?'utan pris':'rader att kontrollera'}</small>}</td>
            </tr>)}</tbody>
          </table>
        </div>}
        <nav aria-label="Sidor i importhistoriken">
          {page>0&&<Link prefetch={false} className="secondary" href={url(page-1)}>Nyare importer</Link>}{' '}
          {history.has_more&&page<10000&&<Link prefetch={false} className="secondary" href={url(page+1)}>Äldre importer</Link>}
        </nav>
      </section>}
  </main>;
}
