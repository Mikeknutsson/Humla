import * as XLSX from 'xlsx';
import {PDFDocument,StandardFonts,rgb} from 'pdf-lib';
import {reportAddress,statusLabels,yardMaterials,yardNumber,yardTotals,type Weighing} from './sortergard-report';

export function yardExcel(rows:Weighing[],year:number,version?:number) {
  const workbook=XLSX.utils.book_new();
  const data=XLSX.utils.aoa_to_sheet([
    ['Transaktionsnummer','Datum','Lastbärare / Reg.nr','Avsändare','Mottagare','Ursprungs-/leveransadress','Artikel','Vikt i ton','Lagerplats','Leveranstyp','Adressstatus','Datakälla'],
    ...rows.map(row=>[row.trans_id,row.day,row.reg,row.sender,row.recipient,reportAddress(row),row.material,row.tonnes,row.stock,row.kind,statusLabels[row.status],row.source]),
  ]);
  data['!cols']=[18,14,20,25,25,52,32,14,20,18,18,22].map(wch=>({wch}));
  data['!autofilter']={ref:data['!ref']!};
  XLSX.utils.book_append_sheet(workbook,data,'Vägningar');
  const materials=yardMaterials(rows);
  XLSX.utils.book_append_sheet(workbook,XLSX.utils.aoa_to_sheet([
    ['Lagerplats','Artikel','Inleverans (ton)','Utleverans (ton)','Externleverans (ton)','Vägningar','Ej verifierade'],
    ...materials.map(r=>[r.stock,r.material,r.in,r.out,r.external,r.count,r.unverified]),
  ]),'Material');
  const totals=yardTotals(rows);
  XLSX.utils.book_append_sheet(workbook,XLSX.utils.aoa_to_sheet([
    ['Sortergården – Pukavik 3:4'],['Rapportår',year],['Version',version??'Aktuell arbetsversion'],
    ['Status',rows.length&&totals.verified===rows.length?'Alla adresser verifierade':'Ofullständig'],
    ['Inleverans (ton)',totals.in],['Utleverans (ton)',totals.out],['Externleverans (ton)',totals.external],
    ['Verifierade',totals.verified],['Sannolika',totals.likely],['Anläggningsadress (reserv)',totals.fallback],['Saknas',totals.missing],['Obehandlade',totals.pending],
  ]),'Rapportstatus');
  return Uint8Array.from(XLSX.write(workbook,{bookType:'xlsx',type:'buffer'}));
}

export async function yardPdf(rows:Weighing[],year:number,version?:number) {
  const pdf=await PDFDocument.create();
  const normal=await pdf.embedFont(StandardFonts.Helvetica);
  const bold=await pdf.embedFont(StandardFonts.HelveticaBold);
  const ink=rgb(.10,.16,.13);
  const green=rgb(.08,.31,.22);
  const totals=yardTotals(rows);
  const status=rows.length&&totals.verified===rows.length?'Alla adresser verifierade':'Ofullständig – adresser återstår';
  const format=(n:number)=>yardNumber.format(n).replace(/\s/g,' ');
  let page=pdf.addPage([842,595]);
  let y=550;
  function fit(value:string,width:number,size:number,strong:boolean) {
    const text=value.replace(/[\u2013\u2014]/g,'-').replace(/[^\u0020-\u007e\u00a0-\u00ff]/g,' ');
    const font=strong?bold:normal;
    if(font.widthOfTextAtSize(text,size)<=width) return text;
    let cut=text;
    while(cut&&font.widthOfTextAtSize(cut+'...',size)>width) cut=cut.slice(0,-1);
    return cut+'...';
  }
  function text(value:string,x:number,width:number,size=10,strong=false) {
    page.drawText(fit(value,width,size,strong),{x,y,size,font:strong?bold:normal,color:strong?green:ink});
  }
  function heading(isContinuation=false) {
    if(isContinuation) {page=pdf.addPage([842,595]);y=550;}
    text(`Årsrapport Miljöförbundet ${year}`,36,750,21,true);y-=23;
    text(`Elleholms Maskin AB · Sortergården · Pukavik 3:4 · ${version?'Version '+version:'Aktuell arbetsversion'}`,36,750);y-=19;
    text(status,36,750,10,true);y-=25;
  }
  heading();
  text(`Vägningar ${format(rows.length)} · In ${format(totals.in)} ton · Ut ${format(totals.out)} ton · Externt ${format(totals.external)} ton`,36,760);
  y-=18;
  text(`Verifierade ${totals.verified} · Sannolika ${totals.likely} · Anläggningsadress (reserv) ${totals.fallback} · Saknas ${totals.missing} · Obehandlade ${totals.pending}`,36,760);
  y-=33;
  const xs=[36,156,419,499,579,660,727];
  const widths=[112,255,72,72,72,59,79];
  function header() {
    ['Lagerplats','Material','In (ton)','Ut (ton)','Externt (ton)','Vägningar','Ej verifierade'].forEach((s,i)=>text(s,xs[i],widths[i],10,true));
    y-=17;
  }
  header();
  for (const r of yardMaterials(rows)) {
    if(y<46) {heading(true);header();}
    [r.stock,r.material,...[r.in,r.out,r.external,r.count,r.unverified].map(format)].forEach((s,i)=>text(s,xs[i],widths[i],9));
    page.drawLine({start:{x:36,y:y-5},end:{x:804,y:y-5},color:rgb(.83,.87,.84),thickness:.5});
    y-=16;
  }
  const pages=pdf.getPages();
  pages.forEach((p,i)=>p.drawText(`${i+1} / ${pages.length}`,{x:766,y:24,size:9,font:normal,color:ink}));
  return pdf.save();
}
