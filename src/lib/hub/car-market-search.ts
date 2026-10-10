import type {Asset} from './asset-tco';
import {marketSources} from './market-discovery';
import type {SearchCandidate,SearchTrialResult} from './market-search-trial';
export type CarCandidate=SearchCandidate&{page_kind:'listing'|'collection'|'unknown';price_kind:'asking'|'auction'|'unknown'};
export type CarSearchResult=Omit<SearchTrialResult,'candidates'>&{candidates:CarCandidate[];missing:string[];meter_km:number|null;meter_date:string|null;generation_id:string|null};
export const carSearchSources=marketSources.filter(s=>(s.kinds as readonly string[]).includes('car'));
export function carSearchPlan(asset:Asset){
 const clean=(s:string|null|undefined)=>(s??'').replace(/["\r\n]/g,' ').replace(/\s+/g,' ').trim().slice(0,150);
 const model=[clean(asset.make),clean(asset.model)].filter(Boolean).join(' ');
 const year=asset.ownership?.model_year,variant=clean(asset.ownership?.variant);
 return {query:`"${model}" ${[year,variant].filter(Boolean).join(' ')} begagnad pris årsmodell miltal -inurl:bil/ -inurl:begagnade-bilar -inurl:avslutade`.replace(/\s+/g,' ').trim(),
  missing:[!year&&'Årsmodell',!variant&&'Motorvariant / drivlina / utrustning',asset.current_meter==null&&'Mätarställning'].filter((x):x is string=>!!x),
  meter_km:asset.current_meter,meter_date:asset.meter_date};
}
export function classifyCarCandidates(candidates:SearchCandidate[]):CarCandidate[]{
 const seen=new Set<string>();
 return candidates.filter(c=>carSearchSources.some(s=>s.name===c.source)).flatMap(c=>{
  const url=new URL(c.url),path=url.pathname;
  let page_kind:CarCandidate['page_kind']='unknown',price_kind:CarCandidate['price_kind']='unknown';
  let identity=url.origin+path;
  if(c.source==='Kvdbil'){
   const id=path.match(/^\/(fast-pris|auktioner)\/(?:.*-)?(\d+)\/?$/);
   if(id){page_kind='listing';price_kind=id[1]==='fast-pris'?'asking':'auction';identity=`kvd:${id[2]}`;}
   else if(path.startsWith('/begagnade-bilar'))page_kind='collection';
  }else if(c.source==='Bytbil'){
   if(/^\/[^/]+\/personbil-[^/]+-\d+-\d+\/?$/.test(path)){page_kind='listing';price_kind='asking';}
   else if(/^\/bil(?:\/|$)/.test(path))page_kind='collection';
  }else if(c.source==='Klaravik'){
   if(/^\/auktion\/produkt\/\d+/.test(path)){page_kind='listing';price_kind='auction';}else page_kind='collection';
  }
  // A URL pattern identifies a page, not a verified sale or comparable vehicle.
  if(seen.has(identity))return [];seen.add(identity);
  return [{...c,page_kind,price_kind}];
 });
}
