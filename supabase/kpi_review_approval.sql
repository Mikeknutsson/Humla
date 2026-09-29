-- Atomic approval of an existing quarantined transaction; original source is immutable.
create table public.kpi_review_events (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.hub_tenants(id),
 row_id uuid not null references public.kpi_import_rows(id), actor uuid not null references auth.users(id),
 reason text not null, previous jsonb not null, current jsonb not null, created_at timestamptz not null default now()
);
create index on public.kpi_review_events(tenant_id);
create index on public.kpi_review_events(row_id);
create index on public.kpi_review_events(actor);
alter table public.kpi_review_events enable row level security;
revoke all on public.kpi_review_events from public,anon,authenticated;
grant select on public.kpi_review_events to authenticated;
create policy kpi_review_read on public.kpi_review_events for select to authenticated using(public.hub_has_permission(tenant_id,'kpi.read'));
-- Trigger alone can append immutable audit records; no client write grant.
create function private.kpi_review_audit() returns trigger language plpgsql security definer set search_path=pg_catalog as $$
begin
 if auth.uid() is null then raise exception 'Inloggning krävs'; end if;
 if new.source_data is distinct from old.source_data or new.tenant_id<>old.tenant_id or new.batch_id<>old.batch_id or new.id<>old.id or new.data_kind<>old.data_kind then raise exception 'Original och identitet får inte ändras'; end if;
 insert into public.kpi_review_events(tenant_id,row_id,actor,reason,previous,current) values(new.tenant_id,new.id,auth.uid(),coalesce(new.allocation->>'review_reason','Manuell uppdatering'),to_jsonb(old),to_jsonb(new));
 return new;
end $$;
revoke all on function private.kpi_review_audit() from public,anon,authenticated;
create trigger kpi_review_audit before update on public.kpi_import_rows for each row execute function private.kpi_review_audit();

create function public.kpi_approve_review(p_row_id uuid,p_values jsonb,p_reason text) returns jsonb language plpgsql security invoker set search_path=pg_catalog as $$
declare r public.kpi_import_rows; v public.kpi_import_rows; b public.kpi_import_batches; target text; total integer; good integer;
begin
 if auth.uid() is null then raise exception 'Inloggning krävs'; end if;
 select * into r from public.kpi_import_rows where id=p_row_id;
 if not found or not public.hub_has_permission(r.tenant_id,'kpi.manage') then raise exception 'Behörighet saknas'; end if;
 -- Serialize approvals within the batch so counts and status cannot race.
 select * into b from public.kpi_import_batches where id=r.batch_id and tenant_id=r.tenant_id for update;
 if b.status not in ('completed','needs_review') then raise exception 'Importen är inte klar för granskning'; end if;
 select * into r from public.kpi_import_rows where id=p_row_id for update;
 if r.is_valid then raise exception 'Raden är redan godkänd. Ladda om granskningen.'; end if;
 if length(trim(coalesce(p_reason,''))) not between 3 and 1000 then raise exception 'Ange en motivering (3–1000 tecken)'; end if;
 v := jsonb_populate_record(null::public.kpi_import_rows,p_values);
 if v.occurred_on is null then raise exception 'Giltigt datum krävs'; end if;
 if r.data_kind in ('revenue','cost','fuel') and (v.amount is null or v.amount::text in ('NaN','Infinity','-Infinity')) then raise exception 'Giltigt belopp krävs'; end if;
 if v.vehicle_registration is not null and v.vehicle_registration !~ '^[A-Z]{3}[0-9]{2}[A-Z0-9]$' then raise exception 'Giltigt registreringsnummer krävs'; end if;
 if exists(select 1 from unnest(array[v.quantity,v.available_hours,v.occupied_hours,v.paid_hours,v.billable_hours]) n where n::text in ('NaN','Infinity','-Infinity')) then raise exception 'Ogiltigt tal'; end if;
 if v.available_hours<0 or v.occupied_hours<0 or v.paid_hours<0 or v.billable_hours<0 then raise exception 'Timmar får inte vara negativa'; end if;
 if r.data_kind='vehicle_activity' and (v.available_hours is null or v.occupied_hours is null or v.occupied_hours>v.available_hours) then raise exception 'Kontrollera tillgängliga och belagda timmar'; end if;
 if r.data_kind='driver_time' and (nullif(trim(v.employee_number),'') is null or v.paid_hours is null or v.billable_hours is null or v.billable_hours>v.paid_hours) then raise exception 'Kontrollera anställningsnummer och timmar'; end if;
 if r.data_kind='cost' then
  if coalesce(v.account,'') !~ '^\d{1,8}$' then raise exception 'Giltigt konto krävs'; end if;
  if not exists(select 1 from public.kpi_account_mappings m where m.tenant_id=r.tenant_id and m.enabled and v.account::integer between m.account_from and m.account_to and v.occurred_on>=m.valid_from and (m.valid_to is null or v.occurred_on<=m.valid_to)) then raise exception 'Kontot saknar aktiv regel. Skapa kontomappningen först.'; end if;
 end if;
 target:=p_values->>'review_target';
 if r.data_kind='revenue' then
  if target='project' and nullif(trim(v.project_reference),'') is not null then v.vehicle_registration:=null; v.employee_number:=null;
  elsif target='vehicle' and v.vehicle_registration is not null then v.project_reference:=null; v.employee_number:=null;
  else raise exception 'Välj projekt eller fordon och ange kopplingen'; end if;
 end if;
 update public.kpi_import_rows set occurred_on=v.occurred_on,amount=v.amount,quantity=v.quantity,
 vehicle_registration=v.vehicle_registration,vehicle_object_id=null,employee_number=v.employee_number,employee_object_id=null,
 project_reference=v.project_reference,cost_center=v.cost_center,account=v.account,description=v.description,
 available_hours=v.available_hours,occupied_hours=v.occupied_hours,paid_hours=v.paid_hours,billable_hours=v.billable_hours,
 is_valid=true,validation_errors='[]',allocation=coalesce(r.allocation,'{}')||jsonb_build_object('review_reason',trim(p_reason),'reviewed_by',auth.uid(),'reviewed_at',now(),'target',coalesce(target,'manual'),'manual_override',true)
 where id=r.id;
 select count(*),count(*) filter(where is_valid) into total,good from public.kpi_import_rows where batch_id=r.batch_id;
 update public.kpi_import_batches set row_count=total,valid_row_count=good,invalid_row_count=total-good,status=case when total=good then 'completed' else 'needs_review' end,
 period_start=(select min(occurred_on) from public.kpi_import_rows where batch_id=r.batch_id and is_valid),
 period_end=(select max(occurred_on) from public.kpi_import_rows where batch_id=r.batch_id and is_valid),
 error_summary=coalesce((select jsonb_agg(jsonb_build_object('row',x.row_number,'errors',x.validation_errors)) from (select row_number,validation_errors from public.kpi_import_rows where batch_id=r.batch_id and not is_valid order by row_number limit 50)x),'[]') where id=r.batch_id;
 return jsonb_build_object('id',r.id,'remaining',total-good);
end $$;
revoke all on function public.kpi_approve_review(uuid,jsonb,text) from public,anon;
grant execute on function public.kpi_approve_review(uuid,jsonb,text) to authenticated;
