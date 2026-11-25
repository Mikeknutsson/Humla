do $seed$
declare
  tenant record;
  site record;
  target_id uuid;
begin
  for tenant in
    select distinct on (r.tenant_id) r.tenant_id, r.created_by
    from private.hub_material_site_rates r
    join public.hub_identity_keys k on k.tenant_id = r.tenant_id and k.object_id = r.site_id
    where k.object_type = 'MaterialSite' and k.identity_type = 'purchase_list_site' and k.identity_value = 'PUKAVIK'
      and r.kind = 'tip' and r.source like 'Prislista Sortergården 2026.pdf%'
    order by r.tenant_id, r.created_at, r.id
  loop
    for site in select * from (values
      ('HASSLEHOLM_HKC', 'Hässleholms Kretsloppscenter', 'Vankiva 9300, 281 95 Vankiva',
       'För lastbil, följ skyltarna mot vågen. Mottagningskrav per material finns i leverantörens prislista.',
       'https://hassleholmmiljo.se/foretag/hassleholms-kretsloppscenter/kontakta-kretsloppscenter'),
      ('MASSHANTERING_SYD_NOBBELOV', 'Masshantering Syd · Nöbbelöv', '',
       'Tar emot schaktmassor, betong och tegel. Begär pris och bekräfta lastbilsinfart med mottagaren. Besöksadress Adamsbergsvägen 53, 291 91 Kristianstad.',
       'https://www.masshanteringsyd.se/tjanster')
    ) as sites(key, name, address, note, source)
    loop
      select k.object_id into target_id
      from public.hub_identity_keys k
      where k.tenant_id = tenant.tenant_id and k.object_type = 'MaterialSite'
        and k.identity_type = 'receiving_site' and k.identity_value = site.key;

      if target_id is null then
        select o.id into target_id from public.hub_objects o
        where o.tenant_id = tenant.tenant_id and o.object_type = 'MaterialSite' and o.status = 'active'
          and lower(trim(o.data->>'display_name')) = lower(site.name)
          and o.data->>'kind' in ('tip','both')
        order by o.id limit 1;

        if target_id is null then
          insert into public.hub_objects (tenant_id, object_type, data, source_of_truth)
          values (tenant.tenant_id, 'MaterialSite', jsonb_build_object('display_name', site.name, 'kind', 'tip',
            'address', site.address, 'location_note', site.note, 'address_source', site.source), 'humla_price_bank')
          returning id into target_id;
        end if;

        insert into public.hub_identity_keys (tenant_id, object_id, object_type, identity_type, identity_value)
        values (tenant.tenant_id, target_id, 'MaterialSite', 'receiving_site', site.key);
      end if;

      if site.key = 'HASSLEHOLM_HKC' then
        insert into private.hub_material_site_rates
          (tenant_id, site_id, kind, material, unit, price, valid_from, valid_to, source, created_by)
        select tenant.tenant_id, target_id, 'tip', price.material, 'ton', price.value, date '2026-01-01', date '2026-12-31',
          'https://hassleholmmiljo.se/download/18.3a31f9bb19afcb9984d510/1765204802472/Prislista%20HKC%202026.pdf · ' || price.original,
          tenant.created_by
        from (values
          ('Betong oarmerad 0-500 mm', 190, 'Betong/tegel <0,5 m'),
          ('Betong över 500 mm', 240, 'Betong/tegel >0,5 m'),
          ('Schaktmassor MKM', 418, 'MKM jord · Analys krävs enligt prislistan')
        ) as price(material, value, original)
        on conflict do nothing;
      end if;
    end loop;
  end loop;
end
$seed$;
