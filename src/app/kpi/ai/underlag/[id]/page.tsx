import Link from 'next/link';
import {notFound,redirect} from 'next/navigation';
import {aiContext} from '@/lib/ai/context';
import styles from '@/app/_components/humla-chat.module.css';
export const dynamic='force-dynamic';
export default async function EvidencePage({params,searchParams}:{params:Promise<{id:string}>;searchParams:Promise<{type?:string}>}){
 const c=await aiContext();if('error'in c){if(c.status===401)redirect('/kpi/login');return <main>{c.error}</main>;}const {id}=await params;const {type}=await searchParams;if(!/^[0-9a-f-]{36}$/i.test(id))notFound();
 let data:unknown;let title='Originalunderlag';
 if(type==='transaction'){const {data:r,error}=await c.db.from('kpi_import_rows').select('id,batch_id,row_number,data_kind,occurred_on,description,amount,currency,vehicle_registration,project_reference,cost_center,account,source_data,created_at').eq('tenant_id',c.tenantId).eq('id',id).eq('is_valid',true).maybeSingle();if(error||!r)notFound();const {data:b}=await c.db.from('kpi_import_batches').select('file_name,source_type,status,created_at').eq('tenant_id',c.tenantId).eq('id',r.batch_id).in('status',['completed','needs_review']).maybeSingle();if(!b)notFound();data={...r,import:b};title=r.description??title;}
 else if(type==='object'){const {data:r,error}=await c.db.from('hub_objects').select('id,object_type,status,data,source_of_truth,updated_at').eq('tenant_id',c.tenantId).eq('id',id).not('object_type','in','(ExternalDriver,Person,Employee,FuelAccount)').maybeSingle();if(error||!r)notFound();const allowed=['registration_number','description','make','model','status','department','internal_ref','odometer','odometer_type','active','vehicle_type','asset_id','reading_type','reading_value','recorded_at','source_system','product_name','quantity_liters','quantity_unit','calculated_unit_price','price_status','source_amount','transaction_date','transaction_id','customer_number','order_number','title','note','project_reference','source_file','total','vehicle','planned_start','planned_end','date','amount','article_number','parent_order_number','quantity','unit_price'];data={...r,data:Object.fromEntries(Object.entries(r.data??{}).filter(([k])=>allowed.includes(k)))};title=r.object_type;}
 else notFound();
 return <main className={styles.page}><Link href="/kpi/ai" prefetch={false} className={styles.back}>← Fråga Humla</Link><h1>{title}</h1><p>Underlaget läses direkt fra Hubben med din aktuella behörighet. En importerad rad är inte automatiskt hela fakturan.</p><pre className={styles.evidence}>{JSON.stringify(data,null,2)}</pre></main>;
}
