import {generateText,gateway,jsonSchema} from 'ai';
import {aiContext} from '@/lib/ai/context';
import {marketSources} from '@/lib/hub/market-discovery';
import {safeSearchCandidates,trialAssetId,trialQuery,type SearchTrialResult} from '@/lib/hub/market-search-trial';
import type {AssetTcoReport} from '@/lib/hub/asset-tco';
export const maxDuration=90;
export const dynamic='force-dynamic';
export async function POST(req:Request){
 if(req.headers.get('origin')!==new URL(req.url).origin)return Response.json({error:'Ogiltigt ursprung.'},{status:403});
 const c=await aiContext();if('error'in c)return Response.json({error:c.error},{status:c.status});
 let assetId:string;
 try{const b=await req.json();if(b.asset_id!==trialAssetId)throw Error();assetId=b.asset_id;}catch{return Response.json({error:'Testet är avgränsat till det valda testfordonet.'},{status:400});}
 const args={p_tenant_id:c.tenantId,p_asset:assetId};
 const {data:report,error:reportError}=await c.db.rpc('hub_asset_tco_v1',{p_tenant_id:c.tenantId,p_as_of:new Date().toISOString().slice(0,10),p_asset:assetId});
 const asset=(report as AssetTcoReport|null)?.assets.find(a=>a.id===assetId);
 if(reportError||!asset||!report.can_manage)return Response.json({error:'Fordonsadministratör krävs.'},{status:403});
 const query=trialQuery(asset.make,asset.model);
 const {data:reservation,error}=await c.db.rpc('hub_market_search_trial_v1',{...args,p_action:'reserve'});
 if(error)return Response.json({error:'Testet kunde inte reserveras.'},{status:503});
 if(!reservation.reserved)return reservation.result?Response.json(reservation.result):Response.json({error:'Testet har redan startats. Ingen ny betald sökning görs.'},{status:409});
 let result:SearchTrialResult={query,searched_at:new Date().toISOString(),candidates:[],cost_usd:null};
 try{
  const search=gateway.tools.perplexitySearch({maxResults:10,maxTokensPerPage:512,maxTokens:2048,country:'SE',searchDomainFilter:marketSources.map(s=>s.domain),searchLanguageFilter:['sv']});
  const generation=await generateText({model:gateway('openai/gpt-5-mini'),maxOutputTokens:800,maxRetries:0,
   providerOptions:{openai:{reasoningEffort:'minimal',parallelToolCalls:false}},
   // One step, one fixed query, no user-controlled tools or repeat search loop.
   prompt:`Use perplexity_search exactly once with query ${JSON.stringify(query)}. Do not change the query.`,
   tools:{perplexity_search:{...search,inputSchema:jsonSchema<{query:string}>({type:'object',properties:{query:{type:'string',enum:[query]}},required:['query'],additionalProperties:false})}},
   toolChoice:{type:'tool',toolName:'perplexity_search'},abortSignal:AbortSignal.timeout(60000)});
  const output=generation.toolResults.find(t=>t.toolName==='perplexity_search')?.output;
  if(output&&typeof output==='object'&&'error'in output)throw Error('Search provider error');
  result.candidates=safeSearchCandidates(output);
  const meta=generation.providerMetadata?.gateway;
  if(meta&&typeof meta.generationId==='string'){
   try{const info=await gateway.getGenerationInfo({id:meta.generationId});result.cost_usd=info.totalCost;}catch{/* Cost is unknown, never presented as zero. */}
  }
 }catch(e){
  console.error('[market-search-trial]',{name:e instanceof Error?e.name:'unknown'});
  result={...result,error:'Webbsökningen kunde inte slutföras. Inga värden har ändrats. Testspärren förhindrar nya betalda försök.'};
 }
 const {error:saveError}=await c.db.rpc('hub_market_search_trial_v1',{...args,p_action:'finish',p_claim:reservation.claim,p_result:result});
 if(saveError)return Response.json({...result,error:'Testet kördes men resultatet kunde inte sparas. Ingen ny betald sökning görs.'});
 return Response.json(result,{headers:{'Cache-Control':'no-store'}});
}
