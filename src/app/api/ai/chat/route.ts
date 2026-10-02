import {aiContext} from '@/lib/ai/context';
import {humlaAgent,type Evidence} from '@/lib/ai/humla-agent';
export const dynamic='force-dynamic';
export const maxDuration=120;
export async function POST(req:Request){
 const origin=req.headers.get('origin');if(origin&&origin!==new URL(req.url).origin)return Response.json({error:'Ogiltigt ursprung.'},{status:403});
 const c=await aiContext();if('error'in c)return Response.json({error:c.error},{status:c.status});
 if(Number(req.headers.get('content-length')??0)>40000)return Response.json({error:'Samtalet är för långt.'},{status:413});
 let messages:Array<{role:'user'|'assistant';content:string}>;
 try{const b=await req.json();if(!Array.isArray(b.messages)||b.messages.length<1||b.messages.length>16)throw Error();messages=b.messages.map((m:unknown)=>{if(!m||typeof m!=='object'||!('role'in m)||!('content'in m)||(m.role!=='user'&&m.role!=='assistant')||typeof m.content!=='string'||m.content.length>4000||!m.content.trim())throw Error();return {role:m.role,content:m.content};});if(messages.at(-1)?.role!=='user'||messages.reduce((n,m)=>n+m.content.length,0)>24000)throw Error();}catch{return Response.json({error:'Skriv en fråga på högst 4 000 tecken.'},{status:400});}
 const {data:reserved,error}=await c.db.rpc('hub_ai_reserve_request_v1',{p_tenant_id:c.tenantId});if(error)return Response.json({error:'Frågetjänsten kunde inte startas.'},{status:503});if(!reserved)return Response.json({error:'Många frågor har ställts. Vänta en minut och försök igen. Max 100 frågor per dygn.'},{status:429});
 try{const evidence=new Map<string,Evidence>();const result=await humlaAgent(c.db,c.tenantId,c.userId,evidence).generate({messages,abortSignal:AbortSignal.any([req.signal,AbortSignal.timeout(110000)])});const text=result.text.trim();if(!text)throw Error('No answer');return Response.json({answer:text,sources:[...evidence.values()].filter(e=>text.includes(`[${e.key}]`)),searchedAt:new Date().toISOString()},{headers:{'Cache-Control':'no-store'}});}catch(e){console.error('[humla-ai] generation failed',e instanceof Error?e.name:'unknown');return Response.json({error:'AI-svaret kunde inte hämtas. Försök igen. Inga belopp har uppskattats.'},{status:503});}
}
