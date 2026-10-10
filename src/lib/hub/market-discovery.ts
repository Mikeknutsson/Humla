import type {Asset} from './asset-tco';

type Kind='car'|'truck'|'trailer'|'machine'|'other';
export const marketSources=[
 {name:'Klaravik',domain:'klaravik.se',url:'https://www.klaravik.se/auktion/avslutade/',kinds:['car','truck','trailer','machine'],basis:'Auktion – kontrollera att affären genomförts'},
 {name:'Blinto',domain:'blinto.se',url:'https://www.blinto.se/',kinds:['car','truck','trailer','machine'],basis:'Auktion – sök även avslutade objekt'},
 {name:'Retrade',domain:'retrade.eu',url:'https://retrade.eu/sv/',kinds:['car','truck','trailer','machine'],basis:'Auktion – högsta bud är inte ett bekräftat slutpris'},
 {name:'Kvdbil',domain:'kvd.se',url:'https://www.kvd.se/',kinds:['car'],basis:'Auktion och fast pris – kontrollera pristyp'},
 {name:'Mascus',domain:'mascus.se',url:'https://www.mascus.se/',kinds:['truck','trailer','machine'],basis:'Annonspris – inte försäljningspris'},
 {name:'Truck1',domain:'truck1.se',url:'https://www.truck1.se/',kinds:['truck','trailer','machine'],basis:'Annonspris – kontrollera valuta och moms'},
 {name:'Autoline',domain:'autoline24.se',url:'https://autoline24.se/',kinds:['truck','trailer'],basis:'Annonspris – samma objekt kan finnas på flera sajter'},
 {name:'Machineryline',domain:'machineryline.se',url:'https://machineryline.se/',kinds:['machine'],basis:'Annonspris och auktion – kontrollera pristyp'},
 {name:'Bytbil',domain:'bytbil.com',url:'https://www.bytbil.com/',kinds:['car'],basis:'Annonspris – inte försäljningspris'},
] as const;
export type MarketDiscovery={query:string;missing:string[];checks:string[];sources:{name:string;url:string;basis:string;broad_url:string;precise_url:string|null}[]};
const clean=(value:string|null|undefined)=>value?.replace(/["\r\n]/g,' ').replace(/\s+/g,' ').trim().slice(0,150)||'';
function kind(asset:Asset):Kind|null{
 if(asset.ownership)return asset.ownership.asset_class;
 if(asset.vehicle_type==='Personbil')return 'car';
 if(asset.vehicle_type==='Lastbil')return 'truck';
 if(asset.vehicle_type==='Släpvagn')return 'trailer';
 if(['Motorredskap','Traktor','Terrängvagn'].includes(asset.vehicle_type??'')||asset.source_meter_type==='K_OT_HOURS')return 'machine';
 return null;
}
// Server-side discovery plan only. No scraping, network fetch, price calculation,
// identity mutation or automatic admission of an unverified comparable.
export function buildMarketDiscovery(asset:Asset):MarketDiscovery{
 const make=clean(asset.make),model=clean(asset.model),variant=clean(asset.ownership?.variant);
 const query=[make,model].filter(Boolean).join(' ');
 const assetKind=kind(asset),year=asset.ownership?.model_year;
 const missing=[!make&&'Fabrikat',!model&&'Modell',!year&&'Årsmodell',!variant&&'Variant / utförande',!assetKind&&'Fordonstyp'].filter((v):v is string=>!!v);
 const search=(domain:string,terms:string)=>`https://www.google.com/search?${new URLSearchParams({q:`site:${domain} ${terms}`})}`;
 const exact=[query,variant,year].filter(Boolean).join(' ');
 return {query,missing,checks:[
  'Samma modell, variant, påbyggnad, axelkonfiguration och relevant utrustning.',
  'Kontrollera årsmodell, skick och faktisk mätarställning. Km, mil och drifttimmar får inte blandas.',
  'Pris ska vara i SEK på samma momsgrund, utan köparavgift. Utländsk valuta måste först omräknas med dokumenterad kurs.',
  'Avslutad auktion betyder inte automatiskt genomförd försäljning. Aktuellt bud används aldrig som slutpris.',
  'Identifiera samma fordon/maskin på flera sajter med regnummer eller chassinummer så att det inte räknas flera gånger.',
 ],sources:marketSources.filter(s=>!assetKind||assetKind==='other'||(s.kinds as readonly string[]).includes(assetKind)).map(s=>({name:s.name,url:s.url,basis:s.basis,broad_url:search(s.domain,query),precise_url:query&&exact!==query?search(s.domain,exact):null}))};
}
