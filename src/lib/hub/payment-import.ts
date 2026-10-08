import type {Payment} from './payment-forecast';
export function parsePaymentCsv(text:string):Payment[]{
 const records:string[][]=[];let record:string[]=[],cell='',quoted=false;
 text=text.replace(/^\uFEFF/,'');
 for(let i=0;i<text.length;i++){
  const ch=text[i];
  if(ch==='"'){if(quoted&&text[i+1]==='"'){cell+='"';i++}else if(quoted||cell==='')quoted=!quoted;else throw Error('Felaktig CSV-citering')}
  else if(ch===';'&&!quoted){record.push(cell);cell=''}
  else if((ch==='\n'||ch==='\r')&&!quoted){if(ch==='\r'&&text[i+1]==='\n')i++;record.push(cell);if(record.some(v=>v.trim()))records.push(record);record=[];cell=''}
  else cell+=ch;
 }
 if(quoted)throw Error('Oavslutat CSV-fält');record.push(cell);if(record.some(v=>v.trim()))records.push(record);
 if(records.shift()?.map(v=>v.trim().toLowerCase()).join(';')!=='id;kst;typ;datum;belopp;intern')throw Error('Kolumner: id;kst;typ;datum;belopp;intern');
 return records.map((r,i)=>{
  if(r.length!==6)throw Error(`Rad ${i+2}: sex kolumner krävs`);
  const [id,center,kind,date,value,internal]=r.map(v=>v.trim()),normalized=value.replace(/[ \u00a0]/g,'').replace(',','.');
  if(!['in','out'].includes(kind)||!['ja','nej'].includes(internal)||!/^\-?\d+(\.\d{1,2})?$/.test(normalized))throw Error(`Rad ${i+2}: kontrollera typ (in/out), belopp och intern (ja/nej)`);
  return {id,center,kind:kind as 'in'|'out',date,amount:Number(normalized),internal:internal==='ja'};
 });
}
