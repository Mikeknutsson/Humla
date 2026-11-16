import * as XLSX from 'xlsx';

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
    const labels=header.map(value=>String(value).trim().toLocaleLowerCase('sv'));
    const indexes=Object.fromEntries(Object.entries(columns).map(([key,names])=>[key,names.map(label=>labels.indexOf(label.toLocaleLowerCase('sv'))).find(index=>index>=0)??-1]));
    if(indexes.project_number<0||indexes.project_name<0)continue;
    if(indexes.cost_center_name===indexes.cost_center)indexes.cost_center_name=-1;
    const projects=rows.flatMap((values,index)=>{
      if(!values.some(value=>String(value).trim()))return [];
      const project=Object.fromEntries(Object.entries(indexes).map(([key,column])=>[key,String(values[column]??'').trim()]));
      if(!project.project_number||!project.project_name)throw Error(`Rad ${index+2} saknar projektnummer eller projektnamn.`);
      if(seen.has(project.project_number))throw Error(`Rad ${index+2} har ett projektnummer som redan finns i filen.`);
      if(project.cost_center&&!/^\d{1,8}$/.test(project.cost_center))throw Error(`Rad ${index+2} har ett ogiltigt kostnadsställenummer.`);
      seen.add(project.project_number);
      return [project];
    });
    if(!projects.length||projects.length>10000)throw Error('Filen måste innehålla 1–10 000 projekt.');
    return projects;
  }
  throw Error('Inget blad med Projektnr och Projektnamn hittades.');
}
