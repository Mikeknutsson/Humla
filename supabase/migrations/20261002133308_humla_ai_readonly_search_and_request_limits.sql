create table public.hub_ai_requests (id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.hub_tenants(id), user_id uuid not null references auth.users(id), created_at timestamptz not null default now());
create index hub_ai_requests_user_time on public.hub_ai_requests(user_id,created_at desc);
alter table public.hub_ai_requests enable row level security;
revoke all on public.hub_ai_requests from anon,authenticated;
grant select,insert on public.hub_ai_requests to authenticated;
create policy hub_ai_requests_read on public.hub_ai_requests for select to authenticated using (user_id=auth.uid() and public.hub_has_permission(tenant_id,'kpi.read'));
create policy hub_ai_requests_insert on public.hub_ai_requests for insert to authenticated with check (user_id=auth.uid() and public.hub_has_permission(tenant_id,'kpi.read'));
create function public.hub_ai_reserve_request_v1(p_tenant_id uuid) returns boolean language plpgsql security invoker set search_path='' as $$
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read') then raise exception 'Åtkomst saknas' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(hashtextextended('humla-ai:'||auth.uid()::text,0));
 if (select count(*) from public.hub_ai_requests where user_id=auth.uid() and created_at>now()-interval '1 minute')>=8 or (select count(*) from public.hub_ai_requests where user_id=auth.uid() and created_at>now()-interval '24 hours')>=100 then return false; end if;
 insert into public.hub_ai_requests(tenant_id,user_id) values(p_tenant_id,auth.uid());return true;
end $$;
create function public.hub_ai_search_v1(p_tenant_id uuid,p_terms text[],p_source text default 'all',p_from date default null,p_to date default null,p_offset integer default 0) returns jsonb language plpgsql security invoker set search_path='' set statement_timeout='15s' as $$
declare result jsonb;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read') then raise exception 'Åtkomst saknas' using errcode='42501'; end if;
 if p_terms is null or cardinality(p_terms)<1 or cardinality(p_terms)>6 or exists(select 1 from unnest(p_terms) t where t is null or length(trim(t))<2 or length(t)>80) or p_source not in ('all','transactions','objects') or p_offset<0 or p_offset>600 or (p_from is not null and p_to is not null and p_to<p_from) then raise exception 'Ogiltigt sökurval'; end if;
 with rows as materialized (
 select r.id,'transaction'::text evidence_type,r.occurred_on::text event_date,r.created_at,r.amount,r.currency,r.data_kind,
 jsonb_build_object('description',r.description,'kind',r.data_kind,'amount',r.amount,'currency',r.currency,'date',r.occurred_on,'vehicle',r.vehicle_registration,'project',r.project_reference,'cost_center',r.cost_center,'account',r.account,'source',b.source_type,'file',b.file_name,'row_number',r.row_number,'import_status',b.status,'original',coalesce((select jsonb_object_agg(k,v) from jsonb_each(r.source_data) e(k,v) where k=any(array['Kundnamn','Kundnr','Artikelnamn','Artikelnummer','ArtikelKommentar','Kundpris','Kvantitet','Enhet','Summa','Rubrik','Ordernummer','Orderstatus','Fakturerad','Artikeldatum','ExterntDokumentnummer','RegNr','Fordon','Projekt','Kostnadsställe','Littranummer','OmvändMoms'])),'{}'::jsonb)) details,
 coalesce(nullif(r.source_data->>'Fakturerad',''),r.occurred_on::text) sort_date
 from public.kpi_import_rows r join public.kpi_import_batches b on b.id=r.batch_id and b.tenant_id=r.tenant_id
 where p_source in ('all','transactions') and r.tenant_id=p_tenant_id and r.is_valid and b.status in ('completed','needs_review') and (p_from is null or r.occurred_on>=p_from) and (p_to is null or r.occurred_on<=p_to)
 and not exists(select 1 from unnest(p_terms) t where strpos(lower(coalesce(r.description,'')||' '||coalesce(r.project_reference,'')||' '||coalesce(r.vehicle_registration,'')||' '||coalesce((select jsonb_object_agg(k,v)::text from jsonb_each(r.source_data) e(k,v) where k=any(array['Kundnamn','Kundnr','Artikelnamn','Artikelnummer','ArtikelKommentar','Rubrik','Ordernummer','RegNr','Fordon','Projekt','Kostnadsställe','Littranummer','ExterntDokumentnummer'])),'')),lower(trim(t)))=0)
 ), objects as materialized (
 select o.id,'object'::text evidence_type,coalesce(o.data->>'recorded_at',o.data->>'transaction_date',o.data->>'date',o.data->>'planned_start',o.updated_at::text) event_date,o.updated_at created_at,null::numeric amount,null::text currency,null::text data_kind,
 jsonb_build_object('object_type',o.object_type,'status',o.status,'updated_at',o.updated_at,'source',o.source_of_truth,'data',coalesce((select jsonb_object_agg(k,v) from jsonb_each(o.data) e(k,v) where k=any(array['registration_number','description','make','model','status','department','internal_ref','odometer','odometer_type','active','vehicle_type','asset_id','reading_type','reading_value','recorded_at','source_system','product_name','quantity_liters','quantity_unit','calculated_unit_price','price_status','source_amount','transaction_date','transaction_id','customer_number','order_number','title','note','project_reference','source_file','total','vehicle','planned_start','planned_end','date','amount','article_number','parent_order_number','quantity','unit_price'])),'{}'::jsonb)) details,
 coalesce(o.data->>'recorded_at',o.data->>'transaction_date',o.data->>'date',o.updated_at::text) sort_date
 from public.hub_objects o where p_source in ('all','objects') and o.tenant_id=p_tenant_id and o.object_type not in ('ExternalDriver','Person','Employee','FuelAccount')
 and (p_from is null or left(coalesce(o.data->>'recorded_at',o.data->>'transaction_date',o.data->>'date',o.data->>'planned_start',o.updated_at::text),10)>=p_from::text) and (p_to is null or left(coalesce(o.data->>'recorded_at',o.data->>'transaction_date',o.data->>'date',o.data->>'planned_start',o.updated_at::text),10)<=p_to::text)
 and not exists(select 1 from unnest(p_terms) t where strpos(lower(coalesce((select jsonb_object_agg(k,v)::text from jsonb_each(o.data) e(k,v) where k=any(array['registration_number','description','make','model','department','internal_ref','asset_id','reading_type','source_system','product_name','customer_number','order_number','title','note','project_reference','vehicle','article_number','parent_order_number'])),'')),lower(trim(t)))=0)
 ), matches as materialized (select * from rows union all select * from objects), page as (select * from matches order by sort_date desc,id limit 30 offset p_offset)
 select jsonb_build_object('searched_at',now(),'terms',p_terms,'matched_count',(select count(*) from matches),'offset',p_offset,'has_more',(select count(*) from matches)>p_offset+30,'coverage',(select jsonb_build_object('first_date',min(r.occurred_on),'last_date',max(r.occurred_on),'latest_import_at',max(b.created_at)) from public.kpi_import_rows r join public.kpi_import_batches b on b.id=r.batch_id where r.tenant_id=p_tenant_id and r.is_valid and b.status in ('completed','needs_review')),'matched_import_amounts',(select coalesce(jsonb_agg(x),'[]'::jsonb) from (select data_kind kind,currency,sum(amount) amount,count(*) rows from rows group by data_kind,currency) x),'results',coalesce((select jsonb_agg(jsonb_build_object('id',id,'evidence_type',evidence_type,'date',event_date,'details',details) order by sort_date desc,id) from page),'[]'::jsonb)) into result;
 return result;
end $$;
revoke all on function public.hub_ai_search_v1(uuid,text[],text,date,date,integer) from public,anon;
revoke all on function public.hub_ai_reserve_request_v1(uuid) from public,anon;
grant execute on function public.hub_ai_search_v1(uuid,text[],text,date,date,integer) to authenticated;
grant execute on function public.hub_ai_reserve_request_v1(uuid) to authenticated;
