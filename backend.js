(() => {
  const config = window.FLORALIS_CONFIG || { mode: 'demo' };
  const sessionKey = 'floralis.session.v1';
  let session = null;
  let businessId = null;

  const json = value => value == null ? null : JSON.stringify(value);
  const fromSnake = row => {
    if (!row) return row;
    const out = {};
    for (const [key, value] of Object.entries(row)) out[key.replace(/_([a-z])/g, (_, c) => c.toUpperCase())] = value;
    return out;
  };

  async function request(path, options = {}) {
    if (!config.supabaseUrl || !config.supabasePublishableKey) throw new Error('Supabase não configurado');
    const headers = {
      apikey: config.supabasePublishableKey,
      'Content-Type': 'application/json',
      Prefer: options.prefer || 'return=representation',
      ...(session?.accessToken ? { Authorization: `Bearer ${session.accessToken}` } : {}),
      ...(options.headers || {})
    };
    const response = await fetch(`${config.supabaseUrl}${path}`, { ...options, headers, body: json(options.body) });
    if (!response.ok) {
      const payload = await response.json().catch(() => ({}));
      const error = new Error(payload.message || payload.error_description || payload.hint || `Erro ${response.status}`);
      error.status = response.status;
      error.code = payload.code || '';
      throw error;
    }
    if (response.status === 204) return null;
    return response.json().catch(() => null);
  }

  async function login(email, password) {
    if (config.mode !== 'supabase') {
      const account = (config.demoUsers || []).find(user => user.email.toLowerCase() === email.toLowerCase() && user.password === password);
      if (!account) throw new Error('Correo o contraseña incorrectos');
      session = { accessToken: 'demo', refreshToken: '', userId: account.role === 'admin' ? 'demo-admin' : 'demo-employee', email: account.email, name: account.name, role: account.role, businessId: 'demo-business' };
      businessId = session.businessId;
      localStorage.setItem(sessionKey, JSON.stringify(session));
      return session;
    }
    const auth = await request('/auth/v1/token?grant_type=password', { method: 'POST', body: { email, password } });
    const memberships = await request(`/rest/v1/memberships?select=business_id,role,display_name,active,must_change_password&user_id=eq.${auth.user.id}&active=is.true&limit=1`, { headers: { Authorization: `Bearer ${auth.access_token}` } });
    if (!memberships?.length) throw new Error('El usuario no está vinculado a una empresa activa');
    const member = memberships[0];
    session = { accessToken: auth.access_token, refreshToken: auth.refresh_token, expiresAt: Date.now() + auth.expires_in * 1000, userId: auth.user.id, email: auth.user.email, name: member.display_name || auth.user.email, role: member.role, businessId: member.business_id, mustChangePassword: Boolean(member.must_change_password) };
    businessId = member.business_id;
    localStorage.setItem(sessionKey, JSON.stringify(session));
    return session;
  }

  async function refresh() {
    if (config.mode !== 'supabase' || !session?.refreshToken || Date.now() < (session.expiresAt || 0) - 60000) return session;
    const auth = await request('/auth/v1/token?grant_type=refresh_token', { method: 'POST', body: { refresh_token: session.refreshToken } });
    session = { ...session, accessToken: auth.access_token, refreshToken: auth.refresh_token, expiresAt: Date.now() + auth.expires_in * 1000 };
    localStorage.setItem(sessionKey, JSON.stringify(session));
    return session;
  }

  async function restoreSession() {
    try { session = JSON.parse(localStorage.getItem(sessionKey) || 'null'); } catch { session = null; }
    if (!session) return null;
    businessId = session.businessId;
    try { await refresh(); return session; } catch { logout(); return null; }
  }

  function logout() { session = null; businessId = null; localStorage.removeItem(sessionKey); }
  const isRemote = () => config.mode === 'supabase' && Boolean(config.supabaseUrl && config.supabasePublishableKey);
  const scoped = table => `/rest/v1/${table}?business_id=eq.${businessId}`;

  async function loadWorkspace() {
    if (!isRemote()) return null;
    await refresh();
    const [businesses, products, clients, ledger, memberships, sales, items, cash, settings, generatedDocuments] = await Promise.all([
      request(`/rest/v1/businesses?select=*&id=eq.${businessId}&limit=1`),
      request(`${scoped('products')}&select=*&order=name.asc`),
      request(`${scoped('clients')}&select=*&order=name.asc`),
      request(`${scoped('client_ledger')}&select=*&order=created_at.asc`),
      request(`${scoped('memberships')}&select=*&active=is.true&order=display_name.asc`),
      request(`${scoped('sales')}&select=*&order=created_at.desc&limit=500`),
      request(`${scoped('sale_items')}&select=*`),
      request(`${scoped('cash_movements')}&select=*&order=created_at.desc&limit=1000`),
      request(`${scoped('business_settings')}&select=*&limit=1`),
      request(`${scoped('generated_documents')}&select=*&order=created_at.desc&limit=200`)
    ]);
    const business = businesses?.[0] || {};
    let auditLogs = [];
    if (session?.role === 'admin') {
      try { auditLogs = await loadAuditLogs(); } catch { auditLogs = []; }
    }
    const ledgerByClient = Object.groupBy ? Object.groupBy(ledger, x => x.client_id) : ledger.reduce((a, x) => ((a[x.client_id] ||= []).push(x), a), {});
    const itemsBySale = items.reduce((a, x) => ((a[x.sale_id] ||= []).push(x), a), {});
    return {
      settings: { businessName: business.name || 'FLORALES', legalName: business.legal_name || '', nit: business.tax_id || '', email: business.email || '', phone: business.phone || '', address: business.address || '', postalCode: business.postal_code || '', city: business.city || '', currency: business.currency || 'Bs', baseCurrency: 'BOB', exchangeRates: { BOB: 1, BRL: .75, USD: .14 }, language: settings?.[0]?.theme?.language || 'es', accent: settings?.[0]?.theme?.accent || '#652276', appearance: settings?.[0]?.theme || {}, posLayout: settings?.[0]?.pos_layout || {}, ...(settings?.[0]?.app_config || {}) },
      products: products.map(row => ({ ...fromSnake(row), id: row.id, image: row.image_url || '', minStock: Number(row.min_stock), wholesale: Number(row.wholesale_price), price: Number(row.price), cost: Number(row.cost), stock: Number(row.stock) })),
      clients: clients.map(row => ({ ...fromSnake(row), id: row.id, photo: row.avatar_url || '', balance: Number(row.balance), purchases: Number(row.purchases), total: Number(row.total_purchased), ledger: (ledgerByClient[row.id] || []).map(entry => ({ id: entry.id, date: entry.effective_at || entry.created_at, type: entry.kind, description: entry.description, amount: Number(entry.amount), paymentMethod: entry.payment_method || '', reference: entry.reference || '', saleId: entry.sale_id || null })) })),
      employees: memberships.map(row => ({ id: row.user_id, name: row.display_name, role: row.job_title || (row.role === 'admin' ? 'Administrador' : 'Funcionario'), email: row.email || '', phone: row.phone || '', document: row.document || '', admin: row.role === 'admin', supervisor: row.supervisor, permissions: row.permissions || {}, mustChangePassword: Boolean(row.must_change_password), active: row.active !== false, sales: Number(row.sales_count || 0), total: Number(row.sales_total || 0), ticket: Number(row.average_ticket || 0), goal: Number(row.goal_progress || 0), photo: row.avatar_url || '' })),
      sales: sales.map(row => ({ id: row.sale_number, uuid: row.id, clientSaleId: row.client_sale_id || row.id, clientId: row.client_id || null, date: row.created_at, client: row.client_name || 'Consumidor final', employee: row.seller_name || '', employeeId: row.seller_id, items: (itemsBySale[row.id] || []).reduce((n, x) => n + Number(x.quantity), 0), subtotal: Number(row.subtotal), discountTotal: Number(row.discount), total: Number(row.total), currency: row.currency_code || 'BOB', exchangeRate: Number(row.exchange_rate || 1), displayTotal: Number(row.display_total || row.total), payment: row.payment_method, type: row.kind || 'Venta', notes: row.notes || '', receiptItems: (itemsBySale[row.id] || []).map(item => ({ id: item.product_id, productId: item.product_id, code: item.product_code || '', name: item.product_name, qty: Number(item.quantity), quantity: Number(item.quantity), price: Number(item.unit_price), unitPrice: Number(item.unit_price), discount: Number(item.discount || 0), total: Number(item.total) })), syncStatus: 'synced' })),
      cash: cash.map(row => ({ id: row.id, date: row.created_at, type: row.kind, description: row.description, amount: Number(row.amount), employee: row.employee_name || '' })), closings: [],
      generatedDocuments: (generatedDocuments || []).map(row => ({ id: row.id, clientDocumentId: row.client_document_id, documentNumber: row.document_number, documentType: row.document_type, title: row.title, sourceType: row.source_type, sourceId: row.source_id, periodStart: row.period_start, periodEnd: row.period_end, createdAt: row.created_at, createdBy: row.created_by, snapshot: row.snapshot || {}, syncStatus: 'synced' })),
      auditLogs
    };
  }

  async function upsert(table, record, conflict = 'id') {
    if (!isRemote()) return record;
    const rows = await request(`/rest/v1/${table}?on_conflict=${conflict}`, { method: 'POST', prefer: 'resolution=merge-duplicates,return=representation', body: { ...record, business_id: businessId } });
    return rows?.[0] || record;
  }

  async function saveProduct(product) { return upsert('products', { id: product.id.length === 36 ? product.id : undefined, code: product.code, ean: product.ean, name: product.name, category: product.category, stock: product.stock, min_stock: product.minStock, cost: product.cost, price: product.price, wholesale_price: product.wholesale, unit: product.unit, notes: product.notes, image_url: product.image || null }); }
  async function saveClient(client) { return upsert('clients', { id: client.id.length === 36 ? client.id : undefined, code: client.code, name: client.name, customer_type: client.type, phone: client.phone, document: client.document, city: client.city, birthdate: client.birthdate || null, balance: client.balance, notes: client.notes, avatar_url: client.photo || null }); }
  async function saveBusiness(settings) {
    if (!isRemote()) return settings;
    const rows = await request(`/rest/v1/businesses?id=eq.${businessId}`, { method: 'PATCH', body: { name: settings.businessName, legal_name: settings.legalName, tax_id: settings.nit, email: settings.email || null, phone: settings.phone, address: settings.address || null, postal_code: settings.postalCode || null, city: settings.city, currency: settings.currency || 'Bs' } });
    return rows?.[0] || settings;
  }
  async function saveSettings(settings) { const { appearance, posLayout, language, accent } = settings, appConfig = { options: settings.options || {}, wholesale: Boolean(settings.wholesale), cashClosing: settings.cashClosing || {}, documentTemplates: settings.documentTemplates || {}, watermarkOpacity: settings.watermarkOpacity, logo: settings.logo || '', email: settings.email || '', address: settings.address || '', postalCode: settings.postalCode || '', website: settings.website || '', zone: settings.zone || '', pointOfSale: settings.pointOfSale || '', authorizationCode: settings.authorizationCode || '', baseCurrency: settings.baseCurrency || 'BOB', exchangeRates: settings.exchangeRates || { BOB: 1, BRL: .75, USD: .14 }, saleReceiptTemplate: settings.saleReceiptTemplate === 'modern' ? 'modern' : 'classic-form' }; return upsert('business_settings', { theme: { ...(appearance || { accent }), language: language || 'es' }, pos_layout: posLayout || {}, app_config: appConfig }, 'business_id'); }
  async function updateCredentials({ email, password }) {
    if (!isRemote()) throw new Error('La cuenta de demostración no tiene credenciales remotas');
    const body = {};
    if (email && email.toLowerCase() !== session?.email?.toLowerCase()) body.email = email.trim().toLowerCase();
    if (password) body.password = password;
    if (!Object.keys(body).length) throw new Error('No hay cambios para guardar');
    const user = await request('/auth/v1/user', { method: 'PUT', body });
    if (password) {
      await request('/rest/v1/rpc/complete_password_change', { method: 'POST', body: { p_business_id: businessId } });
      session.mustChangePassword = false;
    }
    if (user?.email) session.email = user.email;
    localStorage.setItem(sessionKey, JSON.stringify(session));
    return user;
  }
  async function manageEmployee(employee) {
    if (!isRemote()) throw new Error('Gestión remota no configurada');
    return request('/functions/v1/manage-user', { method: 'POST', body: { ...employee, businessId } });
  }
  async function recordLedger(clientId, kind, amount, description, options = {}) { if (!isRemote()) return null; return request('/rest/v1/rpc/record_client_movement_v2', { method: 'POST', body: { p_business_id: businessId, p_client_id: clientId, p_kind: kind, p_amount: amount, p_description: description, p_effective_at: options.date || null, p_payment_method: options.paymentMethod || null, p_reference: options.reference || null, p_sale_id: options.saleId || null } }); }
  async function registerSale(payload) { if (!isRemote()) return null; await request('/rest/v1/rpc/register_sale', { method: 'POST', headers: { 'X-Idempotency-Key': payload.clientSaleId || '' }, body: { p_business_id: businessId, p_client_id: payload.clientId || null, p_payment_method: payload.payment, p_items: payload.items, p_notes: payload.notes || null, p_client_sale_id: payload.clientSaleId, p_kind: payload.kind || 'Venta' } }); await request('/rest/v1/rpc/set_sale_currency', { method: 'POST', body: { p_business_id: businessId, p_client_sale_id: payload.clientSaleId, p_currency_code: payload.currency || 'BOB', p_exchange_rate: Number(payload.exchangeRate || 1), p_display_total: Number(payload.displayTotal || 0) } }); const rows = await request(`${scoped('sales')}&client_sale_id=eq.${encodeURIComponent(payload.clientSaleId)}&select=id,sale_number&limit=1`); return rows?.[0] ? { saleId: rows[0].id, saleNumber: rows[0].sale_number } : null; }
  async function saveGeneratedDocument(record) { if (!isRemote()) return { ...record, syncStatus: 'local' }; return request('/rest/v1/rpc/save_generated_document', { method: 'POST', body: { p_business_id: businessId, p_client_document_id: record.clientDocumentId, p_document_type: record.documentType, p_title: record.title, p_source_type: record.sourceType || null, p_source_id: record.sourceId || null, p_period_start: record.periodStart || null, p_period_end: record.periodEnd || null, p_snapshot: record.snapshot || {} } }); }
  async function ensureTrainingProduct() { if (!isRemote() || session?.role !== 'admin') return null; return upsert('products', { code: 'TEST-000000', ean: null, name: 'Producto test', category: 'Tutorial', stock: 100, min_stock: 0, cost: 0, price: 100, wholesale_price: 100, unit: 'Unidad', notes: 'Producto para practicar el flujo del PDV sin afectar los resultados reales.', image_url: './assets/icon-512.png', active: true }, 'business_id,code'); }
  async function addCashMovement(movement) { return upsert('cash_movements', { kind: movement.type, description: movement.description, amount: movement.amount, employee_name: session?.name || '' }); }
  async function recordAudit(entry) { if (!isRemote()) return null; return request('/rest/v1/rpc/record_audit_event', { method: 'POST', body: { p_business_id: businessId, p_module: entry.module || 'Sistema', p_action: entry.action, p_details: entry.details || null, p_level: entry.level || 'info', p_terminal_id: entry.terminalId || null, p_channel: entry.channel || null, p_user_agent: entry.userAgent || null } }); }
  async function loadAuditLogs() { if (!isRemote() || session?.role !== 'admin') return []; const rows = await request(`${scoped('audit_logs')}&select=*&order=created_at.desc&limit=2000`); return (rows || []).map(row => ({ id: row.id, date: row.created_at, userId: row.user_id, user: row.user_name, email: row.user_email, role: row.user_role, module: row.module, action: row.action, details: row.details, level: row.level, terminalId: row.terminal_id, channel: row.channel, userAgent: row.user_agent })); }
  async function registerDevice(device, isLogin = false) {
    const local = { id: device.terminalId, terminalId: device.terminalId, userId: session?.userId, userName: session?.name, userEmail: session?.email, deviceType: device.deviceType, platform: device.platform, browser: device.browser, userAgent: device.userAgent, channel: device.channel, firstSeen: new Date().toISOString(), lastSeen: new Date().toISOString(), lastLogin: new Date().toISOString() };
    if (!isRemote()) return local;
    const result = await request('/rest/v1/rpc/register_connected_device', { method: 'POST', body: { p_business_id: businessId, p_terminal_id: device.terminalId, p_device_type: device.deviceType, p_platform: device.platform, p_browser: device.browser, p_user_agent: device.userAgent, p_channel: device.channel, p_is_login: Boolean(isLogin) } });
    return fromSnake(Array.isArray(result) ? result[0] : result) || local;
  }
  async function loadDevices() { if (!isRemote() || session?.role !== 'admin') return []; const rows = await request(`${scoped('connected_devices')}&select=*&order=last_seen.desc`); return (rows || []).map(fromSnake); }

  window.FloralisBackend = { login, logout, restoreSession, loadWorkspace, saveProduct, saveClient, saveBusiness, saveSettings, updateCredentials, manageEmployee, recordLedger, registerSale, saveGeneratedDocument, ensureTrainingProduct, addCashMovement, recordAudit, loadAuditLogs, registerDevice, loadDevices, isRemote, getSession: () => session, getBusinessId: () => businessId };
})();
