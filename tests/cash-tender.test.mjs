import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
const source=readFileSync(new URL('../app.js',import.meta.url),'utf8');
const context=vm.createContext({});
vm.runInContext(source.slice(source.indexOf('function parseTenderAmount('),source.indexOf('function paymentCashTender(')),context);
const tender=(total,first,extra)=>context.cashTenderSummary(total,first,extra);
test('cash overpayment produces change and exact payment has zero change',()=>{
 assert.equal(tender(180,'200').change,20);
 assert.equal(tender(180,'180').change,0);
 assert.equal(tender(180,'200').received,200);
 assert.equal(tender(180,'200').remaining,0);
});
test('underpayment shows received money and remaining amount, never negative change',()=>{
 const result=tender(180,'100');assert.equal(result.received,100);assert.equal(result.remaining,80);assert.equal(result.change,0);
});
test('a second cash delivery can complete the sale and produce its own change',()=>{
 const exact=tender(180,'100','80');assert.equal(exact.remaining,0);assert.equal(exact.received,180);assert.equal(exact.change,0);
 const excess=tender(180,'100','100');assert.equal(excess.received,200);assert.equal(excess.change,20);
});
test('decimal input accepts comma or point without binary floating-point change errors',()=>{
 assert.equal(tender(19.9,'20,00').change,.1);
 assert.equal(tender(.3,'0.10','0,20').remaining,0);
 assert.equal(context.parseTenderAmount('1.234,56'),1234.56);
 assert.equal(context.parseTenderAmount('1,234.56'),1234.56);
});
test('invalid, negative and malformed cash amounts cannot become a paid sale',()=>{
 for(const value of ['','-10','abc','1e3','NaN','Infinity','1.234','12,3.45'])assert.equal(tender(100,value).valid,false,value);
 assert.equal(tender(100,'100','bad').valid,false);
 assert.equal(tender(100,Infinity).valid,false);
});
