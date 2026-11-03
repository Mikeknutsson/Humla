export class ImportConnectionError extends Error {
 constructor(message:string,public reconnect=false){super(message);this.name='ImportConnectionError';}
}
/** Retry only read-only analysis. A save with a lost response must never be replayed automatically. */
export async function requestImport(url:string,body:FormData,{readOnly=false,timeout=90000}:{readOnly?:boolean;timeout?:number}={}){
 const requestId=crypto.randomUUID();
 let response:Response|undefined;
 for(let attempt=0;attempt<(readOnly?2:1);attempt++){
  try{
   response=await fetch(url,{method:'POST',body,credentials:'same-origin',redirect:'manual',headers:{'X-Humla-Import-Request':requestId},signal:AbortSignal.timeout(timeout)});
   break;
  }catch(error){
   if(error instanceof Error&&['TimeoutError','AbortError'].includes(error.name))throw new ImportConnectionError(`Svaret dröjde. Filen ligger kvar. ${readOnly?'Försök läsa filen igen.':'Kontrollera senaste importer innan du försöker spara igen.'} Referens: ${requestId}`);
   if(readOnly&&attempt===0)continue;
   throw new ImportConnectionError(`Anslutningen till Humla bröts innan något svar kom fram. Filen ligger kvar. Öppna Humla i en ny flik för att återansluta och försök sedan igen här.${readOnly?'':' Om sparandet hade börjat: kontrollera senaste importer först.'} Referens: ${requestId}`,true);
  }
 }
 if(!response)throw new ImportConnectionError('Inget svar från Humla. Filen ligger kvar.',true);
 if(response.type==='opaqueredirect'||response.status===401){
  throw new ImportConnectionError('Inloggningen behöver förnyas. Filen ligger kvar här. Öppna Humla i en ny flik, logga in och försök sedan igen här.',true);
 }
 if(!response.headers.get('content-type')?.includes('application/json'))throw new ImportConnectionError(`Humla kunde inte lämna ett importsvar (HTTP ${response.status}). Filen ligger kvar. Öppna Humla i en ny flik och försök sedan igen. Referens: ${requestId}`,true);
 let result;
 try{result=await response.json();}catch{throw new ImportConnectionError(`Importsvaret avbröts eller kunde inte läsas. Filen ligger kvar. Försök läsa filen igen. Om sparandet hade börjat, kontrollera senaste importer först. Referens: ${requestId}`,true);}
 if(!response.ok)throw new Error(result.error??`Importanropet misslyckades (HTTP ${response.status}). Referens: ${requestId}`);
 if(!readOnly&&typeof window!=='undefined')window.dispatchEvent(new Event('humla:kpi-imported'));
 return result;
}
