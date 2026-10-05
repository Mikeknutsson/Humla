create or replace function public.hub_next_store_access_token_v1(p_tenant_id uuid,p_connection_id uuid,p_access_token text)
returns jsonb language plpgsql security definer set search_path='' as $fn$
declare v_secret uuid; v_connection public.hub_connections;
begin
 if coalesce(p_access_token,'')='' or length(p_access_token)>8192 then raise exception 'Invalid NEXT token'; end if;
 select * into v_connection from public.hub_connections where id=p_connection_id and tenant_id=p_tenant_id for update;
 if not found or v_connection.connector_type<>'next_project_api' or coalesce(v_connection.configuration->>'environment','')<>'test' then raise exception 'Verified NEXT test connection required'; end if;
 select vault_secret_id into v_secret from public.hub_secret_references where tenant_id=p_tenant_id and connection_id=p_connection_id and credential_name='access_token';
 if v_secret is null then
  select vault.create_secret(p_access_token,'humla_next_access_token_'||p_connection_id::text,'NEXT test access token; never expose to clients') into v_secret;
 else
  perform vault.update_secret(v_secret,p_access_token);
 end if;
 insert into public.hub_secret_references(tenant_id,connection_id,credential_name,vault_secret_id,status,last_rotated_at,updated_at)
 values(p_tenant_id,p_connection_id,'access_token',v_secret,'configured',now(),now())
 on conflict(connection_id,credential_name) do update set vault_secret_id=excluded.vault_secret_id,status='configured',last_rotated_at=now(),updated_at=now();
 return jsonb_build_object('ok',true,'stored',true);
end $fn$;
revoke all on function public.hub_next_store_access_token_v1(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.hub_next_store_access_token_v1(uuid,uuid,text) to service_role;
