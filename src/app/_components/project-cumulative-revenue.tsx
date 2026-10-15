import {createClient} from '@/lib/supabase/server';
const money=(n:number)=>new Intl.NumberFormat('sv-SE',{style:'currency',currency:'SEK',maximumFractionDigits:2}).format(n);
export async function ProjectCumulativeRevenue({tenant,project}:{tenant:string;project:string}){
 const db=await createClient();
 const {data,error}=await db.rpc('hub_project_revenue_statement_v1',{p_tenant_id:tenant,p_project_id:project});
 if(error)return <section className="panel"><p>Projektets ackumulerade intäktsunderlag kunde inte hämtas. Periodrapporten nedan påverkas inte.</p></section>;
 if(!data)return null;
 const s=data as {observed_on:string;billed_total:number;imported_next_revenue:number;unperiodized_difference:number;basis:string;source:{label?:string}};
 return <section className="panel" aria-label="Ackumulerad fakturerad projektintäkt"><span className="section-kicker">Hela projektet · exkl. moms</span><h2>Fakturerat totalt: {money(s.billed_total)}</h2><p>{s.source.label??'NeXT-projektsammanställning'} · avläst {s.observed_on}</p><p>{s.basis}</p><p>Redan importerad NeXT-intäkt: <strong>{money(s.imported_next_revenue)}</strong>. Differens att periodfördela: <strong>{money(s.unperiodized_difference)}</strong>.</p></section>;
}
