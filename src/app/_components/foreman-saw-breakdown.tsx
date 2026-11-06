export type SawBreakdown={revenue:number;cost:number;management_cost:number;other_cost:number;truck_charge:number;material_revenue:number;material_tons:number;material_rate:number;material_rows:{id:string;date:string;tons:number;amount:number;source:string;ticket:string|null;order:string|null}[]};
const money=new Intl.NumberFormat('sv-SE',{style:'currency',currency:'SEK',maximumFractionDigits:0});
const number=new Intl.NumberFormat('sv-SE',{maximumFractionDigits:2});
export function ForemanSawBreakdown({value}:{value?:SawBreakdown|null}){
 if(!value)return null;
 const cards=[
 ['Såguppdrag före lastbilsavdrag',value.revenue-value.material_revenue+value.truck_charge],
 ['Kostnad lastbil – avräknad',value.truck_charge],
 ['Intäkt Grot/Stock',value.material_revenue],
 ['Kostnader Arbetsledning',value.management_cost],
 ['Övriga kostnader inkl. overhead',value.other_cost],
 ['Kostnader totalt',value.cost],
 ] as const;
 return <section className="panel" aria-label="Sågningens intäkter och kostnader"><h2>Sågningen – intäkter och kostnader</h2>
 <div className="metrics-grid">{cards.map(([label,amount])=><article className="metric-card" key={label}><span>{label}</span><strong>{money.format(amount)}</strong></article>)}</div>
 <p>Lastbilens ersättning är redan avräknad från intäkten i sammanställningen ovan. Arbetsledning och övriga kostnader ingår i kostnader totalt.</p>
 <p>Grot/Stock: {number.format(value.material_tons)} ton × {money.format(value.material_rate)}/ton = {money.format(value.material_revenue)}. Materialvärdet ingår i intäkt och resultat. Det är ett beräknat värde på mottaget material.</p>
 <details><summary>Visa registrerat Grot/Stock</summary>{value.material_rows.length?<div className="monthly-scroll"><table><thead><tr><th>Datum</th><th>Underlag</th><th>Ton</th><th>Intäkt</th></tr></thead><tbody>{value.material_rows.map(r=><tr key={r.id}><td>{r.date}</td><td>{r.source}{r.ticket?' · Våg '+r.ticket:''}{r.order?' · Order '+r.order:''}</td><td>{number.format(r.tons)}</td><td>{money.format(r.amount)}</td></tr>)}</tbody></table></div>:<p>Inga registrerade mängder med verifierad koppling till Sågningen i perioden.</p>}</details></section>;
}
