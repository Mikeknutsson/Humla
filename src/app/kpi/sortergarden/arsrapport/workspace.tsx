'use client';

import Link from 'next/link';
import {GoogleAddressField} from '@/app/_components/google-address-field';
import {useMemo,useState} from 'react';
import {useRouter} from 'next/navigation';
import {reportAddress,statusLabels,yardMaterials,yardNumber,yardTotals,type Weighing,type ReportVersion} from '@/lib/hub/sortergard-report';
import {reviewYard,saveYardFacility} from './actions';
import styles from './workspace.module.css';
import YardAddressAssist,{assessYardAddress} from './yard-address-assist';
import {useGoogleMapsKey} from '@/app/_components/google-maps-provider';

const pageSize=35;
const url='/kpi/sortergarden/arsrapport';
type Results={reference:string;name:string;address:string}[];
const filtersDefault={from:'',to:'',stock:'',material:'',kind:'',party:'',reg:'',status:''};

export default function YardWorkspace({rows,year,latest,version,archive}:{
  rows:Weighing[];year:number;latest:number;version:ReportVersion|null;archive:ReportVersion[]|null;
}) {
  const router=useRouter();
  const mapsKey=useGoogleMapsKey();
  const [filters,setFilters]=useState(filtersDefault);
  const [page,setPage]=useState(0);
  const [selection,setSelection]=useState<string[]>([]);
  const [active,setActive]=useState<string>();
  const [origin,setOrigin]=useState('');
  const [destination,setDestination]=useState('');
  const [source,setSource]=useState('Next');
  const [search,setSearch]=useState('');
  const [sources,setSources]=useState<Results>();
  const [busy,setBusy]=useState(false);
  const [feedback,setFeedback]=useState('');
  const totals=useMemo(()=>yardTotals(rows),[rows]);
  const materials=useMemo(()=>yardMaterials(rows),[rows]);
  const filtered=rows.filter(row=>
    (!filters.from||row.day>=filters.from)&&(!filters.to||row.day<=filters.to)&&(!filters.stock||row.stock===filters.stock)
    &&(!filters.material||row.material===filters.material)&&(!filters.kind||row.kind===filters.kind)
    &&(!filters.status||(filters.status==='unverified'?row.status!=='verified':row.status===filters.status))
    &&(!filters.reg||row.reg?.includes(filters.reg.toUpperCase().replace(/[^A-Z0-9]/g,'')))
    &&(!filters.party||[row.sender,row.recipient].some(label=>label?.toLocaleLowerCase('sv-SE').includes(filters.party.toLocaleLowerCase('sv-SE')))));
  const displayed=filtered.slice(page*pageSize,(page+1)*pageSize);
  const chosen=rows.filter(row=>selection.includes(row.id));
  const detail=rows.find(row=>row.id===active);
  const exportUrl=(format:string,id?:string)=>`${url}/export?year=${year}&format=${format}${id?`&version=${id}`:''}`;
  const ready=rows.length?totals.verified/rows.length:0;
  function change<K extends keyof typeof filtersDefault>(key:K,value:string) {
    setFilters(v=>({...v,[key]:value}));setPage(0);setSelection([]);
  }
  async function run(action:Parameters<typeof reviewYard>[1],args:object={},success='Åtgärden är sparad.') {
    setBusy(true);setFeedback('');
    try {
      const response=await reviewYard(year,action,args);
      if(response.error) {setFeedback(response.error);return;}
      if(action==='search') {setSources(response.data);return;}
      if(action==='match') setFeedback(`${response.data.processed} behandlade · ${response.data.likely} sannolika · ${response.data.missing} saknade adresser.`);
      else setFeedback(success);
      setSelection([]);setPage(0);router.refresh();
    } catch {setFeedback('Åtgärden kunde inte slutföras. Försök igen.');}
    finally {setBusy(false);}
  }
  async function saveFacility(row:Weighing,side:'origin'|'destination',address:string) {
    setBusy(true);setFeedback('');
    try {
      const response=await saveYardFacility(year,row.id,side,address);
      setFeedback(response.error??'Anläggningsadressen används som reserv för den här Flintabkunden.');
      if(response.saved) router.refresh();
    } catch {setFeedback('Anläggningsadressen kunde inte sparas.');}
    finally {setBusy(false);}
  }

  async function assessSelection() {
    setBusy(true);setFeedback('');
    let saved=0,failed=0;
    try {
      for(let start=0;start<chosen.length;start+=3) {
        const batch=await Promise.allSettled(chosen.slice(start,start+3).map(row=>assessYardAddress(year,row.id,row.kind,mapsKey)));
        saved+=batch.filter(result=>result.status==='fulfilled'&&result.value.saved).length;
        failed+=batch.filter(result=>result.status==='rejected').length;
      }
      setFeedback(`${saved} sannolika adresser används. ${chosen.length-saved-failed} rader fick ingen ändring.${failed?` ${failed} sökningar misslyckades.`:''}`);
      router.refresh();
    } finally {setBusy(false);}
  }

  function approve(entries:{id:string;candidate:number;expectedAddress:string}[]) {
    void run('review',{mode:'approve',items:entries},'Adresserna är verifierade och låsta.');
  }
  function open(row:Weighing) {
    setActive(row.id);setSources(undefined);setSearch('');setOrigin(row.origin);setDestination(row.destination);
  }
  return <>
    <section className="panel">
      <h2>{year} · Pukavik 3:4</h2>
      <div className={styles.actions}>
        <label>Rapportår <select value={year} onChange={e=>router.push(`${url}?year=${e.target.value}`)}>
          {Array.from({length:latest-2025},(_,i)=>latest-i).map(value=><option key={value}>{value}</option>)}
        </select></label>
        {version&&<Link href={`?year=${year}`}>Till aktuell rapport</Link>}
        <a href={exportUrl('xlsx',version?.id)}>Exportera Excel</a>
        <a href={exportUrl('pdf',version?.id)}>Exportera PDF</a>
      </div>
      {version&&<p><strong>Låst version {version.version}</strong> · {version.incomplete?'Ofullständig':'Alla adresser verifierade'}</p>}
      <div className="metrics-grid">{[
        ['Vägningar',rows.length],['Inlevererat (ton)',totals.in],['Utlevererat (ton)',totals.out],['Externleveranser (ton)',totals.external],
        ['Verifierade',totals.verified],['Sannolika',totals.likely],['Anläggningsadress (reserv)',totals.fallback],['Adress saknas',totals.missing],['Obehandlade',totals.pending],
      ].map(([label,count])=><div className="metric-card" key={label}><span>{label}</span><strong>{yardNumber.format(Number(count))}</strong></div>)}
      <div className="metric-card"><span>Färdigbehandlade</span><strong>{new Intl.NumberFormat('sv-SE',{style:'percent',maximumFractionDigits:1}).format(ready)}</strong></div></div>
      {!version&&<div className={styles.actions}>
        <button disabled={busy||!rows.length} onClick={()=>void run('match')}>Matcha adresser</button>
        <button disabled={busy||!totals.pending} onClick={()=>void run('match',{pending:true})}>Matcha endast obehandlade</button>
        <button onClick={()=>change('status','unverified')}>Granska avvikelser</button>
        <button disabled={busy||!rows.length} onClick={()=>void run('finalize',{},'En låst version sparades i rapportarkivet.')}>
          {ready===1?'Färdigställ årsrapport':'Färdigställ som ofullständig'}
        </button>
      </div>}
      {feedback&&<p role="status">{feedback}</p>}
    </section>
    <section className="panel">
      <h2>Vägningar</h2>
      <div className={styles.filters}>
        {([['from','Från','date'],['to','Till','date'],['party','Kund, avsändare eller mottagare','search'],['reg','Registreringsnummer','search']] as const)
          .map(([key,label,type])=><label key={key}>{label}<input type={type} value={filters[key]} onChange={e=>change(key,e.target.value)}/></label>)}
        {([['stock','Lagerplats'],['material','Material'],['kind','Leveranstyp']] as const).map(([key,label])=><label key={key}>{label}
          <select value={filters[key]} onChange={e=>change(key,e.target.value)}><option value="">Alla</option>
            {[...new Set(rows.map(row=>row[key]).filter(Boolean))].sort((a,b)=>a!.localeCompare(b!,'sv')).map(value=><option key={value}>{value}</option>)}
          </select></label>)}
        <label>Matchningsstatus<select value={filters.status} onChange={e=>change('status',e.target.value)}>
          <option value="">Alla</option><option value="unverified">Alla avvikelser</option>
          {Object.entries(statusLabels).map(([value,label])=><option value={value} key={value}>{label}</option>)}
        </select></label>
      </div>
      <p className={styles.filterNote}>{filtered.length} vägningar i urvalet{chosen.length?` · ${chosen.length} markerade`:''}</p>
      {!version&&chosen.length>0&&<details className={styles.detail}><summary>Åtgärda markerade vägningar</summary>
        <div className={styles.actions}>
          <button disabled={busy||chosen.length>20} onClick={()=>void assessSelection()}>Bedöm markerade med Google (max 20)</button>
          <button disabled={busy||chosen.some(row=>row.status!=='likely'||row.candidates.length!==1)}
            onClick={()=>approve(chosen.map(row=>({id:row.id,candidate:0,expectedAddress:row.candidates[0].address})))}>Massgodkänn entydiga förslag</button>
          <label>Ursprungsadress <input maxLength={240} value={origin} onChange={e=>setOrigin(e.target.value)}/></label>
          <label>Leveransadress <input maxLength={240} value={destination} onChange={e=>setDestination(e.target.value)}/></label>
          <button disabled={busy||chosen.some(row=>row.status==='verified')} onClick={()=>void run('review',{mode:'manual',origin,destination,items:chosen.map(row=>({id:row.id}))})}>Tilldela adress till markerade</button>
        </div>
      </details>}
      <div className="table-wrap"><table><thead><tr>{!version&&<th>Välj</th>}<th>TransId</th><th>Datum / reg.nr</th><th>Avsändare / mottagare</th>
        <th>Ursprungs-/leveransadress</th><th>Artikel / lagerplats</th><th>Ton</th><th>Leveranstyp</th><th>Status</th></tr></thead>
        <tbody>{displayed.map(row=><tr key={row.id}>
          {!version&&<td><input type="checkbox" aria-label={`Markera ${row.trans_id}`} checked={selection.includes(row.id)}
            disabled={row.status==='verified'||(selection.length>=150&&!selection.includes(row.id))}
            onChange={e=>setSelection(old=>e.target.checked?[...old,row.id]:old.filter(id=>id!==row.id))}/></td>}
          <td><button onClick={()=>open(row)}>{row.trans_id}</button></td><td>{row.day}<br/>{row.reg}</td>
          <td>{row.sender}<br/>{row.recipient}</td><td>{reportAddress(row)||'–'}</td>
          <td>{row.material}<br/>{row.stock}</td><td>{yardNumber.format(row.tonnes)}</td><td>{row.kind}</td>
          <td><span className={`${styles.badge} ${styles[row.status]}`}>{statusLabels[row.status]}</span></td>
        </tr>)}</tbody></table></div>
      <div className={styles.actions}>
        <button disabled={!page} onClick={()=>setPage(p=>p-1)}>Föregående</button>
        <span>Sida {page+1} av {Math.max(1,Math.ceil(filtered.length/pageSize))}</span>
        <button disabled={(page+1)*pageSize>=filtered.length} onClick={()=>setPage(p=>p+1)}>Nästa</button>
      </div>
      {detail&&<section className={styles.detail} aria-label={`Vägning ${detail.trans_id}`}>
        <h3>Vägning {detail.trans_id}</h3>
        <button onClick={()=>setActive(undefined)}>Stäng vägning</button>
        <p>{statusLabels[detail.status]}{detail.confidence>0?` · ${detail.confidence}/100`:''} {detail.source} {detail.reason}</p>
        <details><summary>Originaluppgifter från Flintab</summary><dl>{Object.entries(detail.raw).map(([field,value])=>
          <div key={field} style={{display:'contents'}}><dt>{field}</dt><dd>{value==null?'–':String(value)}</dd></div>)}</dl></details>
        {detail.candidates.length>0&&<ul>{detail.candidates.map((candidate,index)=><li key={candidate.address}>
          <strong>{candidate.address}</strong> · {candidate.source} {candidate.reference} · {candidate.score}/100 · {candidate.reason}{' '}
          {!version&&detail.status==='likely'&&<button disabled={busy} onClick={()=>approve([{id:detail.id,candidate:index,expectedAddress:candidate.address}])}>Godkänn adress</button>}
        </li>)}</ul>}
        {!version&&<>
          <YardAddressAssist key={year+':'+detail.id} year={year} event={detail.id} kind={detail.kind}
            apply={(side,address)=>side==='origin'?setOrigin(address):setDestination(address)} onSaved={()=>router.refresh()}/>
          <div className={styles.filters}>
            <label>Sök arbetsorder eller projekt<select value={source} onChange={e=>setSource(e.target.value)}><option>Next</option><option>Workify</option></select></label>
            <label>Nummer eller namn<input value={search} onChange={e=>setSearch(e.target.value)} maxLength={100}/></label>
            <button disabled={busy||search.trim().length<2} onClick={()=>void run('search',{source,query:search})}>Sök adresser</button>
          </div>
          {sources&&<ul>{sources.length?sources.map((item,index)=><li key={index}>{item.reference} · {item.name} · {item.address}{' '}
            {detail.kind!=='Utleverans'&&<button onClick={()=>setOrigin(item.address)}>Använd som ursprung</button>}
            {detail.kind!=='Inleverans'&&<button onClick={()=>setDestination(item.address)}>Använd som destination</button>}
          </li>):<li>Inga arbetsplatsadresser matchade sökningen.</li>}</ul>}
          <div className={styles.addressReview} key={detail.id}>
            {detail.kind!=='Utleverans'&&<GoogleAddressField label="Ursprungsadress" value={origin} onChange={setOrigin}/>}
            {detail.kind!=='Inleverans'&&<GoogleAddressField label="Leveransadress" value={destination} onChange={setDestination}/>}
            <button disabled={busy} onClick={()=>void run('review',{mode:'manual',origin,destination,items:[{id:detail.id}]},'Adressen är verifierad och låst.')}>Verifiera och lås adress</button>
          </div>
          {(detail.status==='missing'||detail.status==='fallback')&&<div className={styles.actions}>
            {detail.kind!=='Utleverans'&&<button disabled={busy||!origin.trim()} onClick={()=>void saveFacility(detail,'origin',origin)}>Spara som avsändarens anläggningsadress</button>}
            {detail.kind!=='Inleverans'&&<button disabled={busy||!destination.trim()} onClick={()=>void saveFacility(detail,'destination',destination)}>Spara som mottagarens anläggningsadress</button>}
          </div>}
        </>}
      </section>}
    </section>
    <section className="panel">
      <h2>Material per lagerplats</h2>
      <div className="table-wrap"><table><thead><tr><th>Lagerplats</th><th>Material</th><th>In (ton)</th><th>Ut (ton)</th><th>Externt (ton)</th><th>Vägningar</th><th>Ej verifierade</th></tr></thead>
        <tbody>{materials.map(row=><tr key={JSON.stringify([row.stock,row.material])}>
          <td><button onClick={()=>change('stock',row.stock)}>{row.stock}</button></td>
          <td><button onClick={()=>change('material',row.material)}>{row.material}</button></td>
          {[row.in,row.out,row.external,row.count,row.unverified].map((n,i)=><td key={i}>{yardNumber.format(n)}</td>)}
        </tr>)}</tbody></table></div>
    </section>
    <section className="panel">
      <h2>Rapportarkiv {year}</h2>
      {archive===null?<p>Arkivet kunde inte hämtas.</p>:archive.length===0?<p>Inga färdigställda versioner ännu.</p>:
        <ul>{archive.map(item=><li key={item.id}>
          <Link href={`?year=${year}&version=${item.id}`}>Version {item.version}</Link> · {new Date(item.created_at).toLocaleString('sv-SE',{timeZone:'Europe/Stockholm'})} · {item.created_by_label} · {item.incomplete?'Ofullständig':'Alla adresser verifierade'}{' '}
          <a href={exportUrl('xlsx',item.id)}>Excel</a>{' '}<a href={exportUrl('pdf',item.id)}>PDF</a>
        </li>)}</ul>}
    </section>
  </>;
}
