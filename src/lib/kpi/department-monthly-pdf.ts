import {PDFDocument,StandardFonts,rgb} from 'pdf-lib';
import {monthlyValue,type MonthlyTransportReport,type MonthlyMetric} from './monthly-report';

type Department={code:string;name:string;report:MonthlyTransportReport};
const ink=rgb(.11,.15,.20),muted=rgb(.39,.44,.49),yellow=rgb(.98,.77,.13),light=rgb(.95,.96,.97);
const safe=(s:string)=>s.replace(/[^\x20-\x7e\xa0-\xff]/g,'-');
export async function departmentMonthlyPdf(departments:Department[],variant:'ledning'|'utforlig'){
 const doc=await PDFDocument.create(),regular=await doc.embedFont(StandardFonts.Helvetica),bold=await doc.embedFont(StandardFonts.HelveticaBold);
 let page=doc.addPage([595,842]),y=790;const left=38,right=557;
 const text=(s:string,x:number,at:number,size=10,strong=false,color=ink)=>page.drawText(safe(s),{x,y:at,font:strong?bold:regular,size,color,maxWidth:550});
 const line=(at:number)=>page.drawLine({start:{x:left,y:at},end:{x:right,y:at},thickness:.7,color:rgb(.82,.84,.86)});
 const newPage=()=>{page=doc.addPage([595,842]);y=790;};
 const room=(h:number)=>{if(y-h<48)newPage();};
 const heading=(s:string)=>{room(40);text(s,left,y,15,true);y-=19;line(y);y-=17;};
 const money=(v:number|null|undefined,unit='kr')=>monthlyValue(v,unit);
 const row=(label:string,m:string,ytd:string)=>{room(29);text(label,left,y,10);text(m,320,y,10,true);text(ytd,448,y,9);y-=26;};
 const fmt=(m:MonthlyMetric|undefined)=>m?money(m.value,m.unit):'Saknas';
 const metrics=(d:Department)=>{const m=d.report.month.metrics,ym=d.report.ytd.metrics;for(let i=0;i<m.length;i++){row(m[i].label,fmt(m[i]),fmt(ym.find(x=>x.key===m[i].key)));}};
 const period=departments[0]?.report.period;
 page.drawRectangle({x:0,y:814,width:595,height:28,color:yellow});
 text('HUMLA  /  MANADSRAPPORT',left,824,11,true);
 text(variant==='ledning'?'Ledningsgrupp - avdelningsoversikt':'Utforlig avdelningsrapport',left,y,22,true);y-=33;
 text(period?`Manad: ${period.from} - ${period.to}  |  Verksamhetsar: ${period.fiscal_year}/${period.fiscal_year+1}`:'',left,y,10,false,muted);y-=28;
 text('KST 20 Sortergarden och KST 30 Transport - separata avdelningsresultat',left,y,10);y-=33;
 if(variant==='ledning'){
  heading('Sammanfattning per avdelning');
  text('Nyckeltal',left,y,9,true,muted);text('Manad',320,y,9,true,muted);text('YTD',448,y,9,true,muted);y-=23;
  for(const d of departments){heading(`KST ${d.code} - ${d.name}`);metrics(d);}
 }else{
  for(const d of departments){
   heading(`KST ${d.code} - ${d.name}`);
   text('Nyckeltal',left,y,9,true,muted);text('Manad',320,y,9,true,muted);text('YTD',448,y,9,true,muted);y-=23;
   metrics(d);
   heading('Ekonomisk sammanstallning');
   row('Registrerade intakter',money(d.report.month.recorded_revenue),money(d.report.ytd.recorded_revenue));
   row('Totala kostnader',money(d.report.month.cost),money(d.report.ytd.cost));
   row('Branslekostnad',money(d.report.month.fuel),money(d.report.ytd.fuel));
   row('Bransleandel',money(d.report.month.fuel_share,'%'),money(d.report.ytd.fuel_share,'%'));
   row('Personalkostnad - schablon',money(d.report.month.estimated_payroll),money(d.report.ytd.estimated_payroll));
   heading('Datastatus och definitioner');
   for(const m of d.report.month.metrics){room(42);text(m.label,left,y,10,true);y-=13;const status=m.status==='source'?'Enligt underlag':m.status==='estimate'?'Preliminart':m.status==='partial'?'Ofullstandigt':'Underlag saknas';text(status,left,y,9,false,muted);y-=23;}
   room(44);text('Resultat ar preliminart. Kontrollera kostnads- och tidsunderlag.',left,y,9,false,muted);y-=35;
  }
 }
 room(55);line(y);y-=16;
 text('Rapporten visar avdelningarnas samlade KPI - ingen fordonsuppdelning.',left,y,9,false,muted);y-=16;
 text('Underlag: Humla Hub. Saknade varden ersatts inte med noll.',left,y,9,false,muted);
 const pages=doc.getPages();for(let i=0;i<pages.length;i++){pages[i].drawText(safe(`Humla Dashboard  |  ${period?.from??''}  |  ${i+1}/${pages.length}`),{x:left,y:22,font:regular,size:8,color:muted});}
 return doc.save();
}
