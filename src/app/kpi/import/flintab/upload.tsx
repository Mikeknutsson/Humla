'use client';

import {useState} from 'react';
import {useRouter} from 'next/navigation';
import {yardNumber} from '@/lib/hub/sortergard-report';

type RowError = {row:number; message:string};
type Counts = {added:number;changed:number;unchanged:number};
export type ImportHistory = {id:string;filename:string;imported_at:string;errors:RowError[];summary:Counts};
type Preview = Counts & {sha:string;commit:boolean;count:number;errors:RowError[];sample:{id:string;date:string;material:string;tonnes:number}[];
  totals:Record<'in'|'out'|'external',number>;weights:Record<'in'|'out'|'external',number>};
const kinds = [['in','Inleveranser'],['out','Utleveranser'],['external','Externleveranser']] as const;

function Errors({errors}:{errors:RowError[]}) {
  return errors.length ? <details><summary>{errors.length} rader att granska</summary><ul>
    {errors.map(item=><li key={item.row}>Rad {item.row} · {item.message}</li>)}</ul></details> : null;
}

export default function FlintabUpload({history}:{history:ImportHistory[]|null}) {
  const [file,setFile]=useState<File>();
  const [preview,setPreview]=useState<Preview>();
  const [busy,setBusy]=useState(false);
  const [error,setError]=useState('');
  const router=useRouter();
  async function upload(selected:File,sha?:string) {
    setFile(selected);setBusy(true);setError('');
    if (!sha) setPreview(undefined);
    try {
      const form=new FormData();form.set('file',selected);if(sha) form.set('commit',sha);
      const response=await fetch('/api/kpi/flintab',{method:'POST',body:form});
      const data=await response.json();
      if(!response.ok) throw Error(data.error || 'Filen kunde inte behandlas.');
      setPreview(data);
      if(data.commit) router.refresh();
    } catch (err) {setError(err instanceof Error ? err.message : 'Filen kunde inte behandlas.');}
    finally {setBusy(false);}
  }
  return <>
    <section className="panel">
      <h2>Flintab Fordonsvåg</h2>
      <label style={{display:'block',padding:24,border:'2px dashed #6d8478',borderRadius:10}} onDragOver={e=>e.preventDefault()}
        onDrop={e=>{e.preventDefault();const dropped=e.dataTransfer.files[0];if(!busy&&dropped) void upload(dropped);}}>
        Dra Excel-filen hit eller välj en fil
        <input type="file" accept=".xlsx,.xls" disabled={busy} onChange={e=>{const picked=e.target.files?.[0];if(picked) void upload(picked);e.target.value='';}}/>
      </label>
      {busy&&<p role="status">Behandlar fil…</p>}
      {error&&<p role="alert">{error}</p>}
      {preview&&<>
        <h3>{preview.commit?'Importresultat':'Förhandsgranskning'} · {file?.name}</h3>
        <p>{preview.count} giltiga vägningar · {preview.added} nya · {preview.changed} ändrade · {preview.unchanged} oförändrade</p>
        <ul>{kinds.map(([key,label])=><li key={key}>{label} · {preview.totals[key]} vägningar · {yardNumber.format(preview.weights[key]/1000)} ton</li>)}</ul>
        <Errors errors={preview.errors}/>
        {!preview.commit&&file&&<>
          <div className="table-wrap"><table><thead><tr><th>TransId</th><th>Datum</th><th>Artikel</th><th>Ton</th></tr></thead>
            <tbody>{preview.sample.map(row=><tr key={row.id}><td>{row.id}</td><td>{row.date}</td><td>{row.material}</td><td>{yardNumber.format(row.tonnes)}</td></tr>)}</tbody></table></div>
          <button type="button" className="primary" disabled={busy} onClick={()=>void upload(file,preview.sha)}>Importera giltiga vägningar</button>
        </>}
      </>}
    </section>
    <section className="panel">
      <h2>Importhistorik</h2>
      {history===null ? <p>Importhistoriken kunde inte läsas.</p> : history.length===0 ? <p>Inga arkiverade Flintabfiler.</p> :
        <div className="table-wrap"><table><thead><tr><th>Datum</th><th>Originalfil</th><th>Nya</th><th>Ändrade</th><th>Oförändrade</th><th>Felaktiga rader</th></tr></thead>
          <tbody>{history.map(row=><tr key={row.id}><td>{new Date(row.imported_at).toLocaleString('sv-SE',{timeZone:'Europe/Stockholm'})}</td>
            <td><a href={`/api/kpi/flintab?id=${row.id}`}>{row.filename}</a></td><td>{row.summary.added}</td><td>{row.summary.changed}</td>
            <td>{row.summary.unchanged}</td><td><Errors errors={row.errors}/></td></tr>)}</tbody></table></div>}
    </section>
  </>;
}
