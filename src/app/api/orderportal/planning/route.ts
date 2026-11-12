import {orderAccess} from '@/lib/orderportal/server';
export const dynamic='force-dynamic';
const headers={'Cache-Control':'private, no-store'};
export async function POST(request:Request){
 if(request.headers.get('origin')!==new URL(request.url).origin)return Response.json({error:'Ogiltigt ursprung.'},{status:403,headers});
 const ctx=await orderAccess();if(!ctx)return Response.json({error:'Behörighet saknas.'},{status:403,headers});
 try{const raw=await request.text();if(raw.length>5000)throw Error('För stor begäran.');const p=JSON.parse(raw);
 if(!p.id||!Number.isInteger(p.version)||p.version<1||!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(p.start)||!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(p.end)||!Number.isFinite(Date.parse(p.start))||!Number.isFinite(Date.parse(p.end))||p.end<=p.start)throw Error('Ange giltig start- och sluttid.');
 const r=await ctx.db.rpc('hub_orderportal_plan',{p_tenant_id:ctx.tenantId,p_id:p.id,p_version:p.version,p_start:p.start,p_end:p.end,p_vehicle:p.vehicleId||null,p_driver:p.driverId||null});
 if(r.error){const m=r.error.message;return Response.json({error:m.includes('maintenance_conflict')?'Fordonet har ett bokat underhållsbesök i Fordonskontrollen. Välj en annan tid eller ett annat fordon.':m.includes('resource_conflict')?'Fordonet eller föraren är redan bokad under perioden. Välj en annan tid eller resurs.':m.includes('version_conflict')?'Ordern har ändrats av någon annan. Stäng dialogen, uppdatera och försök igen.':m.includes('order_not_plannable')?'Endast aktiva Humla-testorder kan planeras.':'Planeringen kunde inte sparas. Kontrollera tider och resurser.'},{status:409,headers});}
 return Response.json({id:r.data},{headers});
 }catch(e){return Response.json({error:e instanceof Error?e.message:'Ogiltig begäran.'},{status:400,headers});}
}
