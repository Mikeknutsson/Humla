import {createClient} from '@/lib/supabase/server';
import {createHash} from 'node:crypto';
import * as XLSX from 'xlsx';
export async function POST(req:Request){
 const s=await createClient();const {data:{user}}=await s.auth.getUser();
 if(!user)return Response.json({error:'Inloggning krävs'},{status:401});
 const {data:member}=await s.from('hub_tenant_members').select('tenant_id').eq('user_id',user.id).eq('status','active').maybeSingle();
 if(!member)return Response.json({error:'Organisation saknas'},{status:403});
 const {data:allowed}=await s.rpc('hub_has_permission',{p_tenant_id:member.tenant_id,p_permission:'kpi.manage'});
 if(!allowed)return Response.json({error:'Behörighet saknas'},{status:403});
 try{
 const form=await req.formData(),file=form.get('file'),source=String(form.get('source')??'').trim();
 if(!(file instanceof File)||file.size>5e6||!file.size||!source)return Response.json({error:'Välj CSV/Excel under 5 MB och ange källa'},{status:400});
 if(!/\.(csv|xlsx|xls)$/i.test(file.name))return Response.json({error:'Filformatet ska vara CSV eller Excel'},{status:400});
 const bytes=new Uint8Array(await file.arrayBuffer());
 const csv=/\.csv$/i.test(file.name);
 const book=XLSX.read(csv?new TextDecoder('utf-8',{fatal:true}).decode(bytes):bytes,{type:csv?'string':'array',cellDates:true,raw:true,sheetRows:5002});
 if(book.SheetNames.length!==1)return Response.json({error:'Använd en fil med ett blad'},{status:400});
 const records=XLSX.utils.sheet_to_json<Record<string,unknown>>(book.Sheets[book.SheetNames[0]],{defval:'',raw:true});
 if(records.length>5000||!records.length)return Response.json({error:'Filen ska innehålla 1–5 000 rader'},{status:400});
 const dateText=(v:unknown)=>v instanceof Date?v.toISOString().slice(0,10):String(v??'');
 const rows=records.map(r=>({registration:String(r.Regnummer??''),from:dateText(r['Från']),to:dateText(r.Till),distance:String(r['Körsträcka']??''),unit:String(r.Enhet??'').trim().toLowerCase(),original:r}));
 const {data,error}=await s.rpc('hub_kpi_import_distance_v1',{p_tenant_id:member.tenant_id,p_rows:rows,p_file_name:file.name,p_file_hash:createHash('sha256').update(bytes).digest('hex'),p_source:source});
 if(error)return Response.json({error:'Importen kunde inte sparas i Hubben'},{status:400});
 return Response.json(data);
 }catch{return Response.json({error:'Filen kunde inte läsas. Kontrollera format och rubriker.'},{status:400});}
}
