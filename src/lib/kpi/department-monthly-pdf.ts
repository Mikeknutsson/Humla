import {PDFDocument,StandardFonts,rgb} from 'pdf-lib';
import {monthlyValue,monthlyComparisonSections,type MonthlyTransportReport,type MonthlyComparisonRow} from './monthly-report';
type Department={code:string;name:string;report:MonthlyTransportReport};
const ink=rgb(.11,.15,.20),muted=rgb(.39,.44,.49),yellow=rgb(.98,.77,.13);
const safe=(s:string)=>s.replace(/[^\x20-\x7e\xa0-\xff]/g,'-');
export async function departmentMonthlyPdf(departments:Department[],variant:'ledning'|'utforlig'){
 const doc=await PDFDocument.create(),regular=await doc.embedFont(StandardFonts.Helvetica),bold=await doc.embedFont(StandardFonts.HelveticaBold);
 let page=doc.addPage([595,842]),y=790;const left=38,right=557,columns=[272,343,414,485];
 const text=(s:string,x:number,at:number,size=9,strong=false,color=ink)=>page.drawText(safe(s),{x,y:at,font:strong?bold:regular,size,color});
 const line=(at:number)=>page.drawLine({start:{x:left,y:at},end:{x:right,y:at},thickness:.7,color:rgb(.82,.84,.86)});
 const newPage=()=>{page=doc.addPage([595,842]);y=790;};
 const room=(h:number)=>{if(y-h<48)newPage();};
 const heading=(s:string)=>{room(65);text(s,left,y,14,true);y-=20;line(y);y-=18;};
 const headers=()=>{text('Nyckeltal',left,y,8,true,muted);['Månad','YTD','Månad fg. år','YTD fg. år'].forEach((s,i)=>text(s,columns[i],y,8,true,muted));y-=23;};
 function rows(title:string,items:MonthlyComparisonRow[]){
  room(105);heading(title);headers();
  for(const row of items){
   const label=safe(row.label.replace(' – TransPA-indikator','').replace(' – TransPA','').replace('NEXT egen tank, avstämning utanför summan','NEXT egen tank (avstämning)'));
   const labels:string[]=[];let current='';
   for(const word of label.split(' ')){const candidate=current?current+' '+word:word;if(current&&regular.widthOfTextAtSize(candidate,8.5)>220){labels.push(current);current=word;}else current=candidate;}if(current)labels.push(current);
   const height=Math.max(24,labels.length*11+10);
   if(y-height<48){newPage();heading(title+' (forts.)');headers();}
   labels.forEach((part,i)=>text(part,left,y-i*11,8.5));row.values.forEach((v,i)=>text(v==null?'Saknas':monthlyValue(v,row.unit),columns[i],y,8,true));y-=height;
  }
  y-=10;
 }
 const period=departments[0]?.report.period;
 page.drawRectangle({x:0,y:814,width:595,height:28,color:yellow});text('HUMLA / MÅNADSRAPPORT',left,824,11,true);
 text(variant==='ledning'?'Ledningsgrupp – avdelningsöversikt':'Utförlig avdelningsrapport',left,y,21,true);y-=32;
 text(period?`Månad: ${period.from} - ${period.to} | Verksamhetsår: ${period.fiscal_year}/${period.fiscal_year+1}`:'',left,y,9,false,muted);y-=24;
 text('KST 20 Sortergården och KST 30 Transport – separata avdelningsresultat',left,y,9);y-=25;
 const excluded=departments[0]?.report.excluded_projects??[];
 if(excluded.length){text('Utanför uppföljningen: '+excluded.map(p=>p.name).join(', '),left,y,9,false,muted);y-=25;}
 for(const [index,d] of departments.entries()){
  if(index>0)newPage();
  heading(`KST ${d.code} – ${d.name}`);
  text('Samma månad och YTD föregående år. Saknat underlag visas som Saknas.',left,y,9,false,muted);y-=25;
  if(d.report.reconciliation?.status==='needs_review'){room(28);text('Preliminär intäkt och resultat – Workify-avstämning återstår.',left,y,9,true);y-=25;}
  if(!d.report.previous_available){room(28);text('Jämförelseåret kunde inte hämtas.',left,y,9,false,muted);y-=25;}
  for(const section of monthlyComparisonSections(d.report)){
   if(variant==='ledning'&&section.key!=='metrics')continue;
   rows(section.title,section.rows);
  }
 }
 room(52);line(y);y-=16;text('Underlag: Humla Hub. Schablonkostnader och tidsindikatorer är preliminära.',left,y,8.5,false,muted);
 const pages=doc.getPages();for(let i=0;i<pages.length;i++)pages[i].drawText(safe(`Humla Dashboard | ${period?.from??''} | ${i+1}/${pages.length}`),{x:left,y:22,font:regular,size:8,color:muted});
 return doc.save();
}
