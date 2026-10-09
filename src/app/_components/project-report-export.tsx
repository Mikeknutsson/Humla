'use client';
import type {ProjectReport} from '@/lib/hub/project-report';
export function ProjectReportExport({report}:{report:ProjectReport}){
 const exportRows=()=>{
  const rows:unknown[][]=[['Humla – Projektuppföljning'],['Period',report.from,report.to],['Verksamhetsgrupp',report.selected_groups.length?report.selected_groups.join(', '):'Alla grupper'],['Källa',report.source],['Uppdelning',report.scope],['Personal',report.salary_source],['Projekt','Namn','KST','Projektledare','Verksamhetsgrupp','Intäkter','Kostnader','Resultat','Marginal %','Personal (ingår i kostnad)','Intern intäkt (ingår)','Intern kostnad (ingår)','Underlagsrader']];
  for(const p of report.projects)rows.push([p.project_number,p.project_name,p.cost_center,p.project_manager,p.business_group,p.revenue,p.cost,p.result,p.margin,p.personnel,p.internal_revenue,p.internal_cost,p.rows]);
  rows.push([],['Månad','Intäkter','Kostnader','Resultat']);for(const m of report.months)rows.push([m.month_start,m.revenue,m.cost,m.result]);
  if(report.transactions.length){rows.push([],['Underlag – endast denna sida, inte alla projektposter'],['Källa','Datum','Typ','Belopp','Konto','Kategori','Beskrivning','Fil','Filrad','Rad-ID','Fordonsfördelning']);for(const t of report.transactions)rows.push([t.source,t.date,t.kind,t.amount,t.account,t.category,t.description,t.file_name,t.row_number,t.id,t.validation_errors.join('; ')]);}
  const cell=(v:unknown)=>{let s=v==null?'':typeof v==='number'?String(v).replace('.',','):String(v);if(typeof v==='string'&&/^[=+@-]/.test(s))s="'"+s;return '"'+s.replaceAll('"','""')+'"';};
  const blob=new Blob(['\uFEFF'+rows.map(r=>r.map(cell).join(';')).join('\r\n')],{type:'text/csv;charset=utf-8'}),url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download=`Humla_projekt_${report.from}_${report.to}.csv`;a.click();URL.revokeObjectURL(url);
 };
 return <button type="button" className="secondary" onClick={exportRows}>Exportera projekt och månadsutfall</button>;
}
