-- Hub-owned, read-only comparison of equally filtered report snapshots.
create or replace function private.hub_kpi_yoy_value_v1(c numeric,p numeric,u text,complete boolean default true)
returns jsonb language sql immutable set search_path='' as $$
 select jsonb_build_object('current',c,'previous',p,
 'difference',case when c is not null and p is not null and complete then round(c-p,2) end,
 'change_pct',case when c is not null and p is not null and complete and p<>0 and u<>'%' then round(100*(c-p)/abs(p),2) end,
 'status',case when c is null or p is null then 'missing' when not complete then 'partial' when p=0 and u<>'%' then 'zero_base' else 'ready' end,
 'reason',case when c is null or p is null then 'Underlag saknas' when not complete then 'Ofullständigt underlag – förändring visas inte' end)
$$;
revoke all on function private.hub_kpi_yoy_value_v1(numeric,numeric,text,boolean) from public;
create or replace function public.hub_kpi_compare_snapshots_v1(p_tenant uuid,p_months integer[],p_part text,p_current jsonb,p_previous jsonb)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;finance_ok boolean;time_ok boolean;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant,'kpi.read') then raise exception 'KPI access required' using errcode='42501';end if;
 if p_part not in('overview','internal','billing','workshop') or cardinality(p_months) not between 1 and 12
 or exists(select 1 from unnest(p_months)m where m not between 1 and 12)
 or coalesce(jsonb_typeof(p_current),'null') not in('object','null') or coalesce(jsonb_typeof(p_previous),'null') not in('object','null')
 or coalesce(length(p_current::text),0)+coalesce(length(p_previous::text),0)>8000000 then raise exception 'Invalid comparison snapshots';end if;
 finance_ok:=p_current is not null and p_previous is not null and not exists(
 select 1 from unnest(p_months)m cross join (values(p_current),(p_previous))s(v)
 where not coalesce(v#>'{coverage,revenue_months}','[]'::jsonb) @> to_jsonb(array[m])
 or not coalesce(v#>'{coverage,cost_months}','[]'::jsonb) @> to_jsonb(array[m]));
 time_ok:=finance_ok and not exists(
 select 1 from (values(p_current),(p_previous))s(v),jsonb_array_elements(coalesce(v->'economic_units','[]'))e
 where coalesce((e->>'revenue')::numeric,0)>0 and coalesce((e->>'worked_hours')::numeric,0)<=0
 and exists(select 1 from jsonb_array_elements(coalesce(e->'children','[]'))ch where nullif(ch->>'vehicle','') is not null));
 with specs(section,path,label,unit,gate) as(values
('Ekonomi','metrics.revenue','Omsättning','kr','finance'),
('Ekonomi','metrics.total_cost','Totala kostnader','kr','finance'),
('Ekonomi','metrics.result','Resultat','kr','finance'),
('Ekonomi','metrics.margin_pct','Marginal','%','finance'),
('Ekonomi','metrics.diesel_share','Dieselandel','%','finance'),
('Ekonomi','metrics.revenue_per_vehicle','Omsättning per fordon','kr','finance'),
('Ekonomi','metrics.vehicle_utilization','Fordonsutnyttjande','%','time'),
('Kostnader','cost_categories.personnel','Personal','kr','finance'),
('Kostnader','cost_categories.fuel','Drivmedel','kr','finance'),
('Kostnader','cost_categories.service_repair','Service och reparation','kr','finance'),
('Kostnader','cost_categories.depreciation','Avskrivning','kr','finance'),
('Kostnader','cost_categories.fixed','Fasta kostnader','kr','finance'),
('Kostnader','cost_categories.material','Material','kr','finance'),
('Kostnader','cost_categories.tipp_deponi','Tipp och deponi','kr','finance'),
('Kostnader','cost_categories.hired','Inhyrt','kr','finance'),
('Kostnader','cost_categories.other','Övriga kostnader','kr','finance'),
('Drift & personal','efficiency.own_revenue','Egen omsättning','kr','finance'),
('Drift & personal','efficiency.hired_revenue','Inhyrd omsättning','kr','finance'),
('Drift & personal','efficiency.worked_hours','Arbetade timmar','h','time'),
('Drift & personal','efficiency.revenue_per_worked_hour','Omsättning per arbetad timme','kr/h','time'),
('Drift & personal','hired_capacity.hired_share_percent','Andel inhyrd omsättning','%','finance'),
('Drift & personal','transpa_vehicle_time.reported_hours','Rapporterad fordonstid','h','time'),
('Drift & personal','transpa_vehicle_time.available_hours','Tillgänglig fordonstid','h','time'),
('Drift & personal','transpa_vehicle_time.utilization','Beläggningsgrad fordon','%','time'),
('Drift & personal','transpa_vehicle_time.vehicle_count','Fordon med tidsunderlag','st','time'),
('Drift & personal','driver_productivity.total_hours','Förartimmar','h','time'),
('Drift & personal','driver_productivity.productive_hours','Produktiva förartimmar','h','time'),
('Drift & personal','driver_productivity.unclassified_hours','Oklassificerade förartimmar','h','time'),
('Drift & personal','driver_productivity.productive_percent','Produktiv tid','%','time'),
('Drift & personal','driver_attendance.attendance_percent','Närvaro','%','time'),
('Drift & personal','driver_attendance.sick_percent','Sjukfrånvaro','%','time'),
('Drift & personal','driver_attendance.vab_percent','VAB','%','time'),
('Drift & personal','driver_attendance.vacation_percent','Semester','%','time'),
('Drift & personal','driver_attendance.other_absence_percent','Övrig frånvaro','%','time'),
('Drift & personal','invoice_lead_time.average_days','Faktureringstid externa order','dagar','finance'),
('Drift & personal','invoice_lead_time.internal_average_days','Faktureringstid interna order','dagar','finance'),
('Drift & personal','invoice_lead_time.averaged_orders','Externa order i faktureringstid','st','finance'),
('Drift & personal','invoice_lead_time.internal_averaged_orders','Interna order i faktureringstid','st','finance'),
('Drift & personal','cost_efficiency.total_cost_per_hour','Total kostnad per timme','kr/h','time'),
('Drift & personal','cost_efficiency.direct_cost_per_hour','Direkt kostnad per timme','kr/h','time'),
('Drift & personal','cost_efficiency.common_cost_per_hour','Gemensam kostnad per timme','kr/h','time'),
('Drift & personal','cost_efficiency.overhead_cost_per_hour','Overhead per arbetad timme','kr/h','time'),
('Drift & personal','cost_efficiency.personnel_cost_per_hour','Personalkostnad per timme','kr/h','time'),
('Drift & personal','cost_efficiency.fuel_cost_per_hour','Drivmedel per timme','kr/h','time'),
('Drift & personal','cost_efficiency.service_repair_cost_per_hour','Service per timme','kr/h','time'),
('Drift & personal','cost_efficiency.fixed_cost_per_hour','Fast kostnad per timme','kr/h','time'),
('Drift & personal','cost_efficiency.contribution_per_hour','Täckningsbidrag per timme','kr/h','time'),
('Drift & personal','cost_efficiency.result_per_hour','Resultat per timme','kr/h','time'),
('Overhead','overhead.management_cost','Arbetsledning','kr','overhead'),
('Overhead','overhead.other_overhead','Övrig overhead','kr','overhead'),
('Overhead','overhead.total_overhead','Total overhead','kr','overhead'),
('Overhead','overhead.revenue','Omsättning','kr','finance'),
('Overhead','overhead.overhead_revenue_pct','Overhead / omsättning','%','overhead'),
('Overhead','overhead.management_revenue_pct','Arbetsledning / omsättning','%','overhead'),
('Overhead','overhead.management_overhead_pct','Arbetsledning / overhead','%','overhead'),
('Overhead','overhead.billable_hours','Debiterbara timmar','h','overhead'),
('Overhead','overhead.overhead_per_billable_hour','Overhead / debiterbar timme','kr/h','overhead'),
('Overhead','overhead.management_per_billable_hour','Arbetsledning / debiterbar timme','kr/h','overhead'),
('Kostnader','components.next_total_cost','NeXT-kostnader','kr','finance'),
('Kostnader','components.piusi_fuel_cost','Piusi-drivmedel','kr','finance'),
('Kostnader','components.transpa_personnel_cost','TransPA-personalkostnad','kr','time'),
('Kostnader','components.depreciation_cost','Avskrivningsunderlag','kr','finance'),
('Drift & personal','cost_efficiency.hired_cost_per_hour','Inhyrt per timme','kr/h','time'),
('Drift & personal','cost_efficiency.other_cost_per_hour','Övrig kostnad per timme','kr/h','time'),
('Drift & personal','cost_efficiency.material_cost_per_hour','Material per timme','kr/h','time'),
('Drift & personal','cost_efficiency.depreciation_cost_per_hour','Avskrivning per timme','kr/h','time'),
('Underlag','quality.total_rows','Underlagsrader','st','finance'),
('Underlag','quality.valid_rows','Giltiga rader','st','finance'),
('Underlag','quality.rows_without_vehicle','Rader utan fordon','st','finance'),
('Underlag','quality.rows_without_employee','Rader utan person','st','finance'),
('Interna intäkter','total','Fakturerat internt totalt','kr','internal'),
('Interna intäkter','material','Internt material','kr','internal'),
('Interna intäkter','tipp_deponi','Intern tipp och deponi','kr','internal'),
('Interna intäkter','transport','Intern transport','kr','internal'),
('Interna intäkter','other','Övrigt internt','kr','internal'),
('Interna intäkter','pending_amount','Ej fakturerat internt','kr','internal'),
('Interna intäkter','review_amount','Internt att granska','kr','internal'),
('Interna intäkter','total_percent','Intern andel av omsättningen','%','internal'),
('Interna intäkter','material_percent','Intern materialandel','%','internal'),
('Interna intäkter','tipp_deponi_percent','Intern tippandel','%','internal'),
('Interna intäkter','rows','Fakturerade interna rader','st','internal'),
('Interna intäkter','pending_rows','Ej fakturerade interna rader','st','internal'),
('Interna intäkter','review_rows','Interna rader att granska','st','internal'),
('Faktureringsbalans','invoiced','Externt fakturerat','kr','billing'),
('Faktureringsbalans','cost','Externa registrerade kostnader','kr','billing'),
('Faktureringsbalans','balance','Faktureringsförsprång','kr','billing'),
('Faktureringsbalans','unknown_party.amount','Saknad motpart, belopp','kr','billing'),
('Faktureringsbalans','unknown_party.rows','Saknad motpart, rader','st','billing'),
('Faktureringsbalans','pending_invoice.amount','Ej fakturerat externt','kr','billing'),
('Faktureringsbalans','pending_invoice.rows','Ej fakturerade externa rader','st','billing'),
('Verkstad','work_hours','Arbetade timmar','h','workshop'),
('Verkstad','absence_hours','Frånvaro','h','workshop'),
('Verkstad','billable_hours','Debiterbar tid','h','workshop'),
('Verkstad','non_billable_hours','Ej debiterbar tid inklusive egen verkstad','h','workshop'),
('Verkstad','billing_rate','Debiteringsgrad','%','workshop'),
('Verkstad','review_rows','Rader att granska','st','workshop'),
('Verkstad','duplicate_rows','Dubbletter','st','workshop')
 ),scalars as(
 select section||':'||path id,section,label,unit,
 case when p_part='workshop' and not coalesce((p_current->>'available')::boolean,false) then null else (p_current#>>string_to_array(path,'.'))::numeric end c,
 case when p_part='workshop' and not coalesce((p_previous->>'available')::boolean,false) then null else (p_previous#>>string_to_array(path,'.'))::numeric end p,
 case gate when 'time' then time_ok when 'overhead' then finance_ok and p_current#>>'{overhead,status}'='source' and p_previous#>>'{overhead,status}'='source'
 when 'internal' then finance_ok and p_current->>'scope'='published_generation' and p_previous->>'scope'='published_generation'
 when 'billing' then finance_ok and p_current->>'status'='ready' and p_previous->>'status'='ready'
 when 'workshop' then true else finance_ok end complete
 from specs where (p_part='overview' and gate not in('internal','billing','workshop')) or gate=p_part
 ),objects as(
 select collection,coalesce(c->>'key',p->>'key') key,coalesce(c->>'label',p->>'label',c->>'key',p->>'key') label,c,p
 from (values('economic_units'),('business_groups'))a(collection)
 cross join lateral (
 select c.value c,p.value p from jsonb_array_elements(coalesce(p_current->collection,'[]'))c
 full join jsonb_array_elements(coalesce(p_previous->collection,'[]'))p on c.value->>'key'=p.value->>'key'
 )o where p_part='overview'
 ),object_rows as(
 select collection||':'||key||':'||metric id,
 case collection when 'economic_units' then 'Ekonomiska enheter' else 'Verksamhetsgrupper' end section,
 label||' · '||title label,unit,(c#>>string_to_array(metric,'.'))::numeric c,(p#>>string_to_array(metric,'.'))::numeric p,
 case when gate='time' then time_ok else finance_ok end complete
 from objects cross join (values
 ('revenue','Omsättning','kr','finance'),('cost','Kostnader','kr','finance'),('result','Resultat','kr','finance'),
 ('margin_pct','Marginal','%','finance'),('cost_categories.personnel','Personal','kr','finance'),
 ('worked_hours','Timmar','h','time'),('productive_hours','Produktiva timmar','h','time'),('available_hours','Tillgängliga timmar','h','time'),
 ('billing_percent','Debiteringsgrad','%','time'),('utilization','Beläggning','%','time'),
 ('revenue_per_hour','Omsättning per timme','kr/h','time'),('cost_per_hour','Kostnad per timme','kr/h','time'),
 ('distance_mil','Körsträcka','mil','time'),('cost_per_mil','Kostnad per mil','kr/mil','time'),('revenue_per_mil','Omsättning per mil','kr/mil','time'),
 ('fuel_cost_per_mil','Drivmedel per mil','kr/mil','time'),('fuel_liters_per_mil','Förbrukning per mil','l/mil','time')
 )m(metric,title,unit,gate) where collection='economic_units' or metric in('revenue','cost','result')
 ),month_objects as(
 select coalesce(c.value->>'month',p.value->>'month')::integer month_no,c.value c,p.value p
 from jsonb_array_elements(coalesce(p_current->'monthly','[]'))c
 full join jsonb_array_elements(coalesce(p_previous->'monthly','[]'))p on c.value->>'month'=p.value->>'month'
 where p_part='overview'
 ),month_rows as(
 select 'month_no:'||month_no||':'||metric id,'Månader' section,
 (array['Jan','Feb','Mar','Apr','Maj','Jun','Jul','Aug','Sep','Okt','Nov','Dec'])[month_no]||' · '||title label,'kr' unit,
 (c->>metric)::numeric c,(p->>metric)::numeric p,
 not exists(select 1 from (values(p_current),(p_previous))s(v) where
 not coalesce(v#>'{coverage,revenue_months}','[]'::jsonb) @> to_jsonb(array[month_no])
 or not coalesce(v#>'{coverage,cost_months}','[]'::jsonb) @> to_jsonb(array[month_no])) complete
 from month_objects cross join (values('revenue','Omsättning'),('cost','Kostnader'),('result','Resultat'))m(metric,title)
 where month_no=any(p_months)
 ),all_rows as(select * from scalars union all select * from object_rows union all select * from month_rows)
 select jsonb_build_object('rows',coalesce(jsonb_agg(jsonb_build_object('id',id,'section',section,'label',label,'unit',unit)||private.hub_kpi_yoy_value_v1(c,p,unit,coalesce(complete,false)) order by section,case id when 'Ekonomi:metrics.revenue' then 0 when 'Ekonomi:metrics.total_cost' then 1 when 'Ekonomi:metrics.result' then 2 when 'Ekonomi:metrics.margin_pct' then 3 else 10 end,label,id),'[]')) into result from all_rows;
 return result;
end $$;
revoke all on function public.hub_kpi_compare_snapshots_v1(uuid,integer[],text,jsonb,jsonb) from public,anon;
grant execute on function public.hub_kpi_compare_snapshots_v1(uuid,integer[],text,jsonb,jsonb) to authenticated;
