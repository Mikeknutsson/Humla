import {readOfferPdf} from '@/lib/hub/ton-price-offer-archive';
import {tonPriceAccess} from '../../../access';

export async function GET(_request: Request, {params}: {params: Promise<{id: string; document: string}>}) {
  const {id,document} = await params;
  if (!/^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/i.test(id) || (document !== 'offert' && document !== 'leveransplan')) {
    return new Response('Dokumentet finns inte.',{status:404});
  }
  const access = await tonPriceAccess();
  if (!access) return new Response('Behörighet saknas.',{status:403});
  try {
    const pdf = await readOfferPdf(access,id,document);
    if (!pdf) return new Response('Dokumentet finns inte.',{status:404});
    return new Response(Uint8Array.from(pdf),{headers:{
      'Content-Type':'application/pdf',
      'Content-Disposition':`attachment; filename="${document}-${id.slice(0,8)}.pdf"`,
      'Cache-Control':'private, no-store',
    }});
  } catch {
    return new Response('Dokumentet kunde inte hämtas. Försök igen.',{status:500});
  }
}
