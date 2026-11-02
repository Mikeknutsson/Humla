const fs=require('fs'),ts=require('typescript'),vm=require('vm'),assert=require('assert/strict'),React=require('react'),{renderToStaticMarkup}=require('react-dom/server');
const {report,missing}=require('./test-payment-evidence-model.cjs');
const exportsObject={};const code=ts.transpileModule(fs.readFileSync('src/app/_components/payment-forecast-evidence.tsx','utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022,jsx:ts.JsxEmit.ReactJSX}}).outputText;
vm.runInNewContext(code,{exports:exportsObject,require,Date,Intl,Set,Map,Number,Math,Object,Array,Error});
const view=r=>renderToStaticMarkup(React.createElement(exportsObject.PaymentForecastEvidence,{forecast:r,busy:false,onReviewed:async()=>{}}));
const html=view(report);assert.ok(html.includes('2026-11-30')&&html.includes('2026-12-27'));assert.ok(html.includes('2 820')||html.includes('2&#xA0;820'));assert.ok(html.includes('före löner och moms'));assert.ok(html.includes('Registrerat underlag'));assert.ok(html.includes('Exportera periodtotal till bolagets prognos'));assert.ok(html.includes('2026-12-15'));
const partial=view(missing);assert.ok(partial.includes('Komplett periodtotal saknas'));assert.ok(!partial.includes('Exportera periodtotal till bolagets prognos'));
console.log('PASS: rendered transfer amount/period/basis, monthly Stena evidence and no full-total export for an incomplete forecast.');
