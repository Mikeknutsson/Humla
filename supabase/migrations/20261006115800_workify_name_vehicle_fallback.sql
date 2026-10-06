-- Confirmed, dated Hub relationships to canonical vehicles. No guessed identities.
create table private.hub_workify_name_vehicle_rules (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.hub_tenants(id),
 name text not null check(length(trim(name)) between 1 and 200),
 name_key text generated always as (lower(regexp_replace(trim(name),'[[:space:]]+',' ','g'))) stored,
 vehicle_object_id uuid not null references public.hub_objects(id),
 valid_from date not null, valid_to date, created_by uuid not null references auth.users(id),
 created_at timestamptz not null default now(), check(valid_to is null or valid_to>=valid_from)
);
create index on private.hub_workify_name_vehicle_rules(tenant_id,name_key,valid_from);
alter table private.hub_workify_name_vehicle_rules enable row level security;
revoke all on private.hub_workify_name_vehicle_rules from public,anon,authenticated;

create function public.hub_workify_name_rules_v1(p_tenant_id uuid,p_action text default 'list',p_rule jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $fn$
declare result jsonb; start_date date; end_date date; normalized_name text; vehicle_id uuid; changed integer;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,case when p_action='list' then 'kpi.read' else 'kpi.manage' end) then raise exception 'Behörighet saknas' using errcode='42501';end if;
 if p_action='save' then
  start_date:=(p_rule->>'valid_from')::date; end_date:=nullif(p_rule->>'valid_to','')::date;
  normalized_name:=lower(regexp_replace(trim(p_rule->>'name'),'[[:space:]]+',' ','g')); vehicle_id:=(p_rule->>'vehicle_object_id')::uuid;
  if start_date is null or length(normalized_name) not between 1 and 200 or end_date<start_date then raise exception 'Kontrollera namn och giltighetsdatum';end if;
  perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||normalized_name,0));
  if not exists(select 1 from public.hub_objects where id=vehicle_id and tenant_id=p_tenant_id and object_type='Vehicle') then raise exception 'Välj ett fordon från Hubben';end if;
  if exists(select 1 from private.hub_workify_name_vehicle_rules where tenant_id=p_tenant_id and name_key=normalized_name and daterange(valid_from,valid_to,'[]') && daterange(start_date,end_date,'[]')) then raise exception 'Namnet har redan en regel under denna period';end if;
  insert into private.hub_workify_name_vehicle_rules(tenant_id,name,vehicle_object_id,valid_from,valid_to,created_by) values(p_tenant_id,trim(p_rule->>'name'),vehicle_id,start_date,end_date,auth.uid());
 elsif p_action='end' then
  end_date:=(p_rule->>'valid_to')::date;
  update private.hub_workify_name_vehicle_rules set valid_to=end_date where tenant_id=p_tenant_id and id=(p_rule->>'id')::uuid and end_date>=valid_from and (valid_to is null or end_date<=valid_to);
  if not found then raise exception 'Ogiltigt slutdatum';end if;
 elsif p_action='apply' then
  update public.kpi_import_rows set allocation=coalesce(allocation,'{}') where tenant_id=p_tenant_id and data_kind='revenue' and source_data ? 'Ordernummer' and vehicle_object_id is null and nullif(trim(source_data->>'RegNr'),'') is null and nullif(trim(source_data->>'Fordon'),'') is null and amount<>0;
  get diagnostics changed=row_count;
  update public.kpi_import_batches b set valid_row_count=s.valid,invalid_row_count=s.invalid,status=case when s.invalid=0 then 'completed' else 'needs_review' end from (select batch_id,count(*)filter(where is_valid) valid,count(*)filter(where not is_valid) invalid from public.kpi_import_rows where tenant_id=p_tenant_id and data_kind='revenue' group by batch_id)s where b.id=s.batch_id and b.tenant_id=p_tenant_id;
 elsif p_action<>'list' then raise exception 'Ogiltig åtgärd';end if;
 select jsonb_build_object('rules',coalesce((select jsonb_agg(to_jsonb(r)||jsonb_build_object('vehicle_label',coalesce(o.data->>'registration_number',o.data->>'name',o.id::text)) order by r.name,r.valid_from) from private.hub_workify_name_vehicle_rules r join public.hub_objects o on o.id=r.vehicle_object_id where r.tenant_id=p_tenant_id),'[]'),
 'vehicles',coalesce((select jsonb_agg(jsonb_build_object('id',id,'label',coalesce(data->>'registration_number',data->>'name',id::text)) order by data->>'registration_number') from public.hub_objects where tenant_id=p_tenant_id and object_type='Vehicle'),'[]'),
 'names',coalesce((select jsonb_agg(s order by s.rows desc) from(select trim(source_data->>'Förare') name,count(*) rows,sum(amount) amount from public.kpi_import_rows where tenant_id=p_tenant_id and data_kind='revenue' and source_data ? 'Ordernummer' and amount<>0 and nullif(trim(source_data->>'RegNr'),'') is null and nullif(trim(source_data->>'Fordon'),'') is null and nullif(trim(source_data->>'Förare'),'') is not null group by 1)s),'[]'),'processed',changed) into result;
 return result;
end $fn$;
revoke all on function public.hub_workify_name_rules_v1(uuid,text,jsonb) from public,anon;
grant execute on function public.hub_workify_name_rules_v1(uuid,text,jsonb) to authenticated;

create function private.hub_workify_name_fallback_v1() returns trigger language plpgsql security definer set search_path='' as $fn$
declare rule private.hub_workify_name_vehicle_rules; label text; article record; errors jsonb;
begin
 if new.data_kind<>'revenue' or not(new.source_data ? 'Ordernummer') then return new;end if;
 if new.amount=0 or (new.amount is null and nullif(trim(new.source_data->>'Summa'),'') is null) then
  new.amount:=0;new.is_valid:=true;new.validation_errors:='[]';new.vehicle_registration:=null;new.vehicle_object_id:=null;
  new.allocation:=coalesce(new.allocation,'{}')||jsonb_build_object('target','ignored','resolution','workify_no_amount');return new;
 end if;
 -- A supplied registration/vehicle, manual assignment or project carrier always wins.
 if nullif(trim(new.source_data->>'RegNr'),'') is not null or nullif(trim(new.source_data->>'Fordon'),'') is not null or new.vehicle_object_id is not null or new.vehicle_registration is not null or new.occurred_on is null then return new;end if;
 select * into article from public.kpi_workify_article_rules where tenant_id=new.tenant_id and enabled and article_number=new.source_data->>'Artikelnummer' and new.occurred_on between valid_from and coalesce(valid_to,'infinity'::date) order by valid_from desc limit 1;
 if not found or article.target_type<>'vehicle' or article.revenue_category in ('ignored','tipp','tipping','material') then return new;end if;
 select * into rule from private.hub_workify_name_vehicle_rules where tenant_id=new.tenant_id and name_key=lower(regexp_replace(trim(new.source_data->>'Förare'),'[[:space:]]+',' ','g')) and new.occurred_on between valid_from and coalesce(valid_to,'infinity'::date);
 if not found then return new;end if;
 select coalesce(data->>'registration_number',data->>'name') into label from public.hub_objects where id=rule.vehicle_object_id and tenant_id=new.tenant_id and object_type='Vehicle';
 if nullif(label,'') is null then return new;end if;
 select coalesce(jsonb_agg(e),'[]') into errors from jsonb_array_elements_text(new.validation_errors)e where e not in ('Workify-artikeln ska till fordon: registreringsnummer behöver mappas','Fordonsbeteckning saknar verifierad regnummerkoppling');
 new.vehicle_object_id:=rule.vehicle_object_id;new.vehicle_registration:=label;new.project_reference:=null;new.validation_errors:=errors;new.is_valid:=jsonb_array_length(errors)=0;
 new.allocation:=coalesce(new.allocation,'{}')-'project_carrier_reference'-'project_carrier_fallback'||jsonb_build_object('target','vehicle','resolution','confirmed_workify_name_fallback','name_rule_id',rule.id,'name_rule_valid_from',rule.valid_from,'resolved_name',rule.name);
 return new;
end $fn$;
revoke all on function private.hub_workify_name_fallback_v1() from public,anon,authenticated;
create trigger a_workify_name_fallback before insert or update on public.kpi_import_rows for each row execute function private.hub_workify_name_fallback_v1();
-- Amountless information rows do not enter financial or internal-transfer readers.
do $patch$ declare signature text; definition text; begin
 foreach signature in array array['private.hub_kpi_financial_facts_v1(uuid,date,date)','private.hub_kpi_financial_month_facts_v1(uuid,date,date,integer[])'] loop
 definition:=pg_get_functiondef(signature::regprocedure);
 definition:=replace(definition,'where x.tenant_id=p_tenant_id and x.is_valid','where x.tenant_id=p_tenant_id and (x.data_kind<>''revenue'' or x.amount<>0) and x.is_valid');execute definition;
 end loop;
end $patch$;
do $patch$ declare definition text; begin
 definition:=pg_get_functiondef('public.hub_kpi_resolve_workify_import_v1(uuid,uuid)'::regprocedure);
 definition:=replace(definition,'when nullif(trim(r.source_data->>''RegNr''),'''') is null','when r.vehicle_object_id is null and nullif(trim(r.source_data->>''RegNr''),'''') is null');execute definition;
 definition:=pg_get_functiondef('public.hub_kpi_internal_transfers_v1(uuid,date,date,integer[])'::regprocedure);
 definition:=replace(definition,'from linked where not','from linked where amount<>0 and not');execute definition;
end $patch$;
-- Backfill is performed through the authenticated rule action, preserving audit identity.
