begin;
select set_config('request.jwt.claim.sub','5a6fa4c4-5427-47fa-9835-d997fe81c7d5',true);
do $$
declare t uuid:='944597b6-9c46-4bef-998d-f19e23c4245b';p uuid:='d0e501bc-b300-479e-8941-e9227b635113';r jsonb;g uuid;fid text;original_amount numeric;
begin
 r:=public.hub_project_revenue_statement_v1(t,p);
 assert (r->>'billed_total')::numeric=485798,'Approved cumulative revenue';
 assert (r->>'imported_project_revenue')::numeric=485797.54,'Already imported revenue remains included once';
 assert (r->>'unperiodized_difference')::numeric=0.46,'Difference from rounded source statement';
 select active_generation into g from private.hub_kpi_report_state where tenant_id=t;
 select fact_id,amount into fid,original_amount from private.hub_kpi_prepared_facts where tenant_id=t and generation_id=g and project='12716' and source='NEXT' and kind='revenue' and occurred_on<='2026-10-15' limit 1;
 assert fid is not null,'Expected imported invoice fixture';
 update private.hub_kpi_prepared_facts set amount=original_amount+0.46 where tenant_id=t and generation_id=g and fact_id=fid;
 r:=public.hub_project_revenue_statement_v1(t,p);
 assert (r->>'billed_total')::numeric=485798,'Later imports must never add the control total again';
 assert (r->>'unperiodized_difference')::numeric=0,'Additional dated evidence reconciles cumulative statement';
 perform set_config('request.jwt.claim.sub','',true);
 begin
  perform public.hub_project_revenue_statement_v1(t,p);
  raise exception 'Anonymous access unexpectedly allowed';
 exception when insufficient_privilege then null;end;
end $$;
rollback;
