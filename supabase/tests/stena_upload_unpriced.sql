begin;
do $test$
declare
 tenant uuid;
 actor uuid;
 original bytea := convert_to('QA: Stena mixed price file: '||gen_random_uuid()::text,'UTF8');
 source_hash text := encode(extensions.digest(original,'sha256'),'hex');
 rows jsonb := '[{"row_number":2,"booking":"99999997","date":"2099-11-16","registration":"","price":123},{"row_number":3,"booking":"99999998","date":"2099-11-16","registration":"","price":null}]';
 result jsonb;
begin
 select tenant_id,user_id into strict tenant,actor from public.hub_tenant_members where role='owner' and status='active' and tenant_id in(select tenant_id from private.hub_stena_rules_v1 where enabled) limit 1;
 perform set_config('request.jwt.claim.sub',actor::text,true);
 result := public.hub_stena_upload_v1(tenant,source_hash,'qa.xlsx','history',rows,'','{}',false);
 if (result->>'unresolved_rows')::int is distinct from 1 or (result->>'total')::numeric is distinct from 123::numeric then
  raise exception 'Mixed amount preview incorrect: %',result;
 end if;
 result := public.hub_stena_upload_v1(tenant,source_hash,'qa.xlsx','history',rows,encode(original,'base64'),'{}',true);
 if (result->>'imported')::boolean is distinct from true then raise exception 'Import did not complete'; end if;
 if not exists(select 1 from private.hub_stena_rows_v1 where tenant_id=tenant and file_hash=encode(extensions.digest(source_hash||':history','sha256'),'hex') and row_number=3 and amount is null) then
  raise exception 'Unpriced row not preserved';
 end if;
 result := public.hub_stena_upload_v1(tenant,source_hash,'qa.xlsx','history',rows,encode(original,'base64'),'{}',true);
 if (result->>'duplicate')::boolean is distinct from true then raise exception 'Re-upload duplicated original'; end if;
 result := public.hub_stena_upload_v1(tenant,source_hash,'qa.xlsx','settled',rows,'','{}',false);
 if (result->>'unresolved_rows')::int is distinct from 2 or result->>'total' is not null then raise exception 'Unpriced settlement produced revenue'; end if;
end
$test$;
rollback;
select 'PASS: mixed preview, complete import, unresolved amount stays NULL, duplicate protection and unpriced settlement' as result;
