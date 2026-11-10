import * as XLSX from 'xlsx';
const monthNames=['jan','feb','mar','apr','maj','jun','jul','aug','sep','okt','nov','dec'];
export function parseAccountingReference(bytes:Uint8Array){
 const book=XLSX.read(bytes,{type:'array'});
 const matches=book.SheetNames.map(name=>({name,rows:XLSX.utils.sheet_to_json<unknown[]>(book.Sheets[name],{header:1,raw:true,defval:null})})).filter(s=>s.rows[0]?.[0]==='Kontorubrik'&&s.rows[0]?.[1]==='Kontogrupp'&&s.rows[0]?.[2]==='Innev års utfall TD');
 if(matches.length!==1)throw Error('Välj bokföringsexporten med Kontorubrik, Kontogrupp och Innev års utfall TD.');
 const {name,rows}=matches[0],footer=rows.flat().filter(v=>typeof v==='string'&&v.startsWith('Tillämpade filter:'));
 if(footer.length!==1)throw Error('Exportens period- och avdelningsfilter saknas eller är tvetydiga.');
 const filters=String(footer[0]),fiscal=/Räkenskapsår2_invSort är (\d{2})\/(\d{2})/.exec(filters),monthLine=/Månad \(sort enl räkenskapsår\) är ([^\n]+)/.exec(filters),centerLine=/dima är ([^\n]+)/.exec(filters);
 if(!fiscal||Number(fiscal[2])!==(Number(fiscal[1])+1)%100||!monthLine||!centerLine)throw Error('Verksamhetsår, månad eller kostnadsställe kunde inte verifieras i exporten.');
 const tokens=monthLine[1].toLowerCase().match(/[a-zåäö]+/g)??[],months=tokens.filter(t=>monthNames.includes(t)).map(t=>monthNames.indexOf(t)+1);
 if(months.length!==1||tokens.some(t=>!monthNames.includes(t)))throw Error('Exporten måste ange en entydig slutmånad för ackumulerat utfall.');
 const centers=[...new Set([...centerLine[1].matchAll(/\b(10|20|30|40|50|60|90)\s/g)].map(m=>m[1]))].sort();
 if(!centers.length)throw Error('Kostnadsställen saknas i exportens filter.');
 const year=2000+Number(fiscal[1]),month=months[0],endYear=year+(month<9?1:0);
 const metric=(label:string,grand=false)=>{
  const found=rows.map((r,i)=>({r,row:i+1})).filter(({r})=>String(r[0]??'').trim()===label&&(grand?r[1]==null:String(r[1]).trim()==='Total'));
  if(found.length!==1||typeof found[0].r[2]!=='number'||!Number.isFinite(found[0].r[2]))throw Error('Entydigt belopp saknas: '+label);
  return {value:found[0].r[2] as number,previous:typeof found[0].r[6]==='number'?found[0].r[6] as number:null,row:found[0].row};
 };
 return {from:`${year}-09-01`,to:`${endYear}-${String(month).padStart(2,'0')}-${new Date(Date.UTC(endYear,month,0)).getUTCDate()}`,cost_center:centers.join(','),sheet:name,filters,
  metrics:{revenue:metric('Rörelsens intäkter'),result:metric('Total',true),fuel:metric('Bränsle'),personnel:metric('Personalkostnader'),depreciation:metric('Avskrivningar')},
  notes:'Ackumulerat utfall från exportens huvudrader. Slutraden Total används för resultat. Mellansummor och upprepade undergrupper summeras inte.'};
}
