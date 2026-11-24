import {reportYear,yardAccess,yardReport} from '@/lib/hub/sortergard-server';
import {yardExcel,yardPdf} from '@/lib/hub/sortergard-export';
import type {ReportVersion,Weighing} from '@/lib/hub/sortergard-report';

export async function GET(request:Request) {
  const access=await yardAccess();
  if(!access) return new Response('Behörighet saknas.',{status:403});
  const p=new URL(request.url).searchParams, id=p.get('version'), format=p.get('format');
  if((format!=='xlsx'&&format!=='pdf')||(id&&!/^[a-f0-9-]{36}$/i.test(id))) return new Response('Ogiltigt rapportval.',{status:400});
  const year=reportYear(p.get('year')??undefined);
  const {data,error}=await yardReport(access,year,id?'version':'read',id?{id}:{});
  if(error||!data) return new Response('Rapporten kunde inte hämtas.',{status:404});
  const selected=id?data as ReportVersion&{rows:Weighing[]}:null;
  const rows=selected?selected.rows:data as Weighing[];
  const bytes=format==='pdf'?await yardPdf(rows,year,selected?.version):yardExcel(rows,year,selected?.version);
  return new Response(Uint8Array.from(bytes),{headers:{
    'Content-Type':format==='pdf'?'application/pdf':'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'Content-Disposition':`attachment; filename="sortergarden-${year}${selected?`-v${selected.version}`:''}.${format}"`,
    'Cache-Control':'private, no-store',
  }});
}
