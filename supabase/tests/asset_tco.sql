-- Run in SQL editor as postgres. All fixtures are rolled back.
begin;
set local request.jwt.claim.sub='5a6fa4c4-5427-47fa-9835-d997fe81c7d5';
do $$
declare tenant uuid:='944597b6-9c46-4bef-998d-f19e23c4245b'; asset_id uuid; report jsonb; asset jsonb; meter numeric; own jsonb; i integer; rejected boolean; payload jsonb;
begin
 select id into asset_id from public.hub_objects where tenant_id=tenant and object_type='Vehicle' and data->>'vehicle_type'='Släpvagn' and public.hub_resolve_canonical_object_v1(tenant,id)=id order by id limit 1;
 if asset_id is null then raise exception 'Test requires a canonical trailer';end if;
 own:=jsonb_build_object('asset_class','trailer','purchase_date','2025-09-01','purchase_cost',300000,'residual_value',60000,'holding_months',60,'meter_type','none','model_year',2020,'variant','test fixture','price_basis','net');
 perform public.hub_asset_tco_save_v1(tenant,asset_id,'ownership',own);
 report:=public.hub_asset_tco_v1(tenant,current_date,asset_id);asset:=report#>'{assets,0}';
 if (asset->>'monthly_depreciation')::numeric<>4000 or asset->>'tco_per_unit' is not null then raise exception 'Depreciation / trailer usage failed';end if;
 report:=public.hub_asset_tco_v1(tenant,'2025-09-01',asset_id);
 if (report#>>'{assets,0,depreciation}')::numeric<>0 then raise exception 'Purchase-day depreciation must be zero';end if;
 report:=public.hub_asset_tco_v1(tenant,'2026-09-01',asset_id);
 if abs((report#>>'{assets,0,depreciation}')::numeric-48000)>150 then raise exception 'Annual depreciation failed';end if;
 for i in 1..3 loop
  payload:=jsonb_build_object('source',case when i=1 then 'Klaravik' else 'Blinto' end,'url','https://example.org/tco-test-'||i,'listing_identity','tco-test-'||i,'title','Test trailer','price',100000+i*10000,'price_basis','net','price_type','sold','observed_on',current_date,'model_year',2020,'comparable_confirmed',true,'sale_confirmed',true);
  perform public.hub_asset_tco_save_v1(tenant,asset_id,'comparable',payload);
 end loop;
 -- An unconfirmed highest bid must not be counted as a sale.
 payload:=payload||jsonb_build_object('url','https://example.org/tco-test-unconfirmed','listing_identity','tco-test-unconfirmed','price',900000,'sale_confirmed',false);
 perform public.hub_asset_tco_save_v1(tenant,asset_id,'comparable',payload);
 -- Neither stale nor mismatched VAT/year evidence may change the estimate.
 perform public.hub_asset_tco_save_v1(tenant,asset_id,'comparable',payload||jsonb_build_object('url','https://example.org/tco-test-gross','listing_identity','tco-test-gross','sale_confirmed',true,'price_basis','gross'));
 perform public.hub_asset_tco_save_v1(tenant,asset_id,'comparable',payload||jsonb_build_object('url','https://example.org/tco-test-old','listing_identity','tco-test-old','sale_confirmed',true,'observed_on',current_date-181));
 perform public.hub_asset_tco_save_v1(tenant,asset_id,'comparable',payload||jsonb_build_object('url','https://example.org/tco-test-year','listing_identity','tco-test-year','sale_confirmed',true,'model_year',2010));
 report:=public.hub_asset_tco_v1(tenant,current_date,asset_id);asset:=report#>'{assets,0}';
 if (asset#>>'{estimate,n}')::integer<>3 or (asset#>>'{estimate,median}')::numeric<>120000 or (asset#>>'{estimate,mean}')::numeric<>120000 then raise exception 'Comparable exclusions / median failed';end if;
 rejected:=false;
 begin perform public.hub_asset_tco_save_v1(tenant,asset_id,'comparable',payload);exception when unique_violation then rejected:=true;end;
 if not rejected then raise exception 'Duplicate guard failed';end if;
 perform public.hub_asset_tco_save_v1(tenant,asset_id,'accept_estimate','{}');
 report:=public.hub_asset_tco_v1(tenant,current_date,asset_id);
 if (report#>>'{assets,0,market_value}')::numeric<>120000 or jsonb_array_length(report->'valuations')<>1 then raise exception 'Valuation history failed';end if;
 if report::text ~ '"personnel"|"revenue"' then raise exception 'Narrow fleet report must not return salaries or revenues';end if;
 perform public.hub_asset_tco_save_v1(tenant,asset_id,'ownership',own||'{"price_basis":"gross"}');
 report:=public.hub_asset_tco_v1(tenant,current_date,asset_id);
 if report#>>'{assets,0,tco}' is not null then raise exception 'Mixed VAT bases must not produce TCO';end if;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
 rejected:=false;
 begin perform public.hub_asset_tco_v1(tenant,current_date,asset_id);exception when insufficient_privilege then rejected:=true;end;
 if not rejected then raise exception 'Unauthorised read was allowed';end if;
 rejected:=false;
 begin perform public.hub_asset_tco_save_v1(tenant,asset_id,'ownership',own);exception when insufficient_privilege then rejected:=true;end;
 if not rejected then raise exception 'Unauthorised write was allowed';end if;
end $$;
select 'TCO, comparisons, duplicate guards, history, VAT and permission checks passed; fixtures rolled back' result;
rollback;
