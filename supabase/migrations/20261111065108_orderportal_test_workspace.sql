-- Additive test workspace. No KPI writes, billing hooks or Workify mutations.
create table public.hub_orderportal_orders (
 id uuid primary key references public.hub_objects(id),
 tenant_id uuid not null references public.hub_tenants(id),
 request_id uuid not null,
 order_number text not null,
 payload jsonb not null,
 amount numeric(16,2) not null default 0,
 version integer not null default 1,
 is_test boolean not null default true check(is_test),
 created_by uuid not null,
 updated_at timestamptz not null default now(),
 unique(tenant_id,request_id),unique(tenant_id,order_number)
);
create table public.hub_orderportal_history (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.hub_tenants(id),
 order_id uuid not null references public.hub_orderportal_orders(id),
 version integer not null,
 actor_id uuid not null,
 before_data jsonb,
 after_data jsonb not null,
 created_at timestamptz not null default now(),
 unique(order_id,version)
);
alter table public.hub_orderportal_orders enable row level security;
alter table public.hub_orderportal_history enable row level security;
revoke all on public.hub_orderportal_orders,public.hub_orderportal_history from anon,authenticated;
grant select on public.hub_orderportal_orders,public.hub_orderportal_history to authenticated;
create policy orderportal_read on public.hub_orderportal_orders for select to authenticated using(public.hub_has_permission(tenant_id,'kpi.manage'));
create policy orderportal_history_read on public.hub_orderportal_history for select to authenticated using(public.hub_has_permission(tenant_id,'kpi.manage'));
create index orderportal_history_tenant on public.hub_orderportal_history(tenant_id,order_id);

create function public.hub_orderportal_imports(p_tenant_id uuid) returns jsonb language sql stable security invoker set search_path='' as $$
 with selected as (
 select distinct r.source_data->>'Ordernummer' number from public.kpi_import_rows r
 where r.tenant_id=p_tenant_id and public.hub_has_permission(p_tenant_id,'kpi.manage')
 and r.source_system='workify_file' and r.data_kind='revenue' and r.occurred_on between '2026-10-01' and '2026-10-31'
 ), rows as (
 select r.id,r.tenant_id,r.batch_id,r.occurred_on,r.amount,r.quantity,r.vehicle_object_id,r.employee_object_id,r.source_fingerprint,r.external_transaction_id,r.source_data,r.created_at,r.is_valid,r.validation_errors
 from public.kpi_import_rows r where r.tenant_id=p_tenant_id and public.hub_has_permission(p_tenant_id,'kpi.manage')
 and r.source_system='workify_file' and r.data_kind='revenue'
 and (r.source_data->>'Ordernummer' in(select number from selected) or (nullif(r.source_data->>'Ordernummer','') is null and r.occurred_on between '2026-10-01' and '2026-10-31'))
 ) select coalesce(jsonb_agg(to_jsonb(rows)),'[]'::jsonb) from rows;
$$;
revoke all on function public.hub_orderportal_imports(uuid) from public,anon;
grant execute on function public.hub_orderportal_imports(uuid) to authenticated;

-- Narrow privileged write boundary: canonical identity + order + audit commit atomically.
-- No direct table writes are granted to application users.
create function private.orderportal_save(p_tenant_id uuid,p_id uuid,p_expected_version integer,p_request_id uuid,p_payload jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;v_old public.hub_orderportal_orders;v_payload jsonb;v_amount numeric;v_ref uuid;v_key text;v_type text;v_line jsonb;v_number text;v_version integer;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.manage') then raise exception 'permission_denied'; end if;
 if p_request_id is null or jsonb_typeof(p_payload)<>'object' or octet_length(p_payload::text)>250000 then raise exception 'invalid_payload';end if;
 if coalesce(p_payload->>'title','')='' or nullif(p_payload->>'customerId','') is null then raise exception 'customer_title_required';end if;
 if coalesce(p_payload->>'status','') not in ('Utkast','Planerad','Pågående','Utförd','Faktureringsklar','Avbruten') then raise exception 'invalid_status';end if;
 if coalesce(p_payload->>'start','') !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$' or coalesce(p_payload->>'end','') !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$' or (p_payload->>'end')::timestamp <= (p_payload->>'start')::timestamp then raise exception 'invalid_dates';end if;
 foreach v_key in array array['customerId','projectId','vehicleId','driverId'] loop
 v_ref=nullif(p_payload->>v_key,'')::uuid;
 if v_ref is not null then
 v_type=case v_key when 'customerId' then 'Customer' when 'projectId' then 'Project' when 'vehicleId' then 'Vehicle' else 'Person' end;
 if not exists(select 1 from public.hub_objects where id=v_ref and tenant_id=p_tenant_id and lower(object_type)=lower(v_type) and status='active') then raise exception 'invalid_canonical_reference';end if;
 end if;
 end loop;
 if jsonb_typeof(p_payload->'lines') is distinct from 'array' or jsonb_array_length(p_payload->'lines')>200 then raise exception 'invalid_lines';end if;
 v_amount=0;
 for v_line in select value from jsonb_array_elements(p_payload->'lines') loop
 if coalesce(v_line->>'label','')='' or coalesce(v_line->>'date','') !~ '^\d{4}-\d{2}-\d{2}$' or jsonb_typeof(v_line->'quantity') is distinct from 'number' or jsonb_typeof(v_line->'price') is distinct from 'number' or (v_line->>'quantity')::numeric<0 or (v_line->>'price')::numeric<0 then raise exception 'invalid_line';end if;
 perform (v_line->>'date')::date;
 v_amount=v_amount+round((v_line->>'quantity')::numeric*(v_line->>'price')::numeric,2);
 end loop;
 if p_payload->>'status'='Faktureringsklar' and jsonb_array_length(p_payload->'lines')=0 then raise exception 'lines_required';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||p_request_id::text,0));
 if p_id is null then
 select id into v_id from public.hub_orderportal_orders where tenant_id=p_tenant_id and request_id=p_request_id;
 if found then return v_id;end if;
 v_id=gen_random_uuid();v_number='TEST-'||upper(substr(replace(v_id::text,'-',''),1,12));v_version=1;
 insert into public.hub_objects(id,tenant_id,object_type,data,source_of_truth) values(v_id,p_tenant_id,'TestTransportOrder',jsonb_build_object('is_test',true,'display_name',v_number),'humla_orderportal_test');
 else
 select * into v_old from public.hub_orderportal_orders where id=p_id and tenant_id=p_tenant_id for update;
 if not found then raise exception 'order_not_found';end if;
 if v_old.version is distinct from p_expected_version then raise exception 'version_conflict';end if;
 v_id=v_old.id;v_number=v_old.order_number;v_version=v_old.version+1;
 end if;
 v_payload=p_payload||jsonb_build_object('id',v_id,'number',v_number,'source','humla','version',v_version,'amount',v_amount,'is_test',true,'issues','[]'::jsonb);
 -- Recalculate every line server-side. Never accept client-computed totals.
 v_payload=jsonb_set(v_payload,'{lines}',coalesce((select jsonb_agg(value||jsonb_build_object('amount',round((value->>'quantity')::numeric*(value->>'price')::numeric,2),'valid',true,'errors','[]'::jsonb)) from jsonb_array_elements(p_payload->'lines')),'[]'::jsonb));
 if p_id is null then
 insert into public.hub_orderportal_orders(id,tenant_id,request_id,order_number,payload,amount,created_by) values(v_id,p_tenant_id,p_request_id,v_number,v_payload,v_amount,auth.uid());
 else
 update public.hub_orderportal_orders set payload=v_payload,amount=v_amount,version=v_version,updated_at=now() where id=v_id;
 end if;
 insert into public.hub_orderportal_history(tenant_id,order_id,version,actor_id,before_data,after_data) values(p_tenant_id,v_id,v_version,auth.uid(),v_old.payload,v_payload);
 return v_id;
end $$;
revoke all on function private.orderportal_save(uuid,uuid,integer,uuid,jsonb) from public,anon;
grant execute on function private.orderportal_save(uuid,uuid,integer,uuid,jsonb) to authenticated;
create function public.hub_orderportal_save(p_tenant_id uuid,p_id uuid,p_expected_version integer,p_request_id uuid,p_payload jsonb)
returns uuid language sql security invoker set search_path='' as $$ select private.orderportal_save(p_tenant_id,p_id,p_expected_version,p_request_id,p_payload) $$;
revoke all on function public.hub_orderportal_save(uuid,uuid,integer,uuid,jsonb) from public,anon;
grant execute on function public.hub_orderportal_save(uuid,uuid,integer,uuid,jsonb) to authenticated;
comment on table public.hub_orderportal_orders is 'Test only: never a billing source. Uses canonical TestTransportOrder objects; no KPI or Workify write path.';
