import type {MarketDiscovery} from '@/lib/hub/market-discovery';
export function MarketDiscoveryPanel({plan}:{plan:MarketDiscovery}){
 return <section className="panel"><div className="panel-head"><h2>Hitta marknadsunderlag på nätet</h2><span>{plan.sources.length} relevanta källor</span></div>
 <p>Sökplan från fordonsuppgifterna i Hubben: <strong>{plan.query||'Fabrikat och modell saknas'}</strong>. Sökningar öppnas på Google, avgränsade till respektive källa. Inga priser hämtas eller sparas automatiskt.</p>
 {plan.missing.length>0&&<p>Komplettera för bättre träffar: {plan.missing.join(', ')}. Osäker fordonstyp visar alla källor.</p>}
 <div className="table-wrap"><table><thead><tr><th>Källa</th><th>Prisunderlag att kontrollera</th><th>Sökning</th></tr></thead><tbody>{plan.sources.map(s=><tr key={s.name}><td><a href={s.url} target="_blank" rel="noopener noreferrer">{s.name}</a></td><td>{s.basis}</td><td>{plan.query?<><a href={s.broad_url} target="_blank" rel="noopener noreferrer">Sök modell</a>{s.precise_url&&<> · <a href={s.precise_url} target="_blank" rel="noopener noreferrer">Sök årsmodell / utförande</a></>}</>:<>Komplettera fabrikat/modell eller öppna källan.</>}</td></tr>)}</tbody></table></div>
 <details><summary>Kontroller innan ett pris får påverka värderingen</summary><ul>{plan.checks.map(c=><li key={c}>{c}</li>)}</ul></details>
 <p>Spara kontrollerade träffar under ”Lägg till jämförelseobjekt”. Sökträffar är inte bekräftat jämförbara objekt. Fler källor förbättrar inte säkerheten om uppgifterna är gamla, dubblerade eller gäller fel utförande.</p>
 <p>Automatisk insamling är inte ansluten. Blocket ingår inte i denna sökplan; systematisk insamling där kräver skriftligt tillstånd.</p></section>;
}
