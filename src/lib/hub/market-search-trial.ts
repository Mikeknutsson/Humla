import {marketSources} from './market-discovery';
export const trialAssetId='741e093a-93ba-4266-abf8-2288789d1c84';
export type SearchCandidate={title:string;url:string;snippet:string;date:string|null;source:string};
export type SearchTrialResult={query:string;searched_at:string;candidates:SearchCandidate[];cost_usd:number|null;error?:string};
// Search engine output is untrusted. No page fetching, price inference or valuation writes.
export function safeSearchCandidates(value:unknown):SearchCandidate[]{
 if(!value||typeof value!=='object'||!('results'in value)||!Array.isArray(value.results))return [];
 const seen=new Set<string>(),out:SearchCandidate[]=[];
 for(const item of value.results.slice(0,10)){
  if(!item||typeof item!=='object'||typeof item.url!=='string'||item.url.length>2000)continue;
  try{
   const url=new URL(item.url);if(url.protocol!=='https:'||url.username||url.password||url.port)continue;
   const source=marketSources.find(s=>url.hostname===s.domain||url.hostname.endsWith(`.${s.domain}`));if(!source)continue;
   url.hash='';const identity=url.origin+url.pathname;if(seen.has(identity))continue;seen.add(identity);
   out.push({title:typeof item.title==='string'?item.title.slice(0,300):source.name,url:url.href,snippet:typeof item.snippet==='string'?item.snippet.slice(0,1600):'',date:typeof item.date==='string'?item.date.slice(0,80):null,source:source.name});
  }catch{/* Ignore malformed links. */}
 }
 return out;
}
export function trialQuery(make:string|null,model:string|null){
 const clean=(s:string|null)=>(s??'').replace(/[\r\n"]/g,' ').trim().slice(0,100);
 // Manufacturer code normalization only; does not confirm comparable identity.
 const code=clean(model).match(/^(R\d{3})B(\dX\d)/i);
 return [clean(make),code?`${code[1]} ${code[2]}`:clean(model),'lastbil pris'].filter(Boolean).join(' ');
}
