'use client';

import Link from 'next/link';
import {useState} from 'react';
import {requestImport} from '@/lib/kpi/import-request';
import type {NextArticlePreview} from '@/lib/kpi/next-article-file';

const count=new Intl.NumberFormat('sv-SE');
const history='/kpi?view=importhistorik&history_kind=next_articles';

export function NextArticleImport({initial,onBusyChange}:{initial?:{file:File;preview:NextArticlePreview};onBusyChange:(busy:boolean)=>void}) {
  const [file,setFile]=useState<File|null>(initial?.file??null);
  const [preview,setPreview]=useState<NextArticlePreview|null>(initial?.preview??null);
  const [busy,setBusy]=useState(false);
  const [message,setMessage]=useState('');
  const [error,setError]=useState('');

  async function run(mode:'preview'|'import') {
    if(!file||busy)return;
    setBusy(true);onBusyChange(true);setError('');setMessage('');
    if(mode==='preview')setPreview(null);
    const form=new FormData();
    form.set('file',file);form.set('mode',mode);
    try {
      const result=await requestImport('/api/kpi/next-articles',form,{readOnly:mode==='preview'});
      if(mode==='preview')setPreview(result);
      else {
        setPreview(null);
        setMessage(result.duplicate?'Filen finns redan i NeXT-artiklarnas importhistorik.':`${count.format(result.rows)} artikelvarianter behandlades.${result.skipped?` ${count.format(result.skipped)} rader hoppades över.`:''}`);
      }
    } catch(failure) {
      setError(failure instanceof Error?failure.message:'Artikelunderlaget kunde inte läsas.');
    } finally {
      setBusy(false);onBusyChange(false);
    }
  }

  return <section className="panel" id="next-artikelimport">
    <div className="panel-head"><h2>Importera artiklar från NeXT</h2><Link prefetch={false} className="secondary" href="/kpi/next-artiklar">Visa NeXT-artiklar</Link></div>
    {initial?<p>Identifierat som <strong>Arbetsorder – Resursuppföljning</strong> · {initial.file.name}</p>:
      <p>Välj Excel-exporten <strong>Arbetsorder – Resursuppföljning</strong>. Humla samlar återkommande rader från arbetsordrar i ett separat NeXT-register.</p>}
    <fieldset disabled={busy} style={{border:0,padding:0,minWidth:0}}>
      {!initial&&<><label>Resursuppföljning <input type="file" accept=".xlsx,.xls" onChange={event=>{
        setFile(event.target.files?.[0]??null);setPreview(null);setMessage('');setError('');
      }}/></label>{' '}
      <button type="button" className="secondary" disabled={!file} onClick={()=>void run('preview')}>Förhandsgranska</button></>}
      {preview&&<>
        <p>{count.format(preview.sourceRows)} källrader innehåller {count.format(preview.rows)} artikelvarianter.
          {preview.periodStart&&` Utfört ${preview.periodStart} – ${preview.periodEnd}.`}</p>
        {preview.skipped>0&&<p role="status">{count.format(preview.skipped)} rader med ofullständiga eller för långa artikeluppgifter hoppas över. {preview.skippedExamples.join(' · ')}</p>}
        <div className="table-wrap"><table className="data-table">
          <thead><tr><th scope="col">Kod</th><th scope="col">Benämning</th><th scope="col">Enhet</th><th scope="col">Prislista</th><th scope="col">Källrader</th></tr></thead>
          <tbody>{preview.preview.map((article,index)=><tr key={index}><td>{article.code}</td><td>{article.name}</td><td>{article.unit||'–'}</td><td>{article.price_list||'–'}</td><td>{count.format(article.source_rows)}</td></tr>)}</tbody>
        </table></div>
        <button type="button" className="primary" onClick={()=>void run('import')}>Importera {count.format(preview.rows)} artikelvarianter</button>
      </>}
    </fieldset>
    {busy&&<p role="status">Bearbetar resursuppföljningen …</p>}
    {error&&<p role="alert">{error}</p>}
    {message&&<p role="status">{message} <Link prefetch={false} href={history}>Visa importhistorik</Link></p>}
  </section>;
}
