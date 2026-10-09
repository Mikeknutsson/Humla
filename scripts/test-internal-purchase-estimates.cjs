// Verify live RPC snapshots, without authoring a workbook or modifying data.
const fs=require('node:fs'),assert=require('node:assert/strict');
if(!process.argv[2])throw Error('Usage: node scripts/test-internal-purchase-estimates.cjs after.json [before.json]');
const after=JSON.parse(fs.readFileSync(process.argv[2],'utf8'));
const before=process.argv[3]?JSON.parse(fs.readFileSync(process.argv[3],'utf8')):null;
const round=n=>Math.round(n*100)/100;
let tips=0,materials=0,newEstimates=0;
for(const r of after.rows){const p=r.purchase;
 if(r.category==='tipp_deponi'&&r.amount!==null){tips++;assert.equal(p.amount,round(r.amount*0.8));assert.equal(p.margin,round(r.amount-p.amount));assert.equal(p.status,'tipping_80pct');assert.equal(p.receipt_cost,null);}
 if(r.category==='material'&&p.quantity!==null&&p.rate!==null){materials++;assert.equal(p.amount,round(p.quantity*p.rate));if(p.status==='material_overview_estimate'){assert.equal(p.receipt_cost,null);assert.ok(p.price_source.includes('verslag'));assert.ok(p.price_sample_count>0);}}
 if(before){const old=before.rows.find(o=>o.row_id===r.row_id);assert.ok(old);const {purchase:oldPurchase,...oldSource}=old;const {purchase,...source}=r;assert.deepEqual(source,oldSource);
  if(r.category==='material'){if(oldPurchase.amount===null&&p.amount!==null)newEstimates++;else if(oldPurchase.amount!==null)assert.equal(p.amount,oldPurchase.amount);}
  else if(r.category!=='tipp_deponi')assert.deepEqual(p,oldPurchase);
 }
}
console.log(JSON.stringify({tips,materials,newEstimates,sourceAndTransfersUnchanged:true}));
