import Link from 'next/link';
import { KpiDetailShell } from '@/app/_components/kpi-detail-shell';
import { reviewAccess, reviewPage } from '@/lib/hub/review-access';

export const dynamic='force-dynamic';
const pageSize=50;
const number=new Intl.NumberFormat('sv-SE',{maximumFractionDigits:4});
const importPath='/kpi?view=import#next-artikelimport';
const history='/kpi?view=importhistorik&history_kind=next_articles';
function span(min:number|null,max:number|null){
  if(min===null)return '–';
  return max===null||max===min?number.format(min):`${number.format(min)} – ${number.format(max)}`;
}

export default async function NextArticles({searchParams}:{searchParams:Promise<{q?:string;page?:string}>}) {
  const access=await reviewAccess();
  const allowed=access&&await access.db.rpc('hub_has_permission',{p_tenant_id:access.tenantId,p_permission:'kpi.manage'});
  if(!access||allowed?.data!==true)return <main className="content"><h1>Åtkomst saknas</h1></main>;

  const params=await searchParams;
  const page=reviewPage(typeof params.page==='string'?params.page:undefined);
  const q=typeof params.q==='string'?params.q.trim().slice(0,100):'';
  const pattern=`%${q.replace(/[\\%_]/g,char=>'\\'+char)}%`;
  const query=access.db.from('kpi_next_article_register')
    .select('code,name,unit,account,price_list,min_price,max_price,min_cost,max_cost,last_performed_on,source_rows')
    .eq('tenant_id',access.tenantId);
  if(q)query.or(`code.ilike.${JSON.stringify(pattern)},name.ilike.${JSON.stringify(pattern)},price_list.ilike.${JSON.stringify(pattern)}`);
  const {data,error}=await query.order('code').order('name').order('unit').order('account').order('price_list')
    .range(page*pageSize,page*pageSize+pageSize);
  const href=(p:number)=>`/kpi/next-artiklar?${new URLSearchParams({q,page:String(p)})}`;
  return <KpiDetailShell query="" title="NeXT-artiklar" breadcrumb="Humla Dashboard / Administration / NeXT-artiklar">
    <div className="content"><section className="panel">
      <div className="panel-head"><h2>Artiklar från resursuppföljningen</h2><div><Link className="primary" prefetch={false} href={importPath}>Importera Excel</Link>{' '}<Link className="secondary" prefetch={false} href={history}>Importhistorik</Link></div></div>
      <p>Pris och kostnad per enhet visar observerade värden i den senast utförda periodens import för respektive artikelvariant.</p>
      <form method="get"><label>Sök kod, benämning eller prislista <input name="q" type="search" defaultValue={q} maxLength={100}/></label>{' '}<button className="secondary" type="submit">Sök</button></form>
      {error?<p role="alert">Artikelregistret kunde inte hämtas.</p>:!data?.length?<p>{q?'Inga artiklar matchar sökningen.':'Inga NeXT-artiklar finns i detta urval.'}</p>:
        <div className="table-wrap"><table className="data-table">
          <thead><tr><th scope="col">Kod</th><th scope="col">Benämning</th><th scope="col">Enhet</th><th scope="col">Konto</th><th scope="col">Prislista</th><th scope="col">Pris/enh</th><th scope="col">Kostnad/enh</th><th scope="col">Senast utförd</th><th scope="col">Källrader</th></tr></thead>
          <tbody>{data.slice(0,pageSize).map(a=><tr key={JSON.stringify([a.code,a.name,a.unit,a.account,a.price_list])}>
            <td>{a.code}</td><td>{a.name}</td><td>{a.unit||'–'}</td><td>{a.account||'–'}</td><td>{a.price_list||'–'}</td>
            <td>{span(a.min_price,a.max_price)}</td><td>{span(a.min_cost,a.max_cost)}</td><td>{a.last_performed_on??'–'}</td><td>{number.format(a.source_rows)}</td>
          </tr>)}</tbody>
        </table></div>}
      <nav aria-label="Sidor i NeXT-artikelregistret">
        {page>0&&<Link className="secondary" prefetch={false} href={href(page-1)}>Föregående</Link>}{' '}
        {!!data&&data.length>pageSize&&page<100000&&<Link className="secondary" prefetch={false} href={href(page+1)}>Nästa</Link>}
      </nav>
    </section></div>
  </KpiDetailShell>;
}
