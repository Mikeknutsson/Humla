import {transportDocumentAccess} from '@/lib/hub/transport-document/access';
import {parseTransportDocument} from '@/lib/hub/transport-document/input';
import {DocumentTextError, renderTransportDocument} from '@/lib/hub/transport-document/pdf';

export const runtime = 'nodejs';

export async function POST(request: Request) {
  const access = await transportDocumentAccess();
  if (access.status !== 'ready') return Response.json({error:'Behörighet saknas. Logga in i Humla igen.'},
    {status:access.status === 'signed-out' ? 401 : 403});
  if (request.headers.get('content-type')?.split(';')[0].trim() !== 'application/json') {
    return Response.json({error:'Dokumentet kunde inte läsas.'},{status:415});
  }
  const maximumSize = 240_000;
  if (Number(request.headers.get('content-length')) > maximumSize) return Response.json({error:'Dokumentet är för stort.'},{status:413});
  const body = await request.text();
  if (body.length > maximumSize) return Response.json({error:'Dokumentet är för stort.'},{status:413});
  let fields;
  try {
    fields = parseTransportDocument(JSON.parse(body));
  } catch (error) {
    return Response.json({error:error instanceof SyntaxError ? 'Dokumentet kunde inte läsas.' :
      error instanceof Error ? error.message : 'Kontrollera formuläret.'},{status:400});
  }
  try {
    const pdf = await renderTransportDocument(fields);
    return new Response(new Uint8Array(pdf),{headers:{
      'Content-Type':'application/pdf',
      'Content-Disposition':'attachment; filename="Transportdokument.pdf"',
      'Cache-Control':'no-store',
    }});
  } catch (error) {
    if (error instanceof DocumentTextError) return Response.json({error:error.message},{status:400});
    console.error('Transportdokument PDF could not be generated',error);
    return Response.json({error:'PDF:en kunde inte skapas. Försök igen.'},{status:500});
  }
}
