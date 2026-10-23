-- Read existing published facts and roll back all generated report cache entries.
begin;
set local statement_timeout='120s';
select set_config('request.jwt.claim.sub','5a6fa4c4-5427-47fa-9835-d997fe81c7d5',true);
do $$
declare filters jsonb;r jsonb;m jsonb;previous_to date;g uuid;expected numeric;year integer;
 tenant uuid:='944597b6-9c46-4bef-998d-f19e23c4245b';today date:=(now()at time zone'Europe/Stockholm')::date;months integer[];
begin
 if private.hub_kpi_ytd_filters_v1(2026,'{"period_mode":"ytd"}','2026-10-19')->>'date_to'<>'2026-10-19' then raise exception 'Current date cutoff failed';end if;
 if private.hub_kpi_ytd_filters_v1(2025,'{"period_mode":"ytd"}','2026-10-19')->>'date_to'<>'2025-10-19' then raise exception 'Historical cutoff failed';end if;
 if private.hub_kpi_ytd_filters_v1(2022,'{"period_mode":"ytd"}','2024-02-29')->>'date_to'<>'2023-02-28' then raise exception 'Leap-year clamp failed';end if;
 if private.hub_kpi_ytd_filters_v1(2026,'{"period_mode":"ytd"}','2027-01-05')->>'date_to'<>'2027-01-05' then raise exception 'Calendar year rollover failed';end if;
 year:=extract(year from today)::int-case when extract(month from today)<9 then 1 else 0 end;
 select array_agg(x.m order by x.ord)into months from unnest(array[9,10,11,12,1,2,3,4,5,6,7,8])with ordinality x(m,ord)
 where ord<=case when extract(month from today)>=9 then extract(month from today)::int-8 else extract(month from today)::int+4 end;
 filters:=private.hub_kpi_ytd_filters_v1(year,'{"period_mode":"ytd"}');
 r:=public.hub_kpi_overview_months_v1(tenant,year,months,'30','{"period_mode":"ytd"}');
 if(r#>>'{period,to}')::date<>today then raise exception 'Overview metadata cutoff failed';end if;
 if(r#>>'{previous,period,to}')::date<>(today-interval'1 year')::date then raise exception 'Prior-year metadata cutoff failed';end if;
 select active_generation into g from private.hub_kpi_report_state where tenant_id=tenant;
 select coalesce(sum(amount),0)into expected from private.hub_kpi_report_display_facts_v1 where tenant_id=tenant and generation_id=g
 and cost_center='30'and kind='revenue'and occurred_on between make_date(year,9,1)and today;
 if abs((r#>>'{metrics,revenue}')::numeric-expected)>0.005 then raise exception 'Current revenue differs from exact daily facts';end if;
 select coalesce(sum(amount),0)into expected from private.hub_kpi_report_display_facts_v1 where tenant_id=tenant and generation_id=g
 and cost_center='30'and kind='revenue'and occurred_on between make_date(year-1,9,1)and(today-interval'1 year')::date;
 if abs((r#>>'{previous,metrics,revenue}')::numeric-expected)>0.005 then raise exception 'Prior revenue differs from exact daily facts';end if;
 m:=public.hub_kpi_monthly_transport_report_v1(tenant,year,extract(month from today)::int,'30','{"period_mode":"ytd"}');
 if(m#>>'{period,to}')::date<>today then raise exception 'Monthly current cutoff failed';end if;
 m:=public.hub_kpi_monthly_transport_report_v1(tenant,year-1,extract(month from today)::int,'30','{"period_mode":"ytd"}');
 if(m#>>'{period,to}')::date<>(today-interval'1 year')::date then raise exception 'Monthly comparison cutoff failed';end if;
end$$;
select 'PASS exact YTD dates, prior-year financial totals, monthly dates, fiscal rollover and leap day'as result;
rollback;
