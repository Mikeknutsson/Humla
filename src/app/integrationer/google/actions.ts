'use server';

import {revalidatePath} from 'next/cache';
import {optimizationConfig, optimizeGoogleTours} from '@/lib/hub/google-route-optimization';
import {googleHubAccess} from '@/lib/hub/google-hub-access';

export async function saveGoogleMapsKey(key: string | null) {
  const access = await googleHubAccess();
  if (!access?.isOwner) return {error:'Ägarbehörighet krävs för Google-inställningarna.'};

  if (key !== null && (typeof key !== 'string' || !/^AIza[A-Za-z0-9_-]{20,90}$/.test(key.trim()))) {
    return {error:'Ange en giltig webbläsarnyckel för Google Maps.'};
  }

  const {error} = await access.db.rpc('hub_google_maps_save', {
    p_tenant:access.tenantId, p_browser_api_key:key?.trim() ?? null,
  });
  if (error) return {error:'Maps-inställningen kunde inte sparas.'};
  revalidatePath('/integrationer/google');
  return {saved:true};
}

export async function testGoogleRouteOptimization() {
  const access = await googleHubAccess();
  if (!access?.isOwner) return {error:'Ägarbehörighet krävs för att testa anslutningen.'};
  const config = optimizationConfig(access.tenantId);
  if (!config) return {error:'Tjänstkontot för Route Optimization saknas i Humlas serverinställningar.'};

  const depot = {latitude:56.0528,longitude:14.5819};
  const stop = {latitude:56.1714,longitude:14.8624};
  try {
    const response = await optimizeGoogleTours(config,{
      shipments:[{deliveries:[{arrivalLocation:stop}]}],
      vehicles:[{startLocation:depot,endLocation:depot,costPerKilometer:1}],
    });
    return response.routes?.some(route => route.visits?.length)
      ? {message:'Google Route Optimization svarar. Testleveransen fick en körplan.'}
      : {error:'Google Route Optimization svarade utan en körplan för testleveransen.'};
  } catch (error) {
    return {error:error instanceof Error && /^Google (OAuth|Route Optimization)/.test(error.message)
      ? error.message : 'Anslutningen till Google Route Optimization misslyckades.'};
  }
}
