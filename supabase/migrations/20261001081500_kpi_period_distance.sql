create table public.kpi_vehicle_distance_periods (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.hub_tenants(id),
 vehicle_object_id uuid not null references public.hub_objects(id), registration text not null,
 period_from date not null, period_to date not null, distance_km numeric not null check(distance_km>=0),
 ingress_id uuid not null references public.hub_ingress_messages(id), source_row integer not null,
 fingerprint text not null, created_by uuid not null, created_at timestamptz not null default now(),
 check(period_to>=period_from), unique(tenant_id,fingerprint)
);
create index on public.kpi_vehicle_distance_periods(tenant_id,registration,period_from,period_to);
alter table public.kpi_vehicle_distance_periods enable row level security;
create policy distance_read on public.kpi_vehicle_distance_periods for select to authenticated using(public.hub_has_permission(tenant_id,'kpi.read'));
revoke all on public.kpi_vehicle_distance_periods from anon,authenticated;
grant select on public.kpi_vehicle_distance_periods to authenticated;

create function public.hub_kpi_import_distance_v1(p_tenant_id uuid,p_rows jsonb,p_file_name text,p_file_hash text,p_source text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare r jsonb; i integer:=0; ing uuid; obj uuid; n integer; reg text; df date; dt date; km numeric; fp text; reason text; results jsonb:='[]'; accepted integer:=0; reviews integer:=0; duplicates integer:=0;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.manage') then raise exception 'KPI-behörighet saknas' using errcode='42501'; end if;
 if jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows) not between 1 and 5000 or nullif(trim(p_source),'') is null then raise exception 'Ogiltigt importunderlag'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||':kpi_distance',0));
 insert into public.hub_ingress_messages(tenant_id,ingress_type,content_type,payload,payload_hash,parser_key,parser_version,metadata)
 values(p_tenant_id,'file','application/json',p_rows,p_file_hash,'kpi_period_distance','1',jsonb_build_object('file_name',p_file_name,'source',p_source,'actor',auth.uid())) returning id into ing;
 for r in select value from jsonb_array_elements(p_rows) loop
  i:=i+1; reason:=null; obj:=null;
  begin
   reg:=upper(regexp_replace(coalesce(r->>'registration',''),'[[:space:]-]','','g'));
   if coalesce(r->>'from','') !~ '^\d{4}-\d{2}-\d{2}$' or coalesce(r->>'to','') !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'Datum ska vara ÅÅÅÅ-MM-DD'; end if;
   df:=(r->>'from')::date; dt:=(r->>'to')::date;
   if dt<df then raise exception 'Slutdatum före startdatum'; end if;
   if coalesce(r->>'unit','') not in ('km','mil') then raise exception 'Enhet ska vara km eller mil'; end if;
   km:=replace(r->>'distance',',','.')::numeric;
   if km is null or km<0 or km::text in ('NaN','Infinity','-Infinity') then raise exception 'Ogiltig körsträcka'; end if;
   if r->>'unit'='mil' then km:=km*10; end if; km:=trim_scale(km);
   select count(*),(array_agg(o.id))[1] into n,obj from public.hub_objects o where o.tenant_id=p_tenant_id and o.object_type='Vehicle' and upper(regexp_replace(o.data->>'registration_number','[[:space:]-]','','g'))=reg;
   if reg='' or n<>1 then raise exception 'Regnummer saknar entydigt Humla Vehicle Object ID'; end if;
   fp:=md5(obj::text||'|'||df::text||'|'||dt::text||'|'||km::text);
   if exists(select 1 from public.kpi_vehicle_distance_periods where tenant_id=p_tenant_id and fingerprint=fp) then
    duplicates:=duplicates+1; results:=results||jsonb_build_array(jsonb_build_object('row',i,'registration',reg,'status','duplicate')); continue;
   end if;
   if exists(select 1 from public.kpi_vehicle_distance_periods where tenant_id=p_tenant_id and vehicle_object_id=obj and period_from<=dt and period_to>=df) then raise exception 'Perioden överlappar redan importerad körsträcka'; end if;
   insert into public.kpi_vehicle_distance_periods(tenant_id,vehicle_object_id,registration,period_from,period_to,distance_km,ingress_id,source_row,fingerprint,created_by)
   values(p_tenant_id,obj,reg,df,dt,km,ing,i,fp,auth.uid());
   accepted:=accepted+1; results:=results||jsonb_build_array(jsonb_build_object('row',i,'registration',reg,'status','accepted','object_id',obj));
  exception when others then
   reason:=sqlerrm;
   insert into public.hub_review_queue(tenant_id,review_type,payload,reason_code,blocking)
   values(p_tenant_id,'kpi_distance_import',jsonb_build_object('ingress_id',ing,'row',i,'record',r,'reason',reason),'distance_mapping_or_period_invalid',true);
   reviews:=reviews+1; results:=results||jsonb_build_array(jsonb_build_object('row',i,'registration',reg,'status','review','reason',reason));
  end;
 end loop;
 update public.hub_ingress_messages set parse_status=case when reviews>0 then 'partial' else 'parsed' end where id=ing;
 return jsonb_build_object('ingress_id',ing,'accepted',accepted,'review',reviews,'duplicates',duplicates,'rows',results);
end $$;
revoke all on function public.hub_kpi_import_distance_v1(uuid,jsonb,text,text,text) from public,anon;
grant execute on function public.hub_kpi_import_distance_v1(uuid,jsonb,text,text,text) to authenticated;

create function public.hub_kpi_distance_report_v1(p_tenant_id uuid,p_from date,p_to date)
returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read') then raise exception 'KPI-behörighet saknas' using errcode='42501'; end if;
 if p_from is null or p_to is null or p_to<p_from then raise exception 'Ogiltig period'; end if;
 with facts as materialized(select * from private.hub_kpi_financial_facts_v1(p_tenant_id,p_from,p_to)),
 finance as(select vehicle as registration,sum(amount) filter(where kind='revenue') as revenue,sum(amount) filter(where kind='cost') as cost from facts where nullif(vehicle,'') is not null group by vehicle),
 periods as(select * from public.kpi_vehicle_distance_periods where tenant_id=p_tenant_id and period_from>=p_from and period_to<=p_to),
 manual as(select registration,case when min(period_from)=p_from and max(period_to)=p_to and sum(period_to-period_from+1)=p_to-p_from+1 then sum(distance_km) end as km,jsonb_agg(jsonb_build_object('ingress_id',ingress_id,'source_row',source_row,'from',period_from,'to',period_to)) as provenance from periods group by registration),
 assets as(select upper(regexp_replace(data->>'registration_number','[[:space:]-]','','g')) as registration,(array_agg(id))[1] as id from public.hub_objects where tenant_id=p_tenant_id and object_type='Vehicle' group by 1 having count(*)=1),
 meter_checks as(select vehicle_id,bool_or(reading_value<prev) as decreased from (select vehicle_id,reading_value,lag(reading_value) over(partition by vehicle_id,connection_id order by recorded_at,id) as prev from public.hub_vehicle_meter_readings where tenant_id=p_tenant_id and reading_type='odometer_km' and recorded_at between (p_from::timestamp at time zone 'Europe/Stockholm') and ((p_to+1)::timestamp at time zone 'Europe/Stockholm')) x group by vehicle_id),
 meters as(select a.registration,case when not coalesce(bool_or(c.decreased),false) and count(distinct m.connection_id)=1 and count(distinct m.reading_value) filter(where m.recorded_at=(p_from::timestamp at time zone 'Europe/Stockholm'))=1 and count(distinct m.reading_value) filter(where m.recorded_at=((p_to+1)::timestamp at time zone 'Europe/Stockholm'))=1 and min(m.reading_value)>=0 and max(m.reading_value) filter(where m.recorded_at=(p_from::timestamp at time zone 'Europe/Stockholm'))=min(m.reading_value) and max(m.reading_value) filter(where m.recorded_at=((p_to+1)::timestamp at time zone 'Europe/Stockholm'))=max(m.reading_value) then max(m.reading_value)-min(m.reading_value) end as km
 from assets a left join meter_checks c on c.vehicle_id=a.id join public.hub_vehicle_meter_readings m on m.tenant_id=p_tenant_id and m.vehicle_id=a.id and m.reading_type='odometer_km' and m.recorded_at between (p_from::timestamp at time zone 'Europe/Stockholm') and ((p_to+1)::timestamp at time zone 'Europe/Stockholm') group by a.registration),
 regs as(select registration from finance union select registration from manual union select registration from meters),
 combined as(select r.registration,coalesce(f.revenue,0) as revenue,coalesce(f.cost,0) as cost,coalesce(m.km,o.km) as km,case when m.km is not null then 'period_import' when o.km is not null then 'fordonskontrollen_boundary_readings' else 'missing' end as basis,m.provenance from regs r left join finance f using(registration) left join manual m using(registration) left join meters o using(registration))
 select jsonb_build_object('from',p_from,'to',p_to,'unit','mil = 10 km','vehicles',coalesce(jsonb_agg(jsonb_build_object('registration',registration,'distance_km',km,'distance_mil',km/10,'cost',round(cost,2),'revenue',round(revenue,2),'cost_per_mil',round(cost/nullif(km/10,0),2),'revenue_per_mil',round(revenue/nullif(km/10,0),2),'basis',basis,'provenance',provenance) order by registration),'[]'::jsonb)) into result from combined;
 return result;
end $$;
revoke all on function public.hub_kpi_distance_report_v1(uuid,date,date) from public,anon;
grant execute on function public.hub_kpi_distance_report_v1(uuid,date,date) to authenticated;
