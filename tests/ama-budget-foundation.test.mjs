import test from 'node:test';
import assert from 'node:assert/strict';
import {classifyAmaReference,budgetRowFromSource} from '../src/lib/hub/ama-budget-foundation.mjs';
test('do not invent missing edition or official AMA validity',()=>{
 assert.equal(classifyAmaReference({system:'AMA',discipline:'Anlaggning',code:'ABC',source:'offer'}).status,'needs_review');
});
test('priced source row is only draft and retains provenance',()=>{
 const r=budgetRowFromSource({reference:{system:'AMA',discipline:'ANLAGGNING',edition:'26',code:'EXAMPLE',source:'project_document'},
 sourceDocumentId:'doc-1',sourcePage:3,description:'Schakt',quantity:25,unit:'m3',unitPrice:90});
 assert.equal(r.status,'draft_requires_approval');
 assert.equal(r.extendedPrice,2250);
 assert.equal(r.sourcePage,3);
});
test('reject amount without document provenance',()=>{assert.equal(budgetRowFromSource({quantity:2,unitPrice:3,unit:'m3',description:'Schakt'}).status,'needs_review');});
