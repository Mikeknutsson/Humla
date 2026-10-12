-- Canonical cost-center alias resolution shared by Hub and KPI.
-- Preserve source values; normalize only when joining/filtering.
create or replace function public.hub_canonical_cost_center(p_value text)
returns text
language sql immutable parallel safe
as $$
  select case
    when lower(btrim(coalesce(p_value,''))) in ('30','transport') then '30'
    when lower(btrim(coalesce(p_value,''))) in ('20','sortergården','sortergarden','sortergård','sortergard') then '20'
    when lower(btrim(coalesce(p_value,''))) in ('40','verkstad') then '40'
    when lower(btrim(coalesce(p_value,''))) in ('90','övrigt','ovrigt') then '90'
    else nullif(btrim(p_value),'')
  end
$$;
comment on function public.hub_canonical_cost_center(text) is
'Canonical code for display-name and numeric cost-center aliases; source data unchanged.';
-- Security invoker keeps the underlying register protected by its own RLS.
create or replace view public.hub_kpi_project_register_canonical_v1
with (security_invoker = true)
as
select tenant_id,project_number,project_name,project_manager,project_status,
       project_category,cost_center as source_cost_center,
       public.hub_canonical_cost_center(cost_center) as cost_center,
       imported_at
from public.kpi_next_project_register;
-- Regression expectations:
-- select hub_canonical_cost_center('Transport')='30'
--    and hub_canonical_cost_center('30')='30';
