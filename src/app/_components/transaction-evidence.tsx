import type {Analysis} from '@/lib/kpi/analysis';
type Transaction=Analysis['transactions'][number];
const categories:Record<string,string>={personnel:'Personal',fuel:'Bränsle',service_repair:'Service & reparation',depreciation:'Avskrivning',fixed:'Fasta kostnader',material:'Material',tipp_deponi:'Tipp / deponi',hired:'Inhyrda',other:'Övrigt'};
function text(value:unknown){if(typeof value!=='string'&&typeof value!=='number')return null;const s=String(value).trim();return !s||['null','undefined','false','true','-','–'].includes(s.toLowerCase())?null:s;}
const key=(s:string)=>s.normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase().replace(/[^a-z0-9]/g,'');
export function transactionText(t:Transaction){
 const entries=t.original&&typeof t.original==='object'&&!Array.isArray(t.original)?Object.entries(t.original):[];
 function field(...names:string[]){for(const name of names){const match=entries.find(([k])=>key(k)===key(name));const value=text(match?.[1]);if(value)return value;}return null;}
 const description=text(t.description);
 const detail=field('Artikelbeskrivning','Radtext','Verifikationsbeskrivning','Beskrivning','Description');
 const generic=!description||/^Intern(?:\s+AO)?\s+\d{4}[-/]\d{2}/i.test(description)||/^[0-9a-f]{8}-[0-9a-f-]{27,}$/i.test(description);
 const title=(generic?detail:description)??detail??description??(t.kind==='revenue'?'Intäkt':'Kostnad')+' · '+(categories[t.category]??t.category);
 const rows=[
 ['Arbete / projekt',field('AO/ATA-Benämning','Projektnamn','Projektbenämning','ProjectName')],
 ['Leverantör',field('Leverantör','Leverantörsnamn','SupplierName','Supplier')],
 ['Kund',field('Kund','Kundnamn','CustomerName','Customer')],
 ['Radbeskrivning',detail&&detail!==title?detail:null],
 ['Referens i underlaget',description&&description!==title?description:field('Verifikationstext')],
 ['Fakturanummer',field('Fakturanummer','Fakturanr','InvoiceNumber')],
 ['Ordernummer',field('Ordernummer','Ordernr','OrderNumber')],
 ['Enhet / fordon',t.unit_name??t.vehicle],
 ['Projekt',t.project],
 ['Bokföringskonto',t.account],
 ].filter((r):r is [string,string]=>Boolean(r[1]));
 return {title,rows};
}
export function TransactionEvidence({transaction:t}:{transaction:Transaction}){
 const {title,rows}=transactionText(t);
 const subtitle=rows.find(([label])=>label==='Leverantör'||label==='Kund'||label==='Arbete / projekt')?.[1];
 return <details id={`underlag-${t.fact_id}`} style={{minWidth:230,maxWidth:520,overflowWrap:'anywhere'}}>
 <summary style={{cursor:'pointer',lineHeight:1.5}}><strong>{title}</strong><span style={{display:'block',fontSize:12,color:'#64748b',marginTop:3}}>{t.occurred_on}{subtitle?' · '+subtitle:''}</span></summary>
 <div style={{padding:'12px 0'}}><dl style={{margin:0,display:'grid',gridTemplateColumns:'minmax(100px, 135px) minmax(0, 1fr)',gap:'7px 12px',fontSize:13}}>{rows.map(([label,value])=><div key={label} style={{display:'contents'}}><dt style={{color:'#64748b'}}>{label}</dt><dd style={{margin:0}}>{value}</dd></div>)}</dl>
 {!rows.length&&<p>Närmare beskrivning saknas i underlaget.</p>}
 <p style={{fontSize:12,color:'#64748b'}}>Källa: {t.source}{t.file_name?' · '+t.file_name:''}{t.row_number!=null?' · rad '+t.row_number:''}</p>
 <details><summary style={{cursor:'pointer',fontSize:12}}>Tekniskt originalunderlag</summary><p style={{fontSize:12}}>Transaktions-ID: {t.fact_id}</p><pre style={{whiteSpace:'pre-wrap',maxWidth:500,fontSize:11}}>{JSON.stringify(t.original,null,2)}</pre></details></div>
 </details>;
}
