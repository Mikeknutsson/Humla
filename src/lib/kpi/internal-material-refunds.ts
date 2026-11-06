export type MaterialRefundDetail={source_row:string;date:string;order_number:string|null;article:string|null;billed:number;purchase_cost:number|null;difference:number|null;source_center:string|null;littra:string|null;bundled:boolean;fallback:boolean;evidence:{status?:string;price_source?:string;note?:string}};
export type MaterialRefundProject={project_id:string|null;project_number:string;project_name:string|null;billed:number;purchase:number|null;refund:number|null;rows:number;estimated_rows:number;default_center_rows:number;missing_rows:number;bundled_rows:number;details:MaterialRefundDetail[]};
export type MaterialRefundReport={projects:MaterialRefundProject[];totals:{billed:number|null;purchase:number|null;refund:number|null;rows:number};all_material_billed:number;unresolved_billed:number;unresolved_rows:MaterialRefundDetail[];other_center_billed:number;other_center_rows:number;basis:string};
export function materialRefundCsv(report:MaterialRefundReport){
 const n=(v:number|null)=>v==null?'':v.toFixed(2).replace('.',',');
 const lines:(string|number)[][]=[['Materialpåslag tillbaka till projekt · KST 10'],[report.basis],
 ['Projekt','Projektnamn','Humla Projekt-ID','Fakturerat material','Beräknat inköp','Tillbaka (+) / tillägg (−)','Rader','Preliminära priser','Standardregel KST 10','Kopplingsstatus']];
 for(const p of report.projects)lines.push([p.project_number,p.project_name??'',p.project_id??'',n(p.billed),n(p.purchase),n(p.refund),p.rows,p.estimated_rows,p.default_center_rows,p.project_id?'Projekt identifierat':'Projektreferens – behöver verifieras']);
 lines.push(['SUMMA','','',n(report.totals.billed),n(report.totals.purchase),n(report.totals.refund)],[],['Utan projektfördelning',n(report.unresolved_billed)],['Andra mottagande KST',n(report.other_center_billed)],[],['Detaljer'],['Projekt','Datum','Order','Littra','Artikel','Intäkts-KST','Internpris','Beräknat inköp','Mellanskillnad','Prisunderlag','Källrad-ID']);
 const detail=(project:string,r:MaterialRefundDetail)=>lines.push([project,r.date,r.order_number??'',r.littra??'',r.article??'',r.source_center??'',n(r.billed),n(r.purchase_cost),r.bundled?'Kräver separat transportpris':n(r.difference),r.evidence?.price_source??'',r.source_row]);
 for(const p of report.projects)for(const r of p.details)detail(p.project_number,r);
 for(const r of report.unresolved_rows)detail('Ej projektfördelat',r);
 const cell=(v:string|number)=>{let s=String(v);if(typeof v==='string'&&/^[=+@-]/.test(s.trimStart())&&!/^-?\d+,\d{2}$/.test(s))s="'"+s;return '"'+s.replaceAll('"','""')+'"';};
 return '\uFEFF'+lines.map(r=>r.map(cell).join(';')).join('\r\n');
}
