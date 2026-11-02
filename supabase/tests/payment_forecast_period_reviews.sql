-- Trusted operator test; all review changes roll back.
begin;
select set_config('request.jwt.claim.sub','5a6fa4c4-5427-47fa-9835-d997fe81c7d5',true);
do $$declare t uuid:='944597b6-9c46-4bef-998d-f19e23c4245b';r jsonb;begin
 begin perform public.hub_payment_forecast_reviews_v2(t,'ordinary','20','out','2026-10-01',true,'');raise exception 'Missing fingerprint was allowed';exception when raise_exception then if sqlerrm='Missing fingerprint was allowed'then raise;end if;end;
 r:=public.hub_payment_forecast_reviews_v2(t,'ordinary','30','out','2026-10-01',true,'Test complete month',repeat('a',64));
 assert exists(select 1 from jsonb_array_elements(r->'reviews')x where x->>'month'='2026-10-01' and x->>'scope'='ordinary'and x->>'center'='30'and x->>'kind'='out'and(x->>'reviewed')::boolean),'Review missing';
 r:=public.hub_payment_forecast_reviews_v2(t,'ordinary','30','out','2026-10-01',false,'Undo test');
 assert exists(select 1 from private.hub_payment_forecast_period_reviews_v1 where tenant_id=t and scope='ordinary'and center='30'and kind='out'and month='2026-10-01'and not reviewed and jsonb_array_length(history)>=2),'Review reversal lost audit';
 begin perform public.hub_payment_forecast_reviews_v2(t,'ordinary','30','out',date_trunc('month',current_date)::date,true,'',repeat('a',64));raise exception 'Current month was allowed';exception when raise_exception then if sqlerrm='Current month was allowed'then raise;end if;end;
 begin perform public.hub_payment_forecast_reviews_v2(t,'stena','30','out','2026-10-01',true,'',repeat('a',64));raise exception 'Stena expense scope was allowed';exception when raise_exception then if sqlerrm='Stena expense scope was allowed'then raise;end if;end;
 begin perform public.hub_payment_forecast_reviews_v2(gen_random_uuid());raise exception 'Other tenant was allowed';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub','',true);
 begin perform public.hub_payment_forecast_reviews_v2(t);raise exception 'Anonymous access was allowed';exception when insufficient_privilege then null;end;
end $$;
select 'PASS: explicit completed-month review, reversible audit, current-month/type validation and tenant/auth boundaries' verification;
rollback;
