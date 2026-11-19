-- The archived originals for these three files use Blad1 with
-- Trp.best.nr, Hämtdatum, Pris SEK and Fakturanr.
do $repair$
declare
 f record;
 updated_count integer;
 definition text;
 marker constant text := ' p_hash:=encode(extensions.digest(p_hash||'':''||p_kind,''sha256''),''hex'');';
begin
 for f in
  select f.*, o.mapping
  from private.hub_stena_files_v1 f
  join private.hub_stena_upload_originals_v1 o using (tenant_id,file_hash)
  where f.source_kind='history' and f.complete
    and (f.file_hash, f.expected_rows) in (
     ('aee52d7f3c31d6690dfa7b849e3a198815f55ead08d3d9aea005744e3f1430fb',298),
     ('6550d9b97efc32a5a82aa4ad044cb57df981cfa086b1c13aaea73b6ebd1e2110',398),
     ('f00f658af38e561155303a60d5a53298476e1e051ab9aa1540474fa958f3b61a',441)
    )
 loop
  perform pg_advisory_xact_lock(hashtextextended('stena-import:'||f.tenant_id::text,0));
  if f.mapping#>>'{columns,settled_amount}' is distinct from '9'
     or f.mapping#>>'{columns,price}' is distinct from '9'
     or coalesce(f.mapping->>'original_sha256','') !~ '^[a-f0-9]{64}$' then
   raise exception 'Unexpected original Stena mapping';
  end if;
  update private.hub_stena_rows_v1 r set amount=r.settled_amount
  where r.tenant_id=f.tenant_id and r.file_hash=f.file_hash and r.settled_amount is not null;
  get diagnostics updated_count = row_count;
  if updated_count<>f.expected_rows then raise exception 'Unexpected number of settled rows'; end if;
  update private.hub_stena_files_v1 s set source_kind='settled'
  where s.tenant_id=f.tenant_id and s.file_hash=f.file_hash;
 end loop;

 -- The repaired files retain their original record identity and references.
 -- Check content hash and final source kind under the import lock on re-upload.
 definition:=pg_get_functiondef('private.hub_stena_upload_v1(uuid,text,text,text,jsonb,text,jsonb,boolean)'::regprocedure);
 if strpos(definition,marker)=0 then raise exception 'Stena upload function has changed'; end if;
 definition:=replace(definition,marker,$dedup$
 perform pg_advisory_xact_lock(hashtextextended('stena-import:'||p_tenant::text,0));
 if exists(
  select 1 from private.hub_stena_files_v1 f
  join private.hub_stena_upload_originals_v1 o using(tenant_id,file_hash)
  where f.tenant_id=p_tenant and f.source_kind=p_kind and f.complete
   and o.mapping->>'original_sha256'=source_hash
 ) then return result||jsonb_build_object('duplicate',true,'imported',false); end if;
 -- A previously misclassified copy uses the history hash but now owns the
 -- settled kind. The standard check below also prevents overwriting that record.
$dedup$||marker);
 execute definition;
end
$repair$;
