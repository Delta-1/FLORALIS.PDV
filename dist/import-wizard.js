(() => {
  const SHEETJS_URL = 'https://cdn.sheetjs.com/xlsx-0.20.3/package/dist/xlsx.full.min.js';
  let pending = null;

  const normalize = value => String(value ?? '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();
  const specs = {
    products: [
      ['name', 'Nome do produto', ['nome','produto','descricao','description','name','articulo']],
      ['code', 'Código interno', ['codigo','code','sku','referencia','reference']],
      ['ean', 'EAN / código de barras', ['ean','gtin','codigo de barras','barcode']],
      ['category', 'Categoria', ['categoria','category','grupo','departamento']],
      ['stock', 'Estoque atual', ['estoque','stock','quantidade','cantidad','saldo fisico']],
      ['minStock', 'Estoque mínimo', ['estoque minimo','stock minimo','min stock']],
      ['cost', 'Preço de custo', ['custo','cost','precio costo','preco custo']],
      ['price', 'Preço de venda', ['preco','price','precio venta','valor venda']],
      ['wholesale', 'Preço mayorista', ['atacado','wholesale','mayorista','preco atacado','precio mayorista']],
      ['unit', 'Unidade', ['unidade','unit','unidad','medida']],
      ['notes', 'Observações', ['observacao','observacoes','notes','notas','detalle']]
    ],
    clients: [
      ['name', 'Nome / razão social', ['nome','cliente','name','razon social','razao social']],
      ['code', 'Código do cliente', ['codigo','code','codigo cliente']],
      ['document', 'CPF / CI / NIT', ['cpf','ci','nit','documento','document','cedula']],
      ['phone', 'Telefone / celular', ['telefone','celular','phone','telefono','whatsapp']],
      ['city', 'Cidade', ['cidade','city','ciudad','municipio']],
      ['type', 'Tipo de cliente', ['tipo','type','clasificacion']],
      ['balance', 'Saldo atual', ['saldo','balance','credito','credito disponivel']],
      ['debt', 'Valor da dívida', ['divida','deuda','debito','valor devido','debt']],
      ['notes', 'Observações', ['observacao','observacoes','notes','notas','detalle']]
    ]
  };

  function suggest(header, type) {
    const value = normalize(header);
    let best = '';
    let score = 0;
    for (const [key, , aliases] of specs[type] || []) for (const alias of aliases) {
      const normalizedAlias = normalize(alias);
      const next = value === normalizedAlias ? 3 : value.includes(normalizedAlias) || normalizedAlias.includes(value) ? 2 : 0;
      if (next > score) { best = key; score = next; }
    }
    return best;
  }

  function parseDelimited(text) {
    const sample = text.split(/\r?\n/).slice(0,5).join('\n');
    const separators = [',',';','\t','|'];
    const separator = separators.sort((a,b)=>(sample.split(b).length-sample.split(a).length))[0];
    const rows=[];let row=[],value='',quoted=false;
    for(let i=0;i<text.length;i++){
      const char=text[i],next=text[i+1];
      if(char==='"'&&quoted&&next==='"'){value+='"';i++}
      else if(char==='"')quoted=!quoted;
      else if(char===separator&&!quoted){row.push(value);value=''}
      else if((char==='\n'||char==='\r')&&!quoted){if(char==='\r'&&next==='\n')i++;row.push(value);if(row.some(cell=>String(cell).trim()))rows.push(row);row=[];value=''}
      else value+=char;
    }
    if(value||row.length){row.push(value);rows.push(row)}
    return rows;
  }

  function loadSheetJs() {
    if (window.XLSX) return Promise.resolve(window.XLSX);
    return new Promise((resolve, reject) => {
      const existing = document.querySelector('script[data-sheetjs]');
      if (existing) { existing.addEventListener('load',()=>resolve(window.XLSX),{once:true}); existing.addEventListener('error',reject,{once:true}); return; }
      const script=document.createElement('script');script.src=SHEETJS_URL;script.dataset.sheetjs='1';script.onload=()=>resolve(window.XLSX);script.onerror=()=>reject(new Error('Não foi possível carregar o leitor XLSX. Salve a planilha como CSV e tente novamente.'));document.head.appendChild(script);
    });
  }

  async function readFile(file) {
    if (/\.xlsx?$|\.xls$/i.test(file.name)) {
      const XLSX = await loadSheetJs();
      const workbook = XLSX.read(await file.arrayBuffer(), {type:'array',cellDates:true});
      const sheet = workbook.Sheets[workbook.SheetNames[0]];
      return XLSX.utils.sheet_to_json(sheet, {header:1,defval:'',raw:false});
    }
    return parseDelimited(await file.text());
  }

  function mappingOptions(type, selected) {
    return `<option value="">Ignorar coluna</option>${(specs[type]||[]).map(([key,label])=>`<option value="${key}" ${selected===key?'selected':''}>${label}</option>`).join('')}`;
  }

  function showWizard(file, type, matrix) {
    const headers=(matrix.shift()||[]).map((header,index)=>String(header||`Coluna ${index+1}`).trim()),rows=matrix.filter(row=>row.some(value=>String(value).trim()));
    if(!headers.length||!rows.length)throw new Error('A planilha não possui cabeçalho e linhas de dados.');
    pending={file,type,headers,rows};
    const mapping=headers.map((header,index)=>`<label class="import-map-card"><span>COLUNA ${index+1}</span><strong>${esc(header)}</strong><select data-import-column="${index}">${mappingOptions(type,suggest(header,type))}</select><small>${esc(String(rows[0]?.[index]??'').slice(0,80))||'Sem exemplo'}</small></label>`).join('');
    const previewHeaders=headers.map(header=>`<th>${esc(header)}</th>`).join(''),previewRows=rows.slice(0,6).map(row=>`<tr>${headers.map((_,index)=>`<td>${esc(String(row[index]??''))}</td>`).join('')}</tr>`).join('');
    openLayer(`${layerHead('Assistente de importação')}<form id="universalImportForm"><div class="layer-body import-wizard"><div class="import-file-summary"><span>${svg('upload')}</span><div><strong>${esc(file.name)}</strong><small>${rows.length} linhas · ${headers.length} colunas · ${type==='products'?'Produtos':'Clientes'}</small></div></div><section><div class="import-section-head"><div><strong>O que significa cada coluna?</strong><small>Confirme o mapeamento sugerido ou escolha outro campo.</small></div><span>1</span></div><div class="import-map-grid">${mapping}</div></section><section><div class="import-section-head"><div><strong>Prévia da planilha</strong><small>As primeiras linhas são exibidas antes da confirmação.</small></div><span>2</span></div><div class="import-preview-scroll"><table class="data-table"><thead><tr>${previewHeaders}</tr></thead><tbody>${previewRows}</tbody></table></div></section><div class="form-warning">Nenhum dado será importado até você confirmar. A coluna de nome é obrigatória.</div></div><footer class="layer-foot"><button type="button" class="btn" data-action="close-layer">Cancelar</button><button class="btn primary">Validar e importar ${rows.length} linhas</button></footer></form>`,'modal import-wizard-modal');
  }

  function localeNumber(value) {
    let text=String(value??'').trim().replace(/[^0-9,.-]/g,'');if(!text)return 0;
    const comma=text.lastIndexOf(','),dot=text.lastIndexOf('.');
    if(comma>dot)text=text.replace(/\./g,'').replace(',','.');else if(dot>comma)text=text.replace(/,/g,'');else text=text.replace(',','.');
    const number=Number(text);return Number.isFinite(number)?number:0;
  }

  async function persistInBatches(items, saver) {
    for(let index=0;index<items.length;index+=20)await Promise.all(items.slice(index,index+20).map(saver));
  }

  async function importMapped(form) {
    if(!pending)return;
    const mapping={};form.querySelectorAll('[data-import-column]').forEach(select=>{if(select.value)mapping[select.value]=Number(select.dataset.importColumn)});
    if(mapping.name==null)throw new Error('Selecione qual coluna contém o nome.');
    const value=(row,key)=>mapping[key]==null?'':String(row[mapping[key]]??'').trim(),textValue=(row,key,fallback='')=>mapping[key]==null?fallback:(value(row,key)||fallback),numberValue=(row,key,fallback=0)=>mapping[key]==null?Number(fallback||0):localeNumber(value(row,key));
    const errors=[];
    if(pending.type==='products'){
      const imported=pending.rows.map((row,index)=>{const name=value(row,'name');if(!name){errors.push(`Linha ${index+2}: nome vazio`);return null}const importedCode=value(row,'code'),importedEan=value(row,'ean'),existing=state.products.find(product=>importedCode&&product.code===importedCode||importedEan&&product.ean===importedEan),code=importedCode||existing?.code||`IMP-${Date.now()}-${index+1}`,ean=textValue(row,'ean',existing?.ean||'');return{...existing,id:existing?.id||`P${Date.now()}${index}`,name,code,ean,category:textValue(row,'category',existing?.category||'General'),stock:numberValue(row,'stock',existing?.stock),minStock:numberValue(row,'minStock',existing?.minStock),cost:numberValue(row,'cost',existing?.cost),price:numberValue(row,'price',existing?.price),wholesale:numberValue(row,'wholesale',existing?.wholesale),unit:textValue(row,'unit',existing?.unit||'Unidad'),notes:textValue(row,'notes',existing?.notes||''),active:existing?.active!==false}}).filter(Boolean);
      if(errors.length)throw new Error(errors.slice(0,4).join(' · '));
      await persistInBatches(imported,async product=>{const saved=await FloralisBackend.saveProduct(product);if(saved?.id)product.id=saved.id;const index=state.products.findIndex(item=>item.id===product.id||item.code===product.code);index>=0?state.products[index]=product:state.products.push(product)});
      save();auditEvent('Produtos importados','Importação',`${imported.length} linhas · ${pending.file.name}`,'success');closeLayer();render();toast(`${imported.length} produtos importados`);
    }else{
      const imported=pending.rows.map((row,index)=>{const name=value(row,'name');if(!name){errors.push(`Linha ${index+2}: nome vazio`);return null}const importedDocument=value(row,'document'),importedCode=value(row,'code'),existing=state.clients.find(client=>importedCode&&client.code===importedCode||importedDocument&&client.document===importedDocument),code=importedCode||existing?.code||`IMP-${Date.now()}-${index+1}`,document=textValue(row,'document',existing?.document||''),debt=value(row,'debt'),balance=mapping.debt!=null?(debt?-Math.abs(localeNumber(debt)):0):numberValue(row,'balance',existing?.balance);return{...existing,id:existing?.id||`C${Date.now()}${index}`,name,code,document,phone:textValue(row,'phone',existing?.phone||''),city:textValue(row,'city',existing?.city||''),type:textValue(row,'type',existing?.type||'Minorista'),balance,notes:textValue(row,'notes',existing?.notes||''),purchases:existing?.purchases||0,total:existing?.total||0,photo:existing?.photo||'',ledger:existing?.ledger||[]}}).filter(Boolean);
      if(errors.length)throw new Error(errors.slice(0,4).join(' · '));
      await persistInBatches(imported,async client=>{const saved=await FloralisBackend.saveClient(client);if(saved?.id)client.id=saved.id;const index=state.clients.findIndex(item=>item.id===client.id||item.code===client.code);index>=0?state.clients[index]=client:state.clients.push(client)});
      save();auditEvent('Clientes importados','Importação',`${imported.length} linhas · ${pending.file.name}`,'success');closeLayer();render();toast(`${imported.length} clientes importados`);
    }
    pending=null;
  }

  function downloadTemplate(type) {
    const products='nome,codigo,ean,categoria,estoque,estoque_minimo,preco_custo,preco_venda,preco_mayorista,unidade,observacoes\nFiltro de óleo,000001,7890000000019,Filtros,10,2,18.50,30.00,26.00,Unidade,Exemplo';
    const clients='nome,codigo,cpf_ci_nit,telefone,cidade,tipo,valor_divida,observacoes\nCliente exemplo,000001,1234567,70000000,Cobija,Minorista,150.00,Exemplo de dívida';
    download(`modelo-importacao-${type==='products'?'produtos':'clientes'}.csv`,'\ufeff'+(type==='products'?products:clients),'text/csv;charset=utf-8');
    auditEvent('Modelo de importação baixado','Importação',type==='products'?'Produtos':'Clientes');
  }

  document.addEventListener('change',async event=>{
    const mappingSelect=event.target.closest?.('[data-import-column]');
    if(mappingSelect&&mappingSelect.value){mappingSelect.closest('form').querySelectorAll('[data-import-column]').forEach(other=>{if(other!==mappingSelect&&other.value===mappingSelect.value)other.value='' });return}
    const input=event.target;if(input?.id!=='importInput'||!['products','clients'].includes(ui.importType))return;
    event.stopImmediatePropagation();const file=input.files?.[0];input.value='';if(!file)return;
    try{showWizard(file,ui.importType,await readFile(file))}catch(error){toast(error.message||'Não foi possível ler a planilha','error')}
  },true);

  document.addEventListener('submit',async event=>{
    if(event.target?.id!=='universalImportForm')return;event.preventDefault();event.stopImmediatePropagation();const submit=event.target.querySelector('[type="submit"]');submit.disabled=true;submit.textContent='Importando…';try{await importMapped(event.target)}catch(error){submit.disabled=false;submit.textContent='Validar e importar';toast(error.message||'Não foi possível importar','error')}
  },true);

  document.addEventListener('click',event=>{
    const action=event.target.closest?.('[data-action]')?.dataset.action;if(action==='download-product-template'){event.preventDefault();event.stopImmediatePropagation();downloadTemplate('products')}if(action==='download-client-template'){event.preventDefault();event.stopImmediatePropagation();downloadTemplate('clients')}
  },true);
})();
