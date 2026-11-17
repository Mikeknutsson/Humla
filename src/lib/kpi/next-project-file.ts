import * as XLSX from 'xlsx';
import { isNextArticleResourceExport } from './next-article-file';

const columns = {
  project_number:['Projektnr','Projektnummer'],
  project_name:['Projektnamn'],
  cost_center:['Kostnadsställe nummer','Kostnadsställenummer','Kostnadsställe'],
  cost_center_name:['Kostnadsställe namn','Kostnadsställe'],
  project_manager:['Projektledare'],
  project_status:['Projektstatus'],
  project_category:['Projektkategori'],
  source_business_groups:['Verksamhetsgrupper','Verksamhetsgrupp'],
} as const;

export function readNextProjectFile(bytes:Uint8Array){
  const workbook=XLSX.read(bytes,{type:'array'});
  const seen=new Set<string>();
  for(const name of workbook.SheetNames){
    const sheet=workbook.Sheets[name];
    const [header,...rows]=XLSX.utils.sheet_to_json<string[]>(sheet,{header:1,raw:false,defval:'',blankrows:true});
    if(!header)continue;
    if(isNextArticleResourceExport(header))throw Error('Det här är Arbetsorder – Resursuppföljning. Släpp filen i den vanliga dropprutan högst upp på Dataimport för att importera NeXT-artiklar.');
    const labels=header.map(value=>String(value).trim().toLocaleLowerCase('sv'));
    const indexes=Object.fromEntries(Object.entries(columns).map(([key,names])=>[key,names.map(label=>labels.indexOf(label.toLocaleLowerCase('sv'))).find(index=>index>=0)??-1]));
    if(indexes.project_number<0||indexes.project_name<0)continue;
    if(indexes.cost_center_name===indexes.cost_center)indexes.cost_center_name=-1;
    const firstDataRow=XLSX.utils.decode_range(sheet['!ref']??'A1').s.r+2;
    const invalidCostCenterRows:number[]=[];
    const incompleteProjectRows:number[]=[];
    const projects=rows.flatMap((values,index)=>{
      if(!values.some(value=>String(value).trim()))return [];
      const project=Object.fromEntries(Object.entries(indexes).map(([key,column])=>[key,String(values[column]??'').trim()]));
      const excelRow=firstDataRow+index;
      if(!project.project_number||!project.project_name){
        incompleteProjectRows.push(excelRow);
        return [];
      }
      if(seen.has(project.project_number))throw Error(`Rad ${excelRow} har ett projektnummer som redan finns i filen.`);
      if(project.cost_center&&!/^\d{1,8}$/.test(project.cost_center)){
        invalidCostCenterRows.push(excelRow);
        project.cost_center='';
        project.cost_center_name='';
      }
      seen.add(project.project_number);
      return [project];
    });
    if(!projects.length&&incompleteProjectRows.length)throw Error('Inga projekt med både projektnummer och projektnamn hittades.');
    if(!projects.length||projects.length>10000)throw Error('Filen måste innehålla 1–10 000 projekt.');
    return {projects,invalidCostCenterRows,incompleteProjectRows};
  }
  throw Error('Inget blad med Projektnr och Projektnamn hittades.');
}
