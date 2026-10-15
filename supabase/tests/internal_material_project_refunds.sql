begin;
select set_config('request.jwt.claim.sub','5a6fa4c4-5427-47fa-9835-d997fe81c7d5',true);
do $$
declare t uuid:='944597b6-9c46-4bef-998d-f19e23c4245b';r jsonb;s jsonb;p jsonb;d jsonb;g uuid;sale numeric;cost numeric;ledger_before bigint;
begin
 select count(*)into ledger_before from public.kpi_internal_transfer_ledger where tenant_id=t;
 r:=public.hub_kpi_internal_material_project_refunds_v1(t,'2026-09-01','2026-09-30',array[9]);
 assert (r#>>'{totals,billed}')::numeric+(r->>'unresolved_billed')::numeric+(r->>'other_center_billed')::numeric=(r->>'all_material_billed')::numeric,'All published material revenue must reconcile';
 assert (select sum((x->>'refund')::numeric)from jsonb_array_elements(r->'projects')x)=(r#>>'{totals,refund}')::numeric,'Project refunds reconcile';
 assert (select sum((x->>'rows')::int)from jsonb_array_elements(r->'projects')x)=(r#>>'{totals,rows}')::int,'Rows counted once';
 assert exists(select 1 from jsonb_array_elements(r->'projects')x where x->>'project_id' is null),'Unresolved project references must remain visible';
 assert (select count(*)from public.kpi_internal_transfer_ledger where tenant_id=t)=ledger_before,'Read-only proposal must not alter ledger';
 select x into p from jsonb_array_elements(r->'projects')x where x->>'project_number'='12664';
 select x into d from jsonb_array_elements(p->'details')x where not(x->>'bundled')::boolean and not(x->>'fallback')::boolean and (x->>'billed')::numeric>0 and (x->>'purchase_cost')::numeric>0 limit 1;
 assert d is not null,'Expected credit fixture';
 sale:=(d->>'billed')::numeric;cost:=(d->>'purchase_cost')::numeric;
 select active_generation into g from private.hub_kpi_report_state where tenant_id=t;
 update private.hub_kpi_prepared_facts set amount=-sale,original=jsonb_set(original,'{_humla_material_separation,purchase,amount}',to_jsonb(-cost))where tenant_id=t and generation_id=g and fact_id=d->>'source_row';
 s:=public.hub_kpi_internal_material_project_refunds_v1(t,'2026-09-01','2026-09-30',array[9]);
 assert (s#>>'{totals,refund}')::numeric=(r#>>'{totals,refund}')::numeric-2*(sale-cost),'Credits preserve sign';
 perform set_config('request.jwt.claim.sub','',true);
 begin
  perform public.hub_kpi_internal_material_project_refunds_v1(t,'2026-09-01','2026-09-30',array[9]);
  raise exception 'Anonymous call unexpectedly allowed';
 exception when insufficient_privilege then null;end;
end $$;
rollback;
