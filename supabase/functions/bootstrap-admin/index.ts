import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

Deno.serve(async request => {
  if (request.method !== 'POST') return new Response(JSON.stringify({ ok: false, error: 'Método no permitido' }), { status: 405, headers: { 'Content-Type': 'application/json' } })
  try {
    const setupKey = Deno.env.get('FLORALIS_SETUP_KEY') || ''
    if (!setupKey || request.headers.get('x-setup-key') !== setupKey) throw new Error('Clave de instalación inválida')
    const url = Deno.env.get('SUPABASE_URL')!
    const serviceRole = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const email = (Deno.env.get('FLORALIS_ADMIN_EMAIL') || 'admin@floralis.local').trim().toLowerCase()
    const password = Deno.env.get('FLORALIS_ADMIN_PASSWORD') || ''
    if (password.length < 12) throw new Error('FLORALIS_ADMIN_PASSWORD debe tener al menos 12 caracteres')
    const admin = createClient(url, serviceRole, { auth: { autoRefreshToken: false, persistSession: false } })
    const { count } = await admin.from('memberships').select('user_id', { count: 'exact', head: true })
    if ((count || 0) > 0) throw new Error('La instalación inicial ya fue realizada')

    const { data: created, error: createError } = await admin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: { name: 'Administrador FLORALIS', must_change_password: true },
      app_metadata: { provisioned_by: 'bootstrap-admin' },
    })
    if (createError || !created.user) throw createError || new Error('No fue posible crear el administrador')

    const { data: business, error: businessError } = await admin.from('businesses').insert({
      name: Deno.env.get('FLORALIS_BUSINESS_NAME') || 'FLORALIS Flores e Presentes',
      legal_name: Deno.env.get('FLORALIS_LEGAL_NAME') || 'FLORALIS Flores e Presentes',
      currency: 'Bs',
    }).select('id').single()
    if (businessError || !business) {
      await admin.auth.admin.deleteUser(created.user.id)
      throw businessError || new Error('No fue posible crear la empresa')
    }

    const { error: membershipError } = await admin.from('memberships').insert({
      business_id: business.id,
      user_id: created.user.id,
      role: 'admin',
      display_name: 'Administrador FLORALIS',
      email,
      job_title: 'Administrador',
      supervisor: true,
      must_change_password: true,
      permissions: { sales: true, clients: true, stock: true, cash: true, reports: true },
    })
    if (membershipError) {
      await admin.from('businesses').delete().eq('id', business.id)
      await admin.auth.admin.deleteUser(created.user.id)
      throw membershipError
    }
    const { error: settingsError } = await admin.from('business_settings').insert({ business_id: business.id })
    if (settingsError) {
      await admin.from('businesses').delete().eq('id', business.id)
      await admin.auth.admin.deleteUser(created.user.id)
      throw settingsError
    }

    const { error: productsError } = await admin.from('products').insert([
      { business_id: business.id, code: 'BUQ-001', name: 'Buquê Romântico', category: 'Buquês', unit: 'Unidade', notes: 'Buquê artesanal com flores selecionadas.', stock: 12, min_stock: 3, cost: 90, price: 180, wholesale_price: 165 },
      { business_id: business.id, code: 'ROS-012', name: 'Ramalhete de Rosas', category: 'Flores', unit: 'Unidade', notes: 'Ramalhete com doze rosas.', stock: 18, min_stock: 4, cost: 110, price: 220, wholesale_price: 200 },
      { business_id: business.id, code: 'PRE-001', name: 'Caixa Presente Floral', category: 'Presentes', unit: 'Unidade', notes: 'Arranjo floral em caixa para presente.', stock: 8, min_stock: 2, cost: 75, price: 155, wholesale_price: 140 },
      { business_id: business.id, code: 'TEST-000000', name: 'Produto de teste', category: 'Tutorial', unit: 'Unidade', notes: 'Produto para praticar o fluxo do PDV sem afetar resultados reais.', stock: 100, min_stock: 0, cost: 0, price: 100, wholesale_price: 100 },
    ])
    if (productsError) {
      await admin.from('businesses').delete().eq('id', business.id)
      await admin.auth.admin.deleteUser(created.user.id)
      throw productsError
    }

    return new Response(JSON.stringify({ ok: true, businessId: business.id, userId: created.user.id, email }), { headers: { 'Content-Type': 'application/json' } })
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error)
    return new Response(JSON.stringify({ ok: false, error: message }), { status: 400, headers: { 'Content-Type': 'application/json' } })
  }
})
