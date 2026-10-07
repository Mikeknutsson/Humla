import Link from 'next/link';
import {redirect} from 'next/navigation';
import {createClient} from '@/lib/supabase/server';
import {parseMonthPeriod} from '@/lib/kpi/period';
import {filterKeys,analysisHref} from '@/lib/kpi/analysis';
import {KpiDetailShell} from '@/app/_components/kpi-detail-shell';
export const dynamic='force-dynamic';
const number=new Intl.NumberFormat('sv-SE',{maximumFractionDigits:2});
type InvoiceDay={order_number:string;article_date:string;first_article_date:string;completion_date:string;completion_source:'order_end'|'last_article';invoice_date:string;days_to_invoice:number;customer_name:string|null;units:string;source_rows:number;is_internal:boolean};
type InvoiceReport={average_days:number|null;orders:number;row_count:number;averaged_orders:number;internal_average_days:number|null;internal_averaged_orders:number;internal_orders:number;zero_orders:number;invalid_orders:number;fallback_orders:number;rows:InvoiceDay[]};
export default async function InvoicePage({searchParams}:{searchParams:Promise<Record<string,string|undefined>>}) {
 const raw=await searchParams;
 const params=new URLSearchParams(Object.entries(raw).filter((entry):entry is [string,string]=>entry[1]!==undefined));
 let period:ReturnType<typeof parseMonthPeriod>;
 try {period=parseMonthPeriod(raw.fiscal_year,raw.months);} catch {return <main>Ogiltig rapportperiod. <Link href="/kpi">Till Översikt</Link></main>;}
 const customer=raw.invoice_customer;
 if(customer!==undefined&&customer!=='external'&&customer!=='internal')return <main>Ogiltigt kundurval.</main>;
 const internal=customer==='internal';
 const page=Number(raw.page??0);
 if(!Number.isInteger(page)||page<0||page>100000)return <main>Ogiltig sida.</main>;
 const db=await createClient();const {data:{user}}=await db.auth.getUser();if(!user)redirect('/kpi/login');
 const {data:member}=await db.from('hub_tenant_members').select('tenant_id').eq('user_id',user.id).eq('status','active').limit(1).maybeSingle();
 if(!member)return <main>Arbetsyta saknas.</main>;
 const filters=Object.fromEntries(filterKeys.filter(key=>params.has(key)).map(key=>[key,params.get(key)!]));
 if(customer)filters.invoice_customer=customer;
 const {data,error}=await db.rpc('hub_kpi_invoice_lead_time_v1',{p_tenant_id:member.tenant_id,p_year:period.fiscalYear,p_months:period.months,p_filters:filters,p_page:page});
 const report=data as InvoiceReport|null;
 const pageHref=(value:number)=>{const query=new URLSearchParams(params);query.set('page',String(value));return `/kpi/fakturering?${query}`;};
 return <KpiDetailShell query={params.toString()}><div className="content"><h1>Genomsnittlig faktureringstid</h1><p>Orderns slutdatum → fakturadatum i kalenderdagar. Om slutdatum saknas används sista artikeldatumet. Varje order räknas en gång. Urvalet gäller ordrar med artikelrader i vald period och aktiva filter; hela orderns datum används. Ofakturerade ordrar ingår inte.</p>{error||!report?<p role="alert">Faktureringsunderlaget kunde inte hämtas.</p>:<>
 <section className="panel"><h2>{(internal?report.internal_average_days:report.average_days)===null?'Underlag saknas':`${number.format((internal?report.internal_average_days:report.average_days)!)} dagar`}</h2>{internal&&<p><strong>Elleholms Maskin · internöverföringar</strong></p>}<p>Huvudsnittet gäller externa kunder. Elleholms Maskin som kund redovisas separat som internöverföringar.</p><table><thead><tr><th>Underlag</th><th>Externa kunder</th><th>Internöverföringar</th></tr></thead><tbody><tr><th>Genomsnittlig faktureringstid</th><td>{report.average_days===null?'Underlag saknas':`${number.format(report.average_days)} dagar`}</td><td>{report.internal_average_days===null?'Underlag saknas':`${number.format(report.internal_average_days)} dagar`}</td></tr><tr><th>Ordrar i snittet</th><td>{number.format(report.averaged_orders)}</td><td>{number.format(report.internal_averaged_orders)}</td></tr></tbody></table><p>{number.format(report.zero_orders)} ordrar med 0 dagar visas i underlaget men ingår inte i något snitt. {number.format(report.internal_orders)} ordrar är internöverföringar.</p><p>{number.format(report.orders)} fakturerade ordrar med giltiga datum. {number.format(report.fallback_orders)} använder sista artikeldatumet eftersom slutdatum saknas.</p>{report.invalid_orders>0&&<p role="status"><strong>Preliminärt underlag:</strong> {number.format(report.invalid_orders)} ordrar med ogiltiga, motstridiga eller negativa datum är uteslutna. Fakturering före avslut eller slutdatum före sista artikeldatum räknas inte som noll dagar.</p>}</section>
 <section className="panel"><h2>Fakturerade ordrar</h2><p>Sorterade med längst faktureringstid först. Samma period och filter som Översikten. {customer==='internal'?'Visar Elleholms Maskin.':customer==='external'?'Visar externa kunder.':'Visar båda kundtyperna.'}</p><div className="table-wrap"><table><thead><tr><th>Workify-order</th><th>Kund</th><th>Typ</th><th>Enhet / fordon</th><th>Första artikel</th><th>Sista artikel</th><th>Avslut</th><th>Datumkälla</th><th>Fakturadatum</th><th>Dagar</th></tr></thead><tbody>{report.rows.map(row=><tr key={row.order_number}><td><details><summary>{row.order_number}</summary><p>{row.source_rows} underlagsrader, räknade som en order.</p><Link prefetch={false} href={analysisHref(params.toString(),{source:'Workify',kind:'revenue',level:'transaction',date_from:row.first_article_date,date_to:row.article_date})}>Öppna orderperiodens underlag</Link></details></td><td>{row.customer_name??'–'}</td><td>{row.is_internal?'Internöverföring':'Extern'}</td><td>{row.units}</td><td>{row.first_article_date}</td><td>{row.article_date}</td><td>{row.completion_date}</td><td>{row.completion_source==='order_end'?'Orderns slutdatum':'Sista artikeldatum'}</td><td>{row.invoice_date}</td><td>{number.format(row.days_to_invoice)}</td></tr>)}</tbody></table></div>{report.rows.length===0&&<p>Inga fakturerade ordrar med giltiga datum i urvalet.</p>}<nav>{page>0&&<Link prefetch={false} href={pageHref(page-1)}>← Föregående</Link>}{(page+1)*100<report.row_count&&<Link prefetch={false} href={pageHref(page+1)}>Nästa →</Link>}</nav></section>
 </>}</div></KpiDetailShell>;
}
