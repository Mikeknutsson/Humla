'use client';
export function KpiEvidenceAmount({id,amount}:{id:string;amount:string}) {
 return <button type="button" className="evidence-amount" aria-label={`Visa originalunderlag för ${amount}`} onClick={()=>{
  const details=document.getElementById(id);
  if(details instanceof HTMLDetailsElement){details.open=true;details.scrollIntoView({block:'nearest'});}
 }}>{amount}</button>;
}
