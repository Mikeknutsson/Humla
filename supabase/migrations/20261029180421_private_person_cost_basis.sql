create table private.hub_person_cost_basis_v1(
tenant_id uuid not null,person_id uuid not null references public.hub_objects(id),valid_from date not null,valid_to date,
monthly_salary numeric not null check(monthly_salary>0),approved_by uuid not null,approved_at timestamptz not null default now(),
primary key(tenant_id,person_id,valid_from),check(valid_to is null or valid_to>=valid_from));
alter table private.hub_person_cost_basis_v1 enable row level security;
revoke all on private.hub_person_cost_basis_v1 from public,anon,authenticated;
create function private.hub_person_cost_salary_v1(p_tenant uuid,p_person uuid,p_date date,p_default numeric)returns numeric
language sql stable set search_path=''as $$
select coalesce((select monthly_salary from private.hub_person_cost_basis_v1 where tenant_id=p_tenant and person_id=p_person and valid_from<=p_date and(valid_to is null or valid_to>=p_date)order by valid_from desc limit 1),p_default)
$$;
revoke all on function private.hub_person_cost_salary_v1(uuid,uuid,date,numeric)from public,anon,authenticated;
create table private.hub_person_cost_reprojection_v1(
tenant_id uuid not null,generation_id uuid not null references private.hub_kpi_report_generations(id)on delete cascade,
fact_id text not null,before_fact jsonb not null,updated_at timestamptz not null default now(),primary key(tenant_id,generation_id,fact_id));
alter table private.hub_person_cost_reprojection_v1 enable row level security;
revoke all on private.hub_person_cost_reprojection_v1 from public,anon,authenticated;
do $migration$
declare d text;
begin
select pg_get_functiondef('private.hub_kpi_financial_month_facts_v1(uuid,date,date,integer[])'::regprocedure)into d;
d:=replace(d,')*c.salary/(c.wh*52/12)*c.load pc',$new$)*private.hub_person_cost_salary_v1(p_tenant_id,(select k.object_id from public.hub_identity_keys k where k.tenant_id=p_tenant_id and k.identity_type='transpa_employee_id'and k.identity_value=t.employee_id and k.confidence=1 limit 1),t.work_date,c.salary)/(c.wh*52/12)*c.load pc$new$);
if position('hub_person_cost_salary_v1'in d)=0 then raise exception 'Financial model anchor missing';end if;
execute d;
select pg_get_functiondef('private.hub_approved_time_cost_basis_v1(uuid,uuid)'::regprocedure)into d;
d:=replace(d,'*s.monthly_salary/(s.weekly_hours*52/12)',$new$*private.hub_person_cost_salary_v1(p_tenant,s.person_id,s.work_date,s.monthly_salary)/(s.weekly_hours*52/12)$new$);
if position('hub_person_cost_salary_v1'in d)=0 then raise exception 'Time model anchor missing';end if;
execute d;
end $migration$;