import {generateText,gateway,jsonSchema} from 'ai';
import {aiContext} from '@/lib/ai/context';
import {safeSearchCandidates} from '@/lib/hub/market-search-trial';
import {carSearchPlan,carSearchSources,classifyCarCandidates,type CarSearchResult} from '@/lib/hub/car-market-search';
import type {AssetTcoReport} from '@/lib/hub/asset-tco';
export const maxDuration=90;
export const dynamic='force-dynamic';
export async function POST(req:Request){
 if(req.headers.get('origin')!==new URL(req.url).origin)return Response.json({error:'Ogiltigt ursprung.'},{status:403});
 if(Number(req.headers.get('content-length')??0)>2000)return Response.json({error:'För stor förfrågan.'},{status:413});
 const c=await aiContext();if('error'in c)return Response.json({error:c.error},{status:c.status});
 let assetId:string;
 try{const b=await req.json();if(typeof b.asset_id!=='string'||! /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(b.asset_id))throw Error();assetId=b.asset_id;}catch{return Response.json({error:'Välj en personbil.'},{status:400});}
 const args={p_tenant_id:c.tenantId,p_asset:assetId};
 const {data:report,error:reportError}=await c.db.rpc('hub_asset_tco_v1',{p_tenant_id:c.tenantId,p_as_of:new Date().toISOString().slice(0,10),p_asset:assetId});
 const asset=(report as AssetTcoReport|null)?.assets.find(a=>a.id===assetId);
 if(reportError||!asset||!report.can_manage||asset.vehicle_type!=='Personbil')return Response.json({error:'Personbil och fordonsadministratör krävs.'},{status:403});
 if(!asset.make||!asset.model)return Response.json({error:'Fabrikat och modell saknas i Hubben.'},{status:400});
 const plan=carSearchPlan(asset);
 const {data:reservation,error}=await c.db.rpc('hub_car_search_trial_v1',{...args,p_action:'reserve'});
 if(error)return Response.json({error:'Personbilstestet kunde inte reserveras.'},{status:503});
 if(!reservation.reserved)return reservation.result?Response.json(reservation.result,{headers:{'Cache-Control':'no-store'}}):Response.json({error:reservation.limit_reached?'Pilotens tre sökningar är använda. Ingen ny betald sökning görs.':'Testet har redan startats. Ingen ny betald sökning görs.'},{status:409});
 let result:CarSearchResult={...plan,searched_at:new Date().toISOString(),candidates:[],cost_usd:null,generation_id:null};
 try{
  const search=gateway.tools.perplexitySearch({maxResults:10,maxTokensPerPage:768,maxTokens:4096,country:'SE',searchDomainFilter:carSearchSources.map(s=>s.domain),searchLanguageFilter:['sv']});
  const generation=await generateText({model:gateway('openai/gpt-5-mini'),maxOutputTokens:800,maxRetries:0,
   providerOptions:{openai:{reasoningEffort:'minimal',parallelToolCalls:false}},
   prompt:`Use perplexity_search exactly once with query ${JSON.stringify(plan.query)}. Do not change the query.`,
   tools:{perplexity_search:{...search,inputSchema:jsonSchema<{query:string}>({type:'object',properties:{query:{type:'string',enum:[plan.query]}},required:['query'],additionalProperties:false})}},
   toolChoice:{type:'tool',toolName:'perplexity_search'},abortSignal:AbortSignal.timeout(60000)});
  const output=generation.toolResults.find(t=>t.toolName==='perplexity_search')?.output;
  if(!output||typeof output!=='object'||'error'in output||!('results'in output))throw Error('Search provider error');
  result.candidates=classifyCarCandidates(safeSearchCandidates(output));
  const meta=generation.providerMetadata?.gateway;
  if(meta&&typeof meta.generationId==='string'){
   result.generation_id=meta.generationId;
   try{const info=await gateway.getGenerationInfo({id:meta.generationId});result.cost_usd=info.totalCost;}catch(e){console.warn('[car-market-search] cost lookup failed',{name:e instanceof Error?e.name:'unknown'});}
  }
 }catch(e){console.error('[car-market-search]',{name:e instanceof Error?e.name:'unknown'});result={...result,error:'Webbsökningen kunde inte slutföras. Inga värden har ändrats. Inga automatiska återförsök görs.'};}
 const {error:saveError}=await c.db.rpc('hub_car_search_trial_v1',{...args,p_action:'finish',p_claim:reservation.claim,p_result:result});
 if(saveError)return Response.json({...result,error:'Testet kördes men resultatet kunde inte sparas. Ingen ny betald sökning görs.'});
 return Response.json(result,{headers:{'Cache-Control':'no-store'}});
}
