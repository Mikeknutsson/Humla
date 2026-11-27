'use server';

import {generateText, gateway, jsonSchema} from 'ai';
import {companyWebDetails, companyWebDomains, searchableCompany} from '@/lib/hub/transport-document/company-web-evidence';
import {transportDocumentAccess} from '@/lib/hub/transport-document/access';

export async function loadConsignorDetails(name: string) {
  const access = await transportDocumentAccess();
  if (access.status !== 'ready') return {status:'unavailable'} as const;
  if (typeof name !== 'string' || !name.trim() || name.length > 110) return {status:'missing'} as const;

  const key = name.trim();
  const {data,error} = await access.db.rpc('hub_transport_document_customer',{
    p_tenant:access.tenantId,p_name:key,
  });
  if (error) return {status:'unavailable'} as const;
  if (data?.length !== 1 || data[0].name?.toLocaleLowerCase('sv') !== key.toLocaleLowerCase('sv')) {
    return {status:'missing'} as const;
  }
  const {organisation,address,source} = data[0];
  if (!organisation && !address) return {status:'missing'} as const;
  return {
    status:'found',
    organisation:organisation?.trim().slice(0,30) ?? '',
    address:address?.trim().slice(0,220) ?? '',
    source:typeof source === 'string' && source.startsWith('https://') ? source : '',
  } as const;
}

export async function searchConsignorDetails(name: string) {
  const access = await transportDocumentAccess();
  if (access.status !== 'ready') return {status:'unavailable'} as const;
  if (typeof name !== 'string' || !searchableCompany(name)) return {status:'unsupported'} as const;
  const query = `"${name}" organisationsnummer postadress`;
  try {
    const search = gateway.tools.perplexitySearch({country:'SE',maxResults:6,maxTokensPerPage:768,maxTokens:3500,
      searchDomainFilter:companyWebDomains,searchLanguageFilter:['sv','en']});
    const result = await generateText({
      model:gateway('openai/gpt-5-mini'),maxOutputTokens:450,maxRetries:0,
      prompt:`Call perplexity_search once using the exact query ${JSON.stringify(query)}.`,
      tools:{perplexity_search:{...search,inputSchema:jsonSchema<{query:string}>({
        type:'object',properties:{query:{type:'string',enum:[query]}},required:['query'],additionalProperties:false,
      })}},
      providerOptions:{openai:{reasoningEffort:'minimal',parallelToolCalls:false}},
      toolChoice:{type:'tool',toolName:'perplexity_search'},abortSignal:AbortSignal.timeout(18000),
    });
    const output = result.toolResults.find(item=>item.toolName==='perplexity_search')?.output;
    if (!output || typeof output !== 'object' || !('results' in output) || !Array.isArray(output.results)) {
      return {status:'unavailable'} as const;
    }
    const details = companyWebDetails(name,output.results);
    return details ? {status:'found',details} as const : {status:'missing'} as const;
  } catch (error) {
    console.warn('Transportdokument web lookup failed',error instanceof Error ? error.name : 'unknown');
    return {status:'unavailable'} as const;
  }
}
