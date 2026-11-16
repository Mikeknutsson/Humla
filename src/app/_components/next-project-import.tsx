'use client';

import Link from 'next/link';
import {useState} from 'react';
import {requestImport} from '@/lib/kpi/import-request';

type Project = {project_number:string;project_name:string;cost_center:string;source_business_groups:string};
type CostCenterWarnings = {count:number;rows:number[]};
type Preview = {rows:number;preview:Project[];warnings?:CostCenterWarnings};

export function NextProjectImport(){
  const [file,setFile]=useState<File|null>(null);
  const [preview,setPreview]=useState<Preview|null>(null);
  const [busy,setBusy]=useState(false);
  const [message,setMessage]=useState('');
  const [error,setError]=useState('');

  async function run(mode:'preview'|'import'){
    if(!file||busy)return;
    setBusy(true);setError('');setMessage('');
    const form=new FormData();
    form.set('file',file);form.set('mode',mode);
    try {
      const result=await requestImport('/api/kpi/next-projects',form,{readOnly:mode==='preview'});
      if(mode==='preview')setPreview(result);
      else {
        setPreview(null);
        const warning=result.warnings?.count? ` Kostnadsstället lämnades orört på ${result.warnings.count} projektrader med ogiltigt nummer.`:'';
        setMessage(result.duplicate?'Filen finns redan i importhistoriken.':`${result.rows} projekt har lästs in i projektregistret.${warning}`);
      }
    } catch (failure) {
      setError(failure instanceof Error?failure.message:'Projektfilen kunde inte läsas.');
    } finally {
      setBusy(false);
    }
  }
  return <section className="panel">
    <h2>Importera projekt från NeXT</h2>
    <p>Välj Excel-exporten Projektöversikt från NeXT. Befintliga projekt uppdateras efter projektnummer. Projekt som saknas i filen behålls.</p>
    <fieldset disabled={busy} style={{border:0,padding:0,minWidth:0}}>
      <label>Projektöversikt <input type="file" accept=".xlsx,.xls" onChange={event=>{
        setFile(event.target.files?.[0]??null);setPreview(null);setMessage('');setError('');
      }}/></label>{' '}
      <button type="button" className="secondary" disabled={!file} onClick={()=>void run('preview')}>Förhandsgranska</button>
      {preview&&<>
        <p>{preview.rows} projekt hittades. Här visas de första {preview.preview.length}.</p>
        {!!preview.warnings?.count&&<p role="status">
          {preview.warnings.count===1?'En rad har ogiltigt kostnadsställenummer.':`${preview.warnings.count} rader har ogiltigt kostnadsställenummer.`}
          {' '}Excelrad{preview.warnings.rows.length===1?'':'er'} {preview.warnings.rows.join(', ')}{preview.warnings.count>preview.warnings.rows.length?', …':'.'}
          {' '}Projekten kan importeras. Befintliga kostnadsställen behålls och nya projekt får inget kostnadsställe på dessa rader.
        </p>}
        <div className="table-wrap"><table className="data-table">
          <thead><tr><th scope="col">Projektnr</th><th scope="col">Projektnamn</th><th scope="col">Kostnadsställe</th><th scope="col">Verksamhetsgrupper i filen</th></tr></thead>
          <tbody>{preview.preview.map(project=><tr key={project.project_number}><td>{project.project_number}</td>
            <td>{project.project_name}</td><td>{project.cost_center||'–'}</td><td>{project.source_business_groups||'–'}</td></tr>)}</tbody>
        </table></div>
        <button type="button" className="primary" onClick={()=>void run('import')}>Importera {preview.rows} projekt</button>
      </>}
    </fieldset>
    {busy&&<p role="status">Bearbetar projektfilen…</p>}
    {error&&<p role="alert">{error}</p>}
    {message&&<p role="status">{message} <Link prefetch={false} href="/kpi?view=importhistorik&history_kind=next_projects">Visa projektimporter</Link></p>}
  </section>;
}
