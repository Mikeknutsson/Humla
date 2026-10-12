import type {InternalRow} from './internal-transfers';
// Financial selection and reconciliation are owned by the Hub RPC.
export type InternalSummaryRow=InternalRow&{report_copies:number;report_basis:'confirmed'|'preliminary'};
export type InternalCenterSummary={
 transfers:Array<{fromCenter:string;fromName:string;toCenter:string;toName:string;amount:number;confirmedAmount:number;preliminaryAmount:number;rows:InternalSummaryRow[]}>;
 total:number;confirmedTotal:number;preliminaryTotal:number;
 unassignedRows:number;unassignedAmount:number;unassignedItems:InternalSummaryRow[];
 otherRows:number;otherAmount:number;otherItems:InternalSummaryRow[];
 duplicateRowsRemoved:number;duplicateAmountRemoved:number;
 conflictCount:number;conflictRawAmount:number;conflicts:Array<{sourceKey:string;rawAmount:number;variants:InternalRow[]}>;
 sourceRows:number;sourceAmount:number;invalidAmountRows:number;reconciles:boolean;
};
export function internalCenterSummaryCsv(summary:InternalCenterSummary,from:string,to:string){
 const lines:(string|number)[][]=[['Interna körningar – perioduppföljning'],['Period från',from,'Till',to],
 ['Periodbelopp omfattar preliminära rader. Kompatibla importkopior räknas en gång. STENA undantas. Ingen bokföring eller exportstatus ändras.'],
 ['Från KST – kostnad','Från avdelning','Till KST – intäkt','Till avdelning','Periodbelopp SEK','Bekräftat SEK','Preliminärt SEK','Unika orderrader']];
 const decimal=(n:number)=>n.toFixed(2).replace('.',',');
 for(const t of summary.transfers)lines.push([t.fromCenter,t.fromName,t.toCenter,t.toName,decimal(t.amount),decimal(t.confirmedAmount),decimal(t.preliminaryAmount),t.rows.length]);
 lines.push(['','','','Summa',decimal(summary.total),decimal(summary.confirmedTotal),decimal(summary.preliminaryTotal)],[],
 ['Avstämning av hela underlaget','Belopp SEK','Rader / källnycklar'],
 ['Importerat brutto',decimal(summary.sourceAmount),summary.sourceRows],
 ['Två överföringar',decimal(summary.total)],
 ['Utan intäkts-KST',decimal(summary.unassignedAmount),summary.unassignedRows],
 ['Andra överföringar',decimal(summary.otherAmount),summary.otherRows],
 ['Importkopior borträknade',decimal(summary.duplicateAmountRemoved),summary.duplicateRowsRemoved],
 ['Motstridiga källrader – brutto, kan innehålla kopior',decimal(summary.conflictRawAmount),summary.conflictCount],
 ['Rader utan läsbart belopp','',summary.invalidAmountRows],
 ['Avstämning av läsbara belopp',summary.reconciles?'Stämmer':'Avvikelse'],[],
 ['Underlag – samtliga delar'],['Del','Datum','Order','Littra','Från KST','Till KST','Belopp SEK','Rapportgrund','Exportstatus','Importkopior','Anmärkning','Källrad-ID']);
 const detail=(section:string,r:InternalRow,basis:string,copies:number)=>lines.push([section,r.occurred_on,r.order,r.littra,r.receiver_center??'',r.source_center??'',r.amount===null?'':decimal(r.amount),basis,r.status,copies,r.review_reason,r.row_id]);
 for(const t of summary.transfers)for(const r of t.rows)detail(t.fromName+' → '+t.toName,r,r.report_basis,r.report_copies);
 for(const r of summary.unassignedItems)detail('Utan intäkts-KST',r,r.report_basis,r.report_copies);
 for(const r of summary.otherItems)detail('Annan överföring',r,r.report_basis,r.report_copies);
 for(const c of summary.conflicts)for(const r of c.variants)detail('Motstridiga uppgifter – inte summerade',r,'conflict',c.variants.length);
 const cell=(v:string|number)=>{let s=String(v);if(typeof v==='string'&&/^[=+@-]/.test(s.trimStart())&&!/^[-]?\d+[,.]\d{2}$/.test(s))s="'"+s;return '"'+s.replaceAll('"','""')+'"';};
 return '\uFEFF'+lines.map(line=>line.map(cell).join(';')).join('\r\n');
}
