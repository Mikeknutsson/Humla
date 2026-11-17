import 'server-only';
import {createHash} from 'node:crypto';
import type {reviewAccess} from '@/lib/hub/review-access';

export type ResourceAccess=NonNullable<Awaited<ReturnType<typeof reviewAccess>>>;
type ResourceBatch={id:string;file_hash:string|null;storage_path:string|null};

export function nextResourceBatches({db,tenantId}:ResourceAccess){
  return db.from('kpi_import_batches')
    .select('id,file_name,file_hash,storage_path,completed_at,period_start,period_end')
    .eq('tenant_id',tenantId).eq('data_kind','next_articles').eq('status','completed')
    .order('completed_at',{ascending:false,nullsFirst:false}).order('id',{ascending:false}).limit(50);
}

export async function loadNextResourceFile({db,tenantId}:ResourceAccess,batch:ResourceBatch){
  if(!batch.storage_path?.startsWith(`${tenantId}/${batch.id}/`)||!batch.file_hash)throw Error('Batch source metadata missing');
  const {data,error}=await db.storage.from('kpi-imports').download(batch.storage_path);
  if(error||!data)throw Error('Batch download failed');
  const bytes=new Uint8Array(await data.arrayBuffer());
  if(bytes.length>4_000_000||createHash('sha256').update(bytes).digest('hex')!==batch.file_hash)throw Error('Batch source verification failed');
  return bytes;
}
