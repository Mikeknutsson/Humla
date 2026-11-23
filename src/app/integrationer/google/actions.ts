'use server';

import {revalidatePath} from 'next/cache';
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
