import * as XLSX from 'xlsx';
export type InternalRow={source_key:string;row_id:string;occurred_on:string;order:string;littra:string;project:string;receiver_name:string|null;vehicle:string;vehicle_id:string|null;receiver_id:string|null;source_center:string|null;receiver_center:string|null;receiver_rule?:string;vehicle_reference?:string;vehicle_rule?:string;category:string;amount:number|null;quantity:number|null;unit:string;article:string;description:string;comment:string;receipt_url:string|null;ready:boolean;status:'new'|'review'|'changed'|'exported'|'posted';review_reason:string;export_id:string|null;booking_reference:string|null};
export type TransferGroup={source_center:string|null;receiver_center:string|null;vehicle:string;vehicle_id:string|null;transport:number;material:number;tipp_deponi:number;total:number;rows:number};
export type TransferTotals={transport:number;material:number;tipp_deponi:number;total:number;rows:number};
export type InternalReport={rows:InternalRow[];count:number;groups?:TransferGroup[];totals?:TransferTotals;totals_by_center?:Record<string,TransferTotals>};
export function transferTotals(groups:TransferGroup[],center?:string):TransferTotals{const result={transport:0,material:0,tipp_deponi:0,total:0,rows:0};for(const g of groups){if(center&&g.source_center!==center&&g.receiver_center!==center)continue;for(const k of ['transport','material','tipp_deponi'] as const)result[k]=Math.round((result[k]+g[k])*100)/100;result.rows+=g.rows;}result.total=Math.round((result.transport+result.material+result.tipp_deponi)*100)/100;return result;}
// Server-side projection of verified evidence; not a second KPI revenue stream.
export function transferGroups(rows:InternalRow[]){const groups=new Map<string,TransferGroup>();for(const r of rows){if(!r.ready||r.status==='changed'||!['transport','material','tipp_deponi'].includes(r.category))continue;const key=JSON.stringify([r.source_center,r.receiver_center,r.vehicle_id]);const g=groups.get(key)??{source_center:r.source_center,receiver_center:r.receiver_center,vehicle:r.vehicle,vehicle_id:r.vehicle_id,transport:0,material:0,tipp_deponi:0,total:0,rows:0};const category=r.category as 'transport'|'material'|'tipp_deponi';g[category]=Math.round((g[category]+Number(r.amount))*100)/100;g.total=Math.round((g.transport+g.material+g.tipp_deponi)*100)/100;g.rows++;groups.set(key,g);}return [...groups.values()];}
export function internalQuery(p:URLSearchParams){
 const from=p.get('from')??'',to=p.get('to')??'';
 for(const date of [from,to])if(!/^\d{4}-\d{2}-\d{2}$/.test(date)||Number.isNaN(Date.parse(date))||new Date(date).toISOString().slice(0,10)!==date)throw new Error('Ogiltig period');
 if(to<from||Date.parse(to)-Date.parse(from)>366*86400000)throw new Error('Välj högst ett verksamhetsår');
 const months=p.has('months')?p.get('months')!.split(',').map(Number):null;
 if(months&&(!months.length||months.some(m=>!Number.isInteger(m)||m<1||m>12)))throw new Error('Ogiltiga månader');
 return {p_from:from,p_to:to,p_months:months};
}
export function finishedRows(rows:InternalRow[],center?:string){return rows.filter(r=>r.ready&&r.status!=='changed'&&['transport','material','tipp_deponi'].includes(r.category)&&(!center||r.source_center===center||r.receiver_center===center));}
export function transferWorkbook(rows:InternalRow[],exportId:string,report=false){
 const groups=transferGroups(rows).map(g=>({'Intäkts-KST':g.source_center??'','Kostnads-KST':g.receiver_center??'',Lastbil:g.vehicle,'Humla Fordons-ID':g.vehicle_id??'',Transport:g.transport,Material:g.material,Tippavgift:g.tipp_deponi,'Total intäkt':g.total,Orderrader:g.rows}));
 const details=rows.map(r=>({Datum:r.occurred_on,Order:r.order,Littra:r.littra,'Intäkts-KST':r.source_center,'Kostnads-KST':r.receiver_center,'Mottagande KST-regel':r.receiver_rule??'Matchat kostnadsställe',Fordon:r.vehicle,'Källans fordonsbenämning':r.vehicle_reference??r.vehicle,'Fordonsregel':r.vehicle_rule??'','Humla Fordons-ID':r.vehicle_id,Projekt:r.project,'Humla Projekt-ID':r.receiver_id,Kategori:r.category,Artikel:r.article,Beskrivning:r.description,Mängd:r.quantity,Enhet:r.unit,Belopp:r.amount,'Källrad-ID':r.row_id,'Dublettnyckel':r.source_key,'Export-ID':exportId}));
 const book=XLSX.utils.book_new();
 XLSX.utils.book_append_sheet(book,XLSX.utils.json_to_sheet([{Export:exportId,Kund:'Elleholms Maskin AB',Status:report?'Rapportexport – ingen omföringsstatus ändrad':'Exporterat underlag – inte bokfört automatiskt',Omföring:'Samlad internintäkt per lastbil mellan intäkts-KST och kostnads-KST',Avgränsning:'Endast fakturerade, granskade rader. Projektkoppling är valfri. Ingen moms eller BAS-kontering föreslås.'}]),'Underlag');
 const totals=transferTotals(transferGroups(rows));
 const summary=report?[{'Intäkts-KST':'','Kostnads-KST':'',Lastbil:'SUMMA','Humla Fordons-ID':'',Transport:totals.transport,Material:totals.material,Tippavgift:totals.tipp_deponi,'Total intäkt':totals.total,Orderrader:totals.rows},...groups]:groups;
 XLSX.utils.book_append_sheet(book,XLSX.utils.json_to_sheet(summary),'KST och fordon');
 XLSX.utils.book_append_sheet(book,XLSX.utils.json_to_sheet(details),'Orderrader');
 return XLSX.write(book,{type:'buffer',bookType:'xlsx'}) as Buffer;
}
