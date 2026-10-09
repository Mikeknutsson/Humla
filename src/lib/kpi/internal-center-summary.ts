import {finishedRows,type InternalRow} from './internal-transfers';
// Cost-bearing receiver -> income-bearing source. No new identity or allocation.
export function internalCenterSummary(rows:InternalRow[]){
 const scope=rows.filter(r=>r.receiver_center==='10');
 const eligible=new Set(finishedRows(scope).filter(r=>r.amount!==null&&Number.isFinite(r.amount)).map(r=>r.row_id));
 const transfers=([['30','Transport'],['20','Sortergården']] as const).map(([toCenter,toName])=>{
  const candidates=scope.filter(r=>r.source_center===toCenter),included=candidates.filter(r=>eligible.has(r.row_id)),excluded=candidates.filter(r=>!eligible.has(r.row_id));
  return {fromCenter:'10',fromName:'Entreprenad',toCenter,toName,
   amount:included.reduce((s,r)=>s+Math.round(r.amount!*100),0)/100,rows:included,excludedRows:excluded.length,
   excludedAmount:excluded.reduce((s,r)=>s+(Number.isFinite(r.amount)?Math.round((r.amount??0)*100):0),0)/100};
 });
 return {transfers,total:transfers.reduce((s,t)=>s+Math.round(t.amount*100),0)/100,unassignedRows:scope.filter(r=>!r.source_center).length};
}
export type InternalCenterSummary=ReturnType<typeof internalCenterSummary>;
export function internalCenterSummaryCsv(summary:InternalCenterSummary,from:string,to:string){
 const lines:(string|number)[][]=[['Interna körningar – omföringsunderlag'],['Period från',from,'Till',to],
  ['Fakturerade och granskade rader. STENA undantas. Ingen bokföring eller exportstatus ändras.'],
  ['Från KST – kostnad','Från avdelning','Till KST – intäkt','Till avdelning','Belopp SEK','Orderrader','Undantagna rader','Undantaget belopp SEK']];
 const decimal=(n:number)=>n.toFixed(2).replace('.',',');
 for(const t of summary.transfers)lines.push([t.fromCenter,t.fromName,t.toCenter,t.toName,decimal(t.amount),t.rows.length,t.excludedRows,decimal(t.excludedAmount)]);
 lines.push(['','','','Summa',decimal(summary.total)],['Rader utan intäkts-KST – ingår inte',summary.unassignedRows],[],['Underlag till de två summorna'],['Datum','Order','Littra','Från KST – kostnad','Till KST – intäkt','Belopp SEK','Status','Källrad-ID']);
 for(const t of summary.transfers)for(const r of t.rows)lines.push([r.occurred_on,r.order,r.littra,t.fromCenter,t.toCenter,decimal(r.amount!),r.status,r.row_id]);
 // Prevent source text from becoming spreadsheet formulas, including - prefixes.
 const cell=(v:string|number)=>{let s=String(v);if(typeof v==='string'&&/^[=+@-]/.test(s.trimStart())&&!/^[-]?\d+[,.]\d{2}$/.test(s))s="'"+s;return '"'+s.replaceAll('"','""')+'"';};
 return '\uFEFF'+lines.map(line=>line.map(cell).join(';')).join('\r\n');
}
