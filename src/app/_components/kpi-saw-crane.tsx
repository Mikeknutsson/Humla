import type {TransportScorecard} from '@/lib/kpi/transport-leader';

const money=new Intl.NumberFormat('sv-SE',{style:'currency',currency:'SEK',maximumFractionDigits:0});
const hours=new Intl.NumberFormat('sv-SE',{maximumFractionDigits:1});
const articlePattern=/(?:^|\\D)12[- ]?04(?:\\D|$)/i;
function articleEvidence(original:Record<string,unknown>):string|null {
 const keys=['article_code','article_number','article_no','article','articleName','article_name','artikelnummer','artikel','item_code','item_number','description'];
 for(const key of keys){const value=original[key];if(typeof value==='string'&&articlePattern.test(value))return key+': '+value;}
 return null;
}
export function SawCranePreview({report,unitSelected}:{report:TransportScorecard;unitSelected:boolean}){
 const matches=report.transactions.map(t=>({t,evidence:articleEvidence(t.original)})).filter(x=>x.evidence);
 const unique=[...new Map(matches.map(x=>[x.t.fact_id,x])).values()];
 const revenue=unique.filter(x=>x.t.kind==='revenue').reduce((sum,x)=>sum+x.t.amount,0);
 const cost=unique.filter(x=>x.t.kind==='cost').reduce((sum,x)=>sum+x.t.amount,0);
 return <section className="panel"><h2>12-04 – Kranbil med Såg</h2>
 <p>Första avstämning av artikel 12-04 mot originalrader i Transportledar-KPI. Detta är en kontrollvy, inte ett färdigt resultat: endast rader på den aktuella underlagssidan kan identifieras här. Fordonskostnader och TransPA-timmar behöver verifierad orderkoppling innan de får fördelas.</p>
 {!unitSelected?<p>Välj en ekonomisk enhet för att granska dess orderrader och identifiera sågkransuppdrag.</p>:<>
 <div className="metrics-grid"><article className="metric-card"><span>Identifierade artikelrader</span><strong>{unique.length}</strong></article><article className="metric-card"><span>Identifierad intäkt (delunderlag)</span><strong>{money.format(revenue)}</strong></article><article className="metric-card"><span>Direkt artikelmärkt kostnad (delunderlag)</span><strong>{money.format(cost)}</strong></article><article className="metric-card"><span>Arbetade timmar</span><strong>Ej verifierade</strong></article></div>
 <p>Observera: 0 identifierade rader betyder inte att uppdrag saknas. Övriga ordersidor, kostnader utan artikelkod och tidsrapporter omfattas inte av denna preliminära matchning.</p>
 {unique.length>0&&<div className="monthly-scroll"><table><thead><tr><th>Datum</th><th>Order</th><th>Kund</th><th>Typ</th><th>Belopp</th><th>Artikelbevis</th></tr></thead><tbody>{unique.map(({t,evidence})=><tr key={t.fact_id}><td>{t.occurred_on}</td><td>{t.order_number??'–'}</td><td>{t.customer??'–'}</td><td>{t.kind==='revenue'?'Intäkt':'Kostnad'}</td><td>{money.format(t.amount)}</td><td>{evidence}</td></tr>)}</tbody></table></div>}
 </>}</section>;
}
