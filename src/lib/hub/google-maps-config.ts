import 'server-only';
import type {createClient} from '@/lib/supabase/server';

type Database = Awaited<ReturnType<typeof createClient>>;
type SavedConfig = {browser_api_key: string | null; updated_at: string};

export async function readGoogleMapsConfig(db: Database, tenantId: string) {
  const {data, error} = await db.rpc('hub_google_maps_config', {p_tenant:tenantId});
  const saved = data as SavedConfig | null;
  if (error) console.error('Could not read Google Maps configuration', error.code);
  const fallback = process.env.NEXT_PUBLIC_GOOGLE_MAPS_API_KEY?.trim() || null;
  return {
    browserKey: saved ? saved.browser_api_key : fallback,
    updatedAt: saved?.updated_at ?? null,
    source: saved ? 'hub' as const : fallback ? 'environment' as const : null,
    error: Boolean(error),
  };
}
