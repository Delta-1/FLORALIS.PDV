import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const read = file => readFileSync(new URL(`../${file}`, import.meta.url), 'utf8');
const studio = read('document-studio.js');
const app = read('app.js');
const backend = read('backend.js');
const styles = read('styles.css');

for (const id of ['cash-closing', 'sale-receipt', 'zona-franca-invoice']) {
  assert.match(studio, new RegExp(`['"]${id}['"]`), `modelo ${id} deve existir`);
}

assert.match(studio, /data-reference-template/, 'modelos especiais devem ser identificáveis');
assert.match(studio, /REQUIERE HOMOLOGACIÓN DEL SIN/, 'factura deve expor aviso de homologação');
assert.match(studio, /openSaleReceipt/, 'API do recibo deve estar disponível');
assert.match(studio, /openZonaFrancaInvoice/, 'API da factura deve estar disponível');
assert.match(app, /data-doc-sale-receipt/, 'venda deve oferecer recibo A4');
assert.match(app, /data-doc-zona-invoice/, 'venda deve oferecer factura de Zona Franca');
assert.match(studio, /DADOS DO CLIENTE/, 'informe A4 deve seguir o modelo físico enviado');
assert.match(studio, /PEDIDOS AL CEL\./, 'informe A4 deve manter o rodapé operacional do modelo');
assert.match(studio, /saleItemsWithBlanks\(sale,8\)/, 'informe A4 deve reservar oito linhas de produtos');

for (const field of ['zone', 'pointOfSale', 'authorizationCode']) {
  assert.match(app, new RegExp(`name=['"]${field}['"]`), `${field} deve ser configurável`);
  assert.match(backend, new RegExp(`${field}: settings\\.${field}`), `${field} deve persistir no Supabase`);
}

assert.match(app, /name="saleReceiptTemplate"/, 'configurações devem permitir escolher o modelo do recibo');
assert.match(app, /Cupón térmico 80mm/, 'finalização deve priorizar o cupom térmico');
assert.match(app, /class="receipt-paper/, 'venda deve abrir a prévia do cupom');
assert.match(app, /Moneda recibida/, 'cupom deve identificar a moeda efetivamente recebida');
assert.match(app, /Valor recibido/, 'cupom deve imprimir o valor recebido');
assert.match(styles, /@page\{size:80mm auto/, 'impressão deve usar bobina de 80 mm');
assert.match(styles, /\.receipt-paper\{width:80mm/, 'prévia deve manter a largura térmica');
assert.match(app, /\['Unidad','Paquete','Caja','Balde','Bolsa','Botella','Lata','Kg'\]/, 'cadastro de produtos deve oferecer Balde como unidade de medida');
assert.match(studio, /receiptTemplate==='modern'/, 'renderização deve alternar entre modelo clássico e moderno');
assert.match(backend, /saleReceiptTemplate: settings\.saleReceiptTemplate/, 'modelo escolhido deve persistir no Supabase');
assert.match(studio, /const styles=\{official:'Oficial tabular'\}/, 'todos os documentos devem usar apenas o padrão oficial');
assert.match(studio, /style:'official',accent:'#111111'/, 'configuração salva não deve reativar estilos decorativos');
assert.match(styles, /Padrão oficial tabular para todos os documentos gerados/, 'relatórios genéricos devem possuir grade oficial própria');
assert.match(styles, /style-official:not\(\.reference-document\).*border:1px solid #222/, 'documentos oficiais devem usar bordas tabulares pretas');
assert.match(styles, /Tipografia operacional FLORALES/, 'sistema deve possuir padrão tipográfico único');
assert.doesNotMatch(app, /state\.clients=\[\];state\.products=\[\];state\.sales=\[\]/, 'atualizações não podem apagar a operação local');
assert.match(app, /Migrações preservadoras/, 'migrações locais devem preservar os dados existentes');
assert.match(styles, /font-family:Arial,Helvetica,sans-serif!important/, 'sistema e documentos devem usar Arial');
assert.match(styles, /text-transform:uppercase/, 'todos os textos devem aparecer em maiúsculas');
assert.match(styles, /font-variant-numeric:tabular-nums lining-nums/, 'valores devem usar números tabulares alinhados');
assert.match(styles, /receipt-modal>\*:not\(\.layer-body\)\{display:none!important\}/, 'impressão do cupom não deve incluir botões do sistema');
assert.match(styles, /padding:2mm!important/, 'cupom deve usar margens térmicas pequenas');

for (const cssClass of ['reference-cash', 'reference-receipt', 'reference-zona']) {
  assert.match(styles, new RegExp(`\\.${cssClass}`), `${cssClass} deve possuir estilo próprio`);
}

assert.match(studio, /saveGeneratedDocument/, 'documentos gerados devem manter histórico persistente');
console.log('Relatórios de referência: contratos verificados.');
