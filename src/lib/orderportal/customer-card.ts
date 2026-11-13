export type CustomerContact = { name:string; email:string; phone:string };
export type CustomerMarking = { number:string; description:string };
export type DocumentSettings = {
 deliveryNote:boolean; invoiceData:boolean; showRoute:boolean; signature:boolean; recipient:string;
};
export type CustomerProfile = {
 contacts:CustomerContact[]; markings:CustomerMarking[]; documents:DocumentSettings; note:string;
};
export type CustomerCard = { profile:CustomerProfile; revision:number };

export function emptyCustomerProfile():CustomerProfile {
 return {contacts:[],markings:[],documents:{deliveryNote:false,invoiceData:false,showRoute:false,signature:false,recipient:''},note:''};
}

export function parseCustomerProfile(value:unknown):CustomerProfile {
 function object(v:unknown):Record<string,unknown>{
  if(!v||typeof v!=='object'||Array.isArray(v))throw Error('Ogiltigt kundkort.');
  return v as Record<string,unknown>;
 }
 function string(v:unknown,max:number,required=false){
  if(typeof v!=='string'||v.trim().length>max||(required&&!v.trim()))throw Error('Kontrollera obligatoriska fält och textlängder.');
  return v.trim();
 }
 function email(v:unknown){
  const address=string(v,254);
  if(address&&!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(address))throw Error('Ange en giltig e-postadress.');
  return address;
 }
 function flag(v:unknown){
  if(typeof v!=='boolean')throw Error('Ogiltig dokumentinställning.');
  return v;
 }
 const profile=object(value), documents=object(profile.documents);
 if(!Array.isArray(profile.contacts)||!Array.isArray(profile.markings)||profile.contacts.length>50||profile.markings.length>100)
  throw Error('Högst 50 kontakter och 100 märkningar per kundkort.');
 const contacts=profile.contacts.map(value=>{
  const contact=object(value);
  return {name:string(contact.name,150,true),email:email(contact.email),phone:string(contact.phone,60)};
 });
 const markings=profile.markings.map(value=>{
  const marking=object(value);
  return {number:string(marking.number,80,true),description:string(marking.description,250)};
 });
 if(new Set(markings.map(m=>m.number.toLocaleLowerCase('sv-SE'))).size!==markings.length)
  throw Error('Varje märkning måste ha ett eget nummer.');
 return {contacts,markings,note:string(profile.note,2000),documents:{
  deliveryNote:flag(documents.deliveryNote),invoiceData:flag(documents.invoiceData),
  showRoute:flag(documents.showRoute),signature:flag(documents.signature),recipient:email(documents.recipient),
 }};
}
