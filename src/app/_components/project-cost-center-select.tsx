'use client';
const centers=[['10','Entreprenad och maskinuthyrning'],['20','Sortergården'],['30','Transport'],['40','Verkstad'],['50','Fastigheter'],['60','Skåne'],['90','Övrigt']];
export function ProjectCostCenterSelect({value}:{value:string|null}){
 return <label>Kostnadsställe<select name="center" defaultValue={value??''} onChange={event=>{
  const form=event.currentTarget.form;if(!form)return;
  // A new cost center starts with all its active groups, rather than retaining a group from another center.
  form.querySelectorAll<HTMLInputElement>('input[name="group"]').forEach(input=>{if(input.type==='checkbox')input.checked=false;else input.disabled=true;});
  form.querySelectorAll<HTMLInputElement>('input[name="project"]').forEach(input=>{input.disabled=true;});
  form.requestSubmit();
 }}><option value="">Alla kostnadsställen</option>{centers.map(([code,name])=><option key={code} value={code}>{code} {name}</option>)}</select></label>;
}
