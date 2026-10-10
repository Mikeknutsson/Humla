import type {AssetRegisterReport} from '@/lib/hub/asset-register';
const money=(n:unknown)=>typeof n==='number'?`${new Intl.NumberFormat('sv-SE',{maximumFractionDigits:0}).format(n)} kr`:'Saknas';
export function AssetRegisterEvidence({report,selectedId}:{report:AssetRegisterReport;selectedId:string|null}){
 const s=report.summary;
 return <section className="panel">
 <h2>Inköp och beräknad värdeminskning till {report.as_of}</h2>
 <p>{s.rows} tillgångsposter sparade i Hubben · {s.exact_links} entydiga fordonskopplingar · {s.active_acquisitions} separata inköp som inte är markerade sålda.</p>
 <p>Beräknat från inköpsdatum, linjärt ned till 0 kr över registrets avskrivningstid. Delar av år räknas efter antal dagar. Värdeminskning = inköpsbelopp × förflutna dagar / avskrivningstidens totala dagar, högst inköpsbeloppet. Kvarvarande värde = inköpsbelopp − värdeminskning.</p>
 <p>Detta är ett beräknat värde med registrets prisgrund, inte ett verifierat bokfört värde eller marknadsvärde. Momsgrund och framtida innehavsplan är inte fastställda. Beräkningen lägger inga nya kostnader eller avskrivningar i KPI-totalerna.</p>
 {!selectedId?<p>Öppna ett fordon nedan för inköpsunderlag och beräkning. {s.review_rows} poster är omatchade, tillbehör eller gemensamma inköp och behöver granskas.</p>:report.rows.length===0?<p>Inget entydigt kopplat inköpsunderlag för detta fordon i filen.</p>:<div className="table-wrap"><table>
 <thead><tr><th>Tillgång / benämning</th><th>Inköpsdatum</th><th>Inköpsbelopp</th><th>Avskrivningstid</th><th>Beräknad värdeminskning</th><th>Beräknat kvarvarande värde</th><th>Underlag / kontroll</th></tr></thead>
 <tbody>{report.rows.map(r=><tr key={r.source_key}>
 <td>{r.evidence.asset_number} · {r.evidence.description}<small style={{display:'block'}}>{r.source_key}</small></td>
 <td>{r.evidence.purchase_date??'Saknas'}</td><td>{money(r.evidence.purchase_cost)}</td><td>{r.evidence.useful_life_years??'Saknas'} år</td>
 <td>{r.projection.status==='calculated'?<>{money(r.projection.depreciation)}<small style={{display:'block'}}>{r.projection.depreciated_days} av {r.projection.total_days} dagar · {money(r.projection.monthly_rate)}/månad i snitt</small></>:'Ej beräknat'}</td>
 <td>{r.projection.status==='calculated'?<>{money(r.projection.remaining_value)}<small style={{display:'block'}}>{r.projection.fully_depreciated?'Fullt avskrivet enligt modellen':`Avskrivning slutar ${r.projection.end_date}`}</small></>:'Ej beräknat'}</td>
 <td>{r.sold?'Såld enligt källan':r.link_kind==='related'?'Tillbehör – inte fordonsinköp':r.link_kind==='bundle'?'Gemensamt inköp – fördelning saknas':'Separat inköpsunderlag'}<small style={{display:'block'}}>Registeravskrivning: {money(r.evidence.monthly_depreciation)}/månad. {r.projection.status!=='calculated'?r.projection.reason:''} {r.evidence.warnings}</small></td>
 </tr>)}</tbody></table></div>}
 </section>;
}
