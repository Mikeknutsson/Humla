import type {PaymentForecast} from './payment-forecast';

export function weeklyTransfers(forecast:Pick<PaymentForecast,'weeks'>){
 return forecast.weeks.map(w=>({week:`${w.year}-V${String(w.number).padStart(2,'0')}`,from:w.from,to:w.to,
  incoming:w.total.incoming.total,outgoing:w.total.outgoing.total,net:w.total.net,
  complete:w.total.incoming.total!==null&&w.total.outgoing.total!==null&&w.total.net!==null}));
}

/** Use approved weekly totals unchanged. Incomplete weeks cannot be transferred. */
export function weeklyTransferText(rows:ReturnType<typeof weeklyTransfers>,delimiter:';'|'\t'){
 if(!rows.length||rows.some(r=>!r.complete))throw Error('Komplett veckoprognos saknas. Hämta och komplettera underlaget innan överföring.');
 const values=[['Vecka','Från','Till','Inbetalningar (SEK exkl. moms)','Utbetalningar (SEK exkl. moms)','Netto före löner och moms (SEK)'],
  ...rows.map(r=>[r.week,r.from,r.to,...[r.incoming,r.outgoing,r.net].map(n=>n!.toFixed(2).replace('.',','))])];
 return values.map(row=>row.map(v=>delimiter===';'?'"'+v.replaceAll('"','""')+'"':v).join(delimiter)).join('\r\n');
}
