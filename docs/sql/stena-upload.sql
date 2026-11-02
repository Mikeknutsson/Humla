create table if not exists private.hub_stena_upload_originals_v1(
 tenant_id uuid not null,file_hash text not null,original_base64 text not null,
 uploaded_by uuid not null,uploaded_at timestamptz not null default now(),mapping jsonb not null,
 primary key(tenant_id,file_hash),foreign key(tenant_id,file_hash) references private.hub_stena_files_v1(tenant_id,file_hash)
);
alter table private.hub_stena_upload_originals_v1 enable row level security;
revoke all on private.hub_stena_upload_originals_v1 from public,anon,authenticated;
create or replace function private.hub_stena_upload_v1(p_tenant uuid,p_hash text,p_name text,p_kind text,p_rows jsonb,p_original text,p_mapping jsonb,p_commit boolean default false)
returns jsonb language plpgsql security definer set search_path='' set statement_timeout='60s' as $$
declare result jsonb;n int;existing private.hub_stena_files_v1;i int;part jsonb;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant,'kpi.manage') then raise exception 'Access denied' using errcode='42501';end if;
 if p_kind not in ('history','settled') or p_kind is null or p_hash !~ '^[a-f0-9]{64}$' or p_hash is null or jsonb_typeof(p_rows) is distinct from 'array' or jsonb_array_length(p_rows) not between 1 and 20000 then raise exception 'Invalid file';end if;
 if exists(select 1 from jsonb_to_recordset(p_rows) r(booking text,date date,price numeric,settled_amount numeric,load_count numeric) where booking is null or booking !~ '^[0-9]{8}$' or date is null or (p_kind='history' and price is null) or (p_kind='settled' and settled_amount is null) or load_count<0) then raise exception 'Missing required source data';end if;
 if (select count(distinct r->>'booking') from jsonb_array_elements(p_rows)r)<>jsonb_array_length(p_rows) then raise exception 'Duplicate bookings in file';end if;
 select jsonb_build_object('rows',count(*),'priced_rows',count(amount),'unresolved_rows',count(*)filter(where amount is null),'total',sum(amount),'preview',coalesce(jsonb_agg(to_jsonb(x))filter(where position<=15),'[]')) into result
 from(select r.*,private.hub_stena_amount_v2(p_kind,r.price,r.extra,r.load_count,r.settled_amount,r.load_carrier_type) amount,row_number()over() position from jsonb_to_recordset(p_rows)r(row_number int,booking text,date text,registration text,price numeric,extra numeric,load_count numeric,settled_amount numeric,load_carrier_type text))x;
 if not p_commit then return result;end if;
 if length(p_original)>4500000 or p_original is null or p_original='' or length(p_name) not between 1 and 200 then raise exception 'Original file missing or too large';end if;
 if encode(extensions.digest(decode(p_original,'base64'),'sha256'),'hex')<>p_hash then raise exception 'Original hash mismatch';end if;
 perform pg_advisory_xact_lock(hashtextextended('stena-import:'||p_tenant::text,0));
 select * into existing from private.hub_stena_files_v1 where tenant_id=p_tenant and file_hash=p_hash;
 if found then
  if existing.complete then return result||jsonb_build_object('duplicate',true,'imported',false);end if;
  raise exception 'File has an incomplete prior import; review before continuing';
 end if;
 insert into private.hub_stena_files_v1(tenant_id,file_hash,file_name,source_kind,expected_rows) values(p_tenant,p_hash,p_name,p_kind,jsonb_array_length(p_rows));
 insert into private.hub_stena_upload_originals_v1(tenant_id,file_hash,original_base64,uploaded_by,mapping)values(p_tenant,p_hash,p_original,auth.uid(),p_mapping);
 for i in 0..((jsonb_array_length(p_rows)-1)/500) loop
  select jsonb_agg(value order by ordinal) into part from jsonb_array_elements(p_rows)with ordinality a(value,ordinal)where ordinal>i*500 and ordinal<=(i+1)*500;
  perform private.hub_stena_ingest_v1(p_tenant,p_hash,part);
 end loop;
 select count(*)into n from private.hub_stena_rows_v1 where tenant_id=p_tenant and file_hash=p_hash;
 if n<>jsonb_array_length(p_rows) then raise exception 'Incomplete row count';end if;
 update private.hub_stena_files_v1 set complete=true where tenant_id=p_tenant and file_hash=p_hash;
 perform public.hub_kpi_request_report_sync_v1(p_tenant);
 return result||jsonb_build_object('duplicate',false,'imported',true,'sync_requested',true);
end $$;
revoke all on function private.hub_stena_upload_v1(uuid,text,text,text,jsonb,text,jsonb,boolean) from public,anon;
grant execute on function private.hub_stena_upload_v1(uuid,text,text,text,jsonb,text,jsonb,boolean) to authenticated;
create or replace function public.hub_stena_upload_v1(p_tenant uuid,p_hash text,p_name text,p_kind text,p_rows jsonb,p_original text,p_mapping jsonb,p_commit boolean default false)
returns jsonb language sql security invoker set search_path='' as $$select private.hub_stena_upload_v1(p_tenant,p_hash,p_name,p_kind,p_rows,p_original,p_mapping,p_commit)$$;
revoke all on function public.hub_stena_upload_v1(uuid,text,text,text,jsonb,text,jsonb,boolean) from public,anon;
grant execute on function public.hub_stena_upload_v1(uuid,text,text,text,jsonb,text,jsonb,boolean) to authenticated;
