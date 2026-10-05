-- Vehicle and dated cost centers are sufficient for accounting transfers.
-- Optional project identity remains evidence, never a new guessed relation.
create or replace function public.hub_kpi_internal_transfers_v1(p_tenant_id uuid,p_from date,p_to date,p_months integer[] default null)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare result jsonb;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read') then raise exception 'KPI access required'; end if;
 if p_from is null or p_to is null or p_to<p_from or p_to-p_from>366 then raise exception 'Invalid period'; end if;
 if p_months is not null and (cardinality(p_months)=0 or exists(select 1 from unnest(p_months) m where m<1 or m>12 or m is null)) then raise exception 'Invalid months';end if;
 with raw as materialized (
  select x.*,coalesce(nullif(x.external_transaction_id,''),md5(jsonb_build_array(x.source_data->>'Ordernummer',x.source_data->>'Artikelnummer',x.occurred_on,upper(trim(x.source_data->>'RegNr')))::text)) source_key,
   nullif(regexp_replace(trim(x.source_data->>'Littranummer'),'^(AO)?([^[:space:]]+).*$', '\2','i'),'') receiver_reference
  from public.kpi_import_rows x where x.tenant_id=p_tenant_id and x.data_kind='revenue'
   and lower(trim(x.source_data->>'Kundnamn'))='elleholms maskin ab'
   and x.occurred_on between p_from and p_to and (p_months is null or extract(month from x.occurred_on)::integer=any(p_months))
 ), linked as (
  select x.*,count(*) over(partition by source_key) duplicate_count,
   ar.revenue_category category,
   case when vi.n=1 then vi.id end vehicle_id,case when pi.n=1 then pi.id end receiver_id,
   case when sc.n=1 then sc.code end source_center,case when rc.n=1 then rc.code end receiver_center,
   rc.name receiver_name
  from raw x
  left join lateral(select count(distinct k.object_id) n,(array_agg(distinct k.object_id))[1] id from public.hub_identity_keys k
   join public.hub_objects o on o.id=k.object_id and o.tenant_id=k.tenant_id
   where k.tenant_id=p_tenant_id and lower(o.object_type)='vehicle' and k.confidence=1
   and ((x.vehicle_object_id is not null and k.object_id=x.vehicle_object_id) or
   (x.vehicle_object_id is null and k.identity_type='registration_number' and upper(trim(k.identity_value))=upper(trim(x.source_data->>'RegNr'))))) vi on true
  left join lateral(select count(distinct k.object_id) n,(array_agg(distinct k.object_id))[1] id from public.hub_identity_keys k
   join public.hub_objects o on o.id=k.object_id and o.tenant_id=k.tenant_id
   where k.tenant_id=p_tenant_id and lower(o.object_type)='project' and k.confidence=1
   and k.identity_type='next_project_number' and k.identity_value=x.receiver_reference) pi on true
  left join lateral(select a.revenue_category from public.kpi_workify_article_rules a where a.tenant_id=p_tenant_id and a.enabled
   and a.article_number=x.source_data->>'Artikelnummer' and x.occurred_on>=a.valid_from and (a.valid_to is null or x.occurred_on<=a.valid_to)
   order by a.valid_from desc,a.id limit 1) ar on true
  left join lateral(select count(distinct c.cost_center) n,min(c.cost_center) code from public.kpi_project_classification_periods c
   where c.tenant_id=p_tenant_id and upper(trim(x.source_data->>'RegNr'))=any(c.registrations)
   and c.valid_from<=x.occurred_on and (c.valid_to is null or c.valid_to>=x.occurred_on)) sc on true
  left join lateral(select count(distinct c.cost_center) n,min(c.cost_center) code,min(c.project_name) name from public.kpi_project_classification_periods c
   where c.tenant_id=p_tenant_id and c.project_reference=x.receiver_reference
   and c.valid_from<=x.occurred_on and (c.valid_to is null or c.valid_to>=x.occurred_on)) rc on true
 ), prepared as (
  select source_key,jsonb_build_object('source_key',source_key,'row_id',id,'occurred_on',occurred_on,'order',source_data->>'Ordernummer',
   'littra',source_data->>'Littranummer','project',receiver_reference,'receiver_name',receiver_name,
   'vehicle',upper(trim(source_data->>'RegNr')),'vehicle_id',vehicle_id,'receiver_id',receiver_id,
   'source_center',source_center,'receiver_center',receiver_center,'category',coalesce(category,'unclassified'),
   'amount',amount,'quantity',quantity,'unit',source_data->>'Enhet','article',source_data->>'Artikelnummer',
   'description',description,'comment',source_data->>'ArtikelKommentar','receipt_url',nullif(source_data->>'FilUrl',''),
   'duplicate_count',duplicate_count,'invoiced',source_data->>'Orderstatus'='Invoiced',
   'ready',is_valid and amount is not null and vehicle_id is not null
    and source_center is not null and receiver_center is not null and duplicate_count=1
    and source_data->>'Orderstatus'='Invoiced' and category in ('transport','material','tipp_deponi'),
   'review_reason',concat_ws('; ',case when not is_valid then 'Ogiltig importrad' end,
    case when vehicle_id is null then 'Canonical fordonskoppling saknas/är tvetydig' end,
    case when source_center is null then 'Utförande kostnadsställe saknas' end,
    case when receiver_center is null then 'Mottagande kostnadsställe saknas' end,
    case when duplicate_count>1 then 'Dublett eller flera likadana orderrader – behöver granskas' end,
    case when source_data->>'Orderstatus' is distinct from 'Invoiced' then 'Inte fakturerad' end,
    case when category is null or category not in ('transport','material','tipp_deponi') then 'Artikelkategori behöver granskas' end,
    case when amount is null then 'Belopp saknas' end)) payload
  from linked
 ), finalized as (
  select p.payload||jsonb_build_object('export_id',l.export_id,'booking_reference',l.booking_reference,
   'status',case when l.source_key is null then case when (p.payload->>'ready')::boolean then 'new' else 'review' end
    when (p.payload - 'row_id') is distinct from (l.snapshot - 'row_id') then 'changed'
    when l.posted_at is not null then 'posted' else 'exported' end) payload from prepared p
  left join public.kpi_internal_transfer_ledger l on l.tenant_id=p_tenant_id and l.source_key=p.source_key
 ) select jsonb_build_object('rows',coalesce(jsonb_agg(payload order by payload->>'occurred_on',payload->>'order'),'[]'::jsonb),'count',count(*)) into result from finalized;
 if (result->>'count')::integer>10000 then raise exception 'Select a smaller period; no rows truncated';end if;
 return result;
end $$;
revoke all on function public.hub_kpi_internal_transfers_v1(uuid,date,date,integer[]) from public,anon;
grant execute on function public.hub_kpi_internal_transfers_v1(uuid,date,date,integer[]) to authenticated;

