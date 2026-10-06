import * as XLSX from 'xlsx';
import {PDFDocument,StandardFonts} from 'pdf-lib';
import {monthlyRows,monthlyValue,metricStatus,type MonthlyTransportReport} from './monthly-report';
export function monthlyExcel(report:MonthlyTransportReport){
 const book=XLSX.utils.book_new();
 const metadata=[{Fält:'Rapport',Värde:`${report.tenant} · ${report.title}`},{Fält:'Månad',Värde:`${report.period.from} – ${report.period.to}`},{Fält:'YTD',Värde:`${report.period.ytd_from} – ${report.period.to}`},{Fält:'Urval',Värde:JSON.stringify(report.scope)},{Fält:'Underlag synkat',Värde:report.synced_at},{Fält:'Underlagsversion',Värde:report.generation},{Fält:'Definition',Värde:'Alla registrerade intäkter räknas som fakturerade enligt användarens rapportregel. Originalstatus ändras inte. Resultat är preliminärt med NEXT-kostnader och TransPA-schablon.'}];
 const vehicleRows=(period:MonthlyTransportReport['month'])=>period.vehicles.map(v=>({Enhet:v.label,'Fakturerad omsättning':v.invoiced_revenue,'Registrerade intäkter':v.recorded_revenue,Kostnad:v.cost,Bränsle:v.fuel,Typ:v.hired?'Inhyrdas samlingsenhet':'Fordonsenhet','Hub-nyckel':v.key}));
 const indicators=[{Indikator:'Registrerade intäkter',Månad:report.month.recorded_revenue,YTD:report.ytd.recorded_revenue,Enhet:'kr'},{Indikator:'Intäkter utanför rapportens faktureringsregel',Månad:report.month.uninvoiced_revenue,YTD:report.ytd.uninvoiced_revenue,Enhet:'kr'},{Indikator:'Totalt bränsle, ej enbart diesel',Månad:report.month.fuel,YTD:report.ytd.fuel,Enhet:'kr'},{Indikator:'Bränsle / fakturerad omsättning',Månad:report.month.fuel_share,YTD:report.ytd.fuel_share,Enhet:'%'},{Indikator:'Personalschablon TransPA',Månad:report.month.estimated_payroll,YTD:report.ytd.estimated_payroll,Enhet:'kr'},{Indikator:'Aktiva egna fordonsenheter',Månad:report.month.active_vehicle_count,YTD:report.ytd.active_vehicle_count,Enhet:'st'},{Indikator:'Rapporterad TransPA-tid / kapacitet, ej debiterbar tid',Månad:report.indicators.reported_vehicle_utilization,YTD:null,Enhet:'%'}];
 for(const [name,rows] of Object.entries({'Nyckeltal':monthlyRows(report),'Rapportunderlag':metadata,'Fordonsenheter månad':vehicleRows(report.month),'Fordonsenheter YTD':vehicleRows(report.ytd),'Indikatorer':indicators})){
 const sheet=XLSX.utils.json_to_sheet(rows);sheet['!cols']=[{wch:42},{wch:24},{wch:24},{wch:18},{wch:35},{wch:35},{wch:110}];XLSX.utils.book_append_sheet(book,sheet,name);
 }
 return XLSX.write(book,{type:'buffer',bookType:'xlsx'}) as Buffer;
}
export async function monthlyPdf(report:MonthlyTransportReport){
 const doc=await PDFDocument.create(),font=await doc.embedFont(StandardFonts.Helvetica),bold=await doc.embedFont(StandardFonts.HelveticaBold);
 let page=doc.addPage([595,842]),y=795;
 const clean=(s:string)=>s.replace(/[^\x20-\x7e\xa0-\xff]/g,'-');
 function draw(s:string,heading=false){if(y<45){page=doc.addPage([595,842]);y=795;}page.drawText(clean(s),{x:38,y,font:heading?bold:font,size:heading?13:9});y-=heading?23:14;}
 function line(s:string,heading=false){let row='';for(const word of clean(s).split(/\s+/)){const next=row?row+' '+word:word;if(font.widthOfTextAtSize(next,heading?13:9)>515){draw(row,heading);row=word;}else row=next;}if(row)draw(row,heading);}
 line(`${report.tenant} - ${report.title}`,true);line(`Månad: ${report.period.from} - ${report.period.to}`);line(`YTD: ${report.period.ytd_from} - ${report.period.to}`);line(`Urval: ${JSON.stringify(report.scope)}`);line(report.invoicing_rule);line(`Underlag synkat: ${report.synced_at}`);
 for(const [i,m] of report.month.metrics.entries()){y-=8;line(m.label,true);line(`Månad: ${monthlyValue(m.value,m.unit)} | YTD: ${monthlyValue(report.ytd.metrics[i].value,m.unit)}`);line(`${metricStatus[m.status]} | YTD: ${metricStatus[report.ytd.metrics[i].status]}`);line(m.basis);}
 line('Separata indikatorer',true);line(`Totalt bränsle: ${monthlyValue(report.month.fuel,'kr')} | Bränsleandel: ${monthlyValue(report.month.fuel_share,'%')}`);line(`Rapporterad fordonstid / kapacitet: ${monthlyValue(report.indicators.reported_vehicle_utilization,'%')}. ${report.indicators.definition}`);
 line('Fordonsenheter - månad',true);for(const v of report.month.vehicles)line(`${v.label}${v.hired?' (inhyrdas samlingsenhet)':''} | Fakturerat ${monthlyValue(v.invoiced_revenue,'kr')} | Kostnad ${monthlyValue(v.cost,'kr')}`);
 for(const [i,p] of doc.getPages().entries())p.drawText(`Humla Dashboard | ${report.period.from} | Sida ${i+1}/${doc.getPageCount()}`,{x:38,y:20,font,size:8});
 return doc.save();
}
