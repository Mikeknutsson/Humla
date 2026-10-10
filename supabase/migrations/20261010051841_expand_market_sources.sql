-- Additive source support; existing comparables, valuation history, RLS and
-- canonical asset IDs remain unchanged. This does not enable web scraping.
set lock_timeout='5s';
alter table private.hub_asset_comparables drop constraint hub_asset_comparables_source_check;
alter table private.hub_asset_comparables add constraint hub_asset_comparables_source_check
 check(source in ('Blocket','Klaravik','Blinto','Bilpriser','Other','Retrade','Kvdbil','Mascus','Truck1','Autoline','Machineryline','Bytbil'));
