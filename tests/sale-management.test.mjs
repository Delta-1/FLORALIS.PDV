import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
const source=readFileSync(new URL('../app.js',import.meta.url),'utf8');
const functions=source.slice(source.indexOf('function saleManagementButtons('),source.indexOf('function saleView('));
function context(admin=true){const button={disabled:false},ctx={canAdmin:()=>admin,esc:String,state:{sales:[{id:'V1',total:100}],offlineQueue:[]},navigator:{onLine:true},terminalId:'test',button,saleEditItems:()=>[],FloralisBackend:{changeSale:async()=>{throw Error('network failure')}},$:()=>null};vm.createContext(ctx);vm.runInContext(functions,ctx);return ctx}
test('sale controls respect administrator permission and cancelled state',()=>{const admin=context(),employee=context(false);assert.match(admin.saleManagementButtons({id:'V1'}),/data-sale-edit/);assert.match(admin.saleManagementButtons({id:'V1'}),/data-sale-cancel/);assert.equal(employee.saleManagementButtons({id:'V1'}),'');assert.doesNotMatch(admin.saleManagementButtons({id:'V1',status:'cancelled'}),/data-sale-edit|data-sale-cancel/)});
test('cancelled sales contribute zero to currency totals',()=>{const fn=source.match(/const saleColumnAmount=([^\n]+)/)[0];const ctx={saleReportCurrency:()=> 'BOB',saleOriginalAmount:()=>100};vm.createContext(ctx);vm.runInContext(fn+';globalThis.amount=saleColumnAmount;',ctx);assert.equal(ctx.amount({status:'cancelled',amountBob:100},'BOB'),0);assert.equal(ctx.amount({amountBrl:75},'BRL'),75)});
test('offline cancellations and employee calls never reach backend',async()=>{for(const [admin,online] of [[false,true],[true,false]]){const ctx=context(admin);ctx.navigator.onLine=online;await assert.rejects(ctx.submitSaleChange({dataset:{id:'V1',cancel:'1'}},{reason:'test'}));assert.equal(ctx.state.sales[0].status,undefined)}});
test('failed cancellation keeps sale active and permits retry',async()=>{const ctx=context(),form={dataset:{id:'V1',cancel:'1'},querySelector:()=>ctx.button};await assert.rejects(ctx.submitSaleChange(form,{reason:'test'}),/network failure/);assert.equal(ctx.button.disabled,false);assert.equal(ctx.state.sales[0].status,undefined)});
