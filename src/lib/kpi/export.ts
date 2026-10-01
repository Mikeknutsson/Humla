import * as XLSX from 'xlsx';
import {PDFDocument,StandardFonts,rgb} from 'pdf-lib';
import type {Analysis} from './analysis';
export function exportSheets(report:Analysis,context:Record<string,unknown>){
 return {
  'Vald vy':Object.entries({...context,...report.summary}).map(([fält,värde])=>({fält,värde:typeof värde==='object'?JSON.stringify(värde):värde})),
  'Objekt':report.groups,'Perioder':report.periods,
  'Transaktioner':report.transactions.map(t=>({...t,original:JSON.stringify(t.original),classification_source:JSON.stringify(t.classification_source??null)})),
 };
}
export function excelExport(report:Analysis,context:Record<string,unknown>){const book=XLSX.utils.book_new();for(const [name,rows]of Object.entries(exportSheets(report,context)))XLSX.utils.book_append_sheet(book,XLSX.utils.json_to_sheet(rows),name);return XLSX.write(book,{type:'buffer',bookType:'xlsx'}) as Buffer;}
export async function pdfExport(report:Analysis,context:Record<string,unknown>){
 const doc=await PDFDocument.create();const font=await doc.embedFont(StandardFonts.Helvetica);const bold=await doc.embedFont(StandardFonts.HelveticaBold);
 let page=doc.addPage([842,595]),y=550;const clean=(v:unknown)=>String(v??'–').replace(/[^\x20-\x7e\xa0-\xff]/g,'-');
 function line(text:string,heading=false){const content=clean(text);const words=content.split(/\s+/);let row='';for(const word of words){const candidate=row?row+' '+word:word;if(font.widthOfTextAtSize(candidate,heading?12:9)>740){draw(row,heading);row=word}else row=candidate}if(row)draw(row,heading);}
 function draw(text:string,heading:boolean){if(y<42){page=doc.addPage([842,595]);y=550}page.drawText(text,{x:42,y,size:heading?12:9,font:heading?bold:font,color:rgb(.12,.16,.2)});y-=heading?22:15;}
 const money=(v:unknown)=>new Intl.NumberFormat('sv-SE',{minimumFractionDigits:2,maximumFractionDigits:2}).format(Number(v??0))+' kr';
 line('Humla KPI - vald vy',true);for(const[k,v]of Object.entries(context))line(`${k}: ${typeof v==='object'?JSON.stringify(v):v}`);
 line(`Omsättning: ${money(report.summary.revenue)} | Kostnad: ${money(report.summary.cost)} | Resultat: ${money(report.summary.result)} | Marginal: ${report.summary.margin_pct??'-'} %`);
 line('Ekonomiska objekt',true);for(const g of report.groups)line(`${g.label} | Intäkt ${money(g.revenue)} | Kostnad ${money(g.cost)} | Resultat ${money(g.result)} | ${g.rows} rader`);
 line('Perioder',true);for(const p of report.periods)line(`${p.period_start} - ${p.period_end} | Intäkt ${money(p.revenue)} | Kostnad ${money(p.cost)} | Resultat ${money(p.result)}`);
 line('Transaktioner och källreferenser',true);for(const t of report.transactions){line(`${t.occurred_on} | ${t.source} | ${t.unit_name??t.vehicle??'Ej fördelat'} | Kostnadsställe ${t.cost_center??'-'} | Projekt ${t.project??'-'} | Konto ${t.account??'-'} | ${t.category} | ${t.kind} | ${money(t.amount)}`);line(`${t.description??''} | ${t.file_name??t.source} | rad ${t.row_number??'-'} | ID ${t.fact_id}`)}
 for(const [i,p]of doc.getPages().entries())p.drawText(`Humla Hub | Sida ${i+1} / ${doc.getPageCount()}`,{x:42,y:20,size:8,font});
 return await doc.save();
}
