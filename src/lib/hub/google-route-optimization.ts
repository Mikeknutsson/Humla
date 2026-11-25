import 'server-only';

import {sign} from 'node:crypto';

const tokenEndpoint = 'https://oauth2.googleapis.com/token';

type AccessConfig = {
  projectId: string;
  clientEmail: string;
  privateKey: string;
};

export function optimizationConfig(tenantId: string): AccessConfig | null {
  if (process.env.GOOGLE_ROUTE_OPTIMIZATION_TENANT_ID !== tenantId) return null;
  try {
    const account = JSON.parse(process.env.GOOGLE_ROUTE_OPTIMIZATION_SERVICE_ACCOUNT_JSON ?? '{}');
    if (!/^[a-z][a-z0-9-]{4,28}[a-z0-9]$/.test(account.project_id ?? '') ||
        typeof account.client_email !== 'string' || typeof account.private_key !== 'string') return null;
    return {projectId:account.project_id,clientEmail:account.client_email,privateKey:account.private_key};
  } catch {
    return null;
  }
}

async function accessToken(config: AccessConfig) {
  const issuedAt = Math.floor(Date.now()/1000);
  const header = Buffer.from(JSON.stringify({alg:'RS256',typ:'JWT'})).toString('base64url');
  const claims = Buffer.from(JSON.stringify({
    iss:config.clientEmail,scope:'https://www.googleapis.com/auth/cloud-platform',
    aud:tokenEndpoint,iat:issuedAt,exp:issuedAt+300,
  })).toString('base64url');
  const payload = `${header}.${claims}`;
  const assertion = `${payload}.${sign('RSA-SHA256',Buffer.from(payload),config.privateKey).toString('base64url')}`;
  const response = await fetch(tokenEndpoint,{
    method:'POST',
    body:new URLSearchParams({grant_type:'urn:ietf:params:oauth:grant-type:jwt-bearer',assertion}),
    cache:'no-store',signal:AbortSignal.timeout(10000),
  });
  if (!response.ok) throw new Error('Google OAuth kunde inte utfärda en åtkomsttoken.');
  const {access_token: token} = await response.json();
  if (typeof token !== 'string' || !token) throw new Error('Google OAuth returnerade ingen åtkomsttoken.');
  return token;
}

type TourLocation = {latitude: number; longitude: number};

type TourModel = {
  shipments: {
    pickups?: {arrivalLocation: TourLocation}[];
    deliveries?: {arrivalLocation: TourLocation}[];
  }[];
  vehicles: {
    startLocation: TourLocation;
    endLocation: TourLocation;
    costPerKilometer: number;
  }[];
};

export async function optimizeGoogleTours(config: AccessConfig, model: TourModel) {
  const token = await accessToken(config);
  const response = await fetch(`https://routeoptimization.googleapis.com/v1/projects/${config.projectId}:optimizeTours`,{
    method:'POST',
    headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json'},
    body:JSON.stringify({model,timeout:'5s'}),
    cache:'no-store',signal:AbortSignal.timeout(15000),
  });
  if (!response.ok) {
    const body = await response.json().catch(() => null) as {
      error?: {status?: unknown; details?: {reason?: unknown}[]};
    } | null;
    const details = body?.error?.details;
    const isErrorCode = (value: unknown): value is string =>
      typeof value === 'string' && /^[A-Z][A-Z0-9_]{2,79}$/.test(value);
    const reason = Array.isArray(details) ? details.find(detail => isErrorCode(detail?.reason))?.reason : null;
    const code = isErrorCode(reason) ? reason : body?.error?.status;
    const hint = isErrorCode(code) ? ` (${code})` : '';
    throw new Error(`Google Route Optimization returnerade HTTP ${response.status}${hint}.`);
  }
  return await response.json() as {routes?: {visits?: {isPickup?: boolean}[]}[]};
}
