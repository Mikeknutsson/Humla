alter table public.kpi_import_batches drop constraint kpi_import_batches_data_kind_check;
alter table public.kpi_import_batches add constraint kpi_import_batches_data_kind_check
 check (data_kind in ('revenue','cost','fuel','vehicle_activity','driver_time','next_historical_time','next_projects','next_articles'));

-- Source register for articles observed on NEXT work orders.
create table public.kpi_next_article_register (
 tenant_id uuid not null references public.hub_tenants(id) on delete cascade,
 code text not null check (length(code) between 1 and 100),
 name text not null check (length(name) between 1 and 250),
 unit text not null check (length(unit)<=50),
 account text not null check (length(account)<=50),
 price_list text not null check (length(price_list)<=200),
 min_price numeric check (abs(min_price)<1e12),
 max_price numeric check (abs(max_price)<1e12 and max_price>=min_price),
 min_cost numeric check (abs(min_cost)<1e12),
 max_cost numeric check (abs(max_cost)<1e12 and max_cost>=min_cost),
 source_rows integer not null check (source_rows between 1 and 30000),
 last_performed_on date,
 batch_id uuid not null references public.kpi_import_batches(id) on delete restrict,
 imported_at timestamptz not null default now(),
 primary key (tenant_id,code,name,unit,account,price_list)
);
create index kpi_next_article_register_batch_idx on public.kpi_next_article_register(batch_id);
alter table public.kpi_next_article_register enable row level security;
revoke all on table public.kpi_next_article_register from public,anon,authenticated;
grant select on table public.kpi_next_article_register to authenticated;
create policy next_article_register_read on public.kpi_next_article_register
 for select to authenticated using (public.hub_has_permission(tenant_id,'kpi.manage'));

create function private.hub_next_article_upload(
 t uuid,p_id uuid,p_file text,p_hash text,p_path text,p_rows jsonb,p_source_rows integer,p_from date,p_to date
)
returns jsonb language plpgsql security definer set search_path='' as $$
declare existing uuid; valid_rows integer;
begin
 if auth.uid() is null or public.hub_has_permission(t,'kpi.manage') is not true then
  raise exception 'Access denied' using errcode='42501';
 end if;
 if p_id is null or p_file is null or length(p_file) not between 1 and 200
  or p_hash is null or p_hash !~ '^[0-9a-f]{64}$'
  or p_path is null or split_part(p_path,'/',1)<>t::text or split_part(p_path,'/',2)<>p_id::text
  or p_source_rows is null or p_source_rows not between 1 and 30000
  or (p_from is null)<>(p_to is null) or p_from>p_to
  or jsonb_typeof(p_rows) is distinct from 'array' or jsonb_array_length(p_rows) not between 1 and 10000
 then raise exception 'Invalid article file' using errcode='22023';end if;
 select sum(r.source_rows) into valid_rows
 from jsonb_to_recordset(p_rows) as r(source_rows integer);
 if valid_rows is null or valid_rows not between jsonb_array_length(p_rows) and p_source_rows then
  raise exception 'Invalid article row count' using errcode='22023';
 end if;
 if not exists(select 1 from storage.objects where bucket_id='kpi-imports' and name=p_path) then
  raise exception 'Original file missing' using errcode='22023';
 end if;
 perform pg_advisory_xact_lock(hashtextextended('next-article-upload:'||t::text,0));
 select id into existing from public.kpi_import_batches
 where tenant_id=t and data_kind='next_articles' and file_hash=p_hash and status='completed';
 if existing is not null then return jsonb_build_object('duplicate',true,'batch_id',existing);end if;
 insert into public.kpi_import_batches(id,tenant_id,source_type,data_kind,file_name,file_hash,storage_path,status,
  row_count,valid_row_count,invalid_row_count,period_start,period_end,created_by,completed_at,provenance)
 values(p_id,t,'manual_excel','next_articles',p_file,p_hash,p_path,'completed',
  p_source_rows,valid_rows,p_source_rows-valid_rows,p_from,p_to,auth.uid(),now(),
  jsonb_build_object('channel','manual_upload','original_preserved',true,'connector','next_project_api',
   'export','workorder_resource_followup','article_variants',jsonb_array_length(p_rows)));
 insert into public.kpi_next_article_register as a(
  tenant_id,code,name,unit,account,price_list,min_price,max_price,min_cost,max_cost,source_rows,last_performed_on,batch_id
 )
 select t,btrim(r.code),btrim(r.name),btrim(r.unit),btrim(r.account),btrim(r.price_list),
  r.min_price,r.max_price,r.min_cost,r.max_cost,r.source_rows,r.last_performed_on,p_id
 from jsonb_to_recordset(p_rows) as r(
  code text,name text,unit text,account text,price_list text,min_price numeric,max_price numeric,
  min_cost numeric,max_cost numeric,source_rows integer,last_performed_on date
 )
 on conflict(tenant_id,code,name,unit,account,price_list) do update set
  min_price=excluded.min_price,max_price=excluded.max_price,min_cost=excluded.min_cost,max_cost=excluded.max_cost,
  source_rows=excluded.source_rows,last_performed_on=excluded.last_performed_on,batch_id=excluded.batch_id,imported_at=now()
 where a.last_performed_on is null or excluded.last_performed_on>=a.last_performed_on;
 return jsonb_build_object('duplicate',false,'batch_id',p_id,'rows',jsonb_array_length(p_rows));
end $$;
revoke all on function private.hub_next_article_upload(uuid,uuid,text,text,text,jsonb,integer,date,date) from public,anon,authenticated;
grant execute on function private.hub_next_article_upload(uuid,uuid,text,text,text,jsonb,integer,date,date) to authenticated;

create function public.hub_next_article_upload(
 t uuid,p_id uuid,p_file text,p_hash text,p_path text,p_rows jsonb,p_source_rows integer,p_from date,p_to date
)
returns jsonb language sql security invoker set search_path='' as $$
 select private.hub_next_article_upload(t,p_id,p_file,p_hash,p_path,p_rows,p_source_rows,p_from,p_to)
$$;
revoke all on function public.hub_next_article_upload(uuid,uuid,text,text,text,jsonb,integer,date,date) from public,anon,authenticated;
grant execute on function public.hub_next_article_upload(uuid,uuid,text,text,text,jsonb,integer,date,date) to authenticated;
