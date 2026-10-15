-- Apply after the monthly NEXT/time report migrations when refreshing an existing generation.
-- This changes only derived-report cache identity, not source or financial facts.
begin;
select set_config('request.jwt.claim.sub','5a6fa4c4-5427-47fa-9835-d997fe81c7d5',true);
update private.hub_kpi_report_state set correction_revision=correction_revision+1
where tenant_id='944597b6-9c46-4bef-998d-f19e23c4245b'and public.hub_has_permission(tenant_id,'kpi.manage');
commit;
