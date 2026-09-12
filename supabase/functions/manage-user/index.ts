import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const allowedOrigins = (Deno.env.get('ALLOWED_ORIGINS') || '').split(',').map(value => value.trim()).filter(Boolean)

function cors(request: Request) {
  const origin = request.headers.get('origin') || ''
  const allowed = !allowedOrigins.length || allowedOrigins.includes(origin)
  return {
    allowed,
    headers: {
      'Access-Control-Allow-Origin': allowedOrigins.length ? (allowed ? origin : allowedOrigins[0]) : '*',
      'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
      'Access-Control-Allow-Methods': 'POST, OPTIONS',
      'Vary': 'Origin',
    },
  }
}

const permissionsFor = (value: Record<string, unknown> = {}) => ({
  sales: value.sales !== false,
  clients: value.clients !== false,
  stock: Boolean(value.stock),
  cash: Boolean(value.cash),
  reports: Boolean(value.reports),
})

Deno.serve(async request => {
  const access = cors(request)
  if (request.method === 'OPTIONS') return new Response('ok', { status: access.allowed ? 200 : 403, headers: access.headers })
  if (!access.allowed) return new Response(JSON.stringify({ ok: false, error: 'Origen no autorizado' }), { status: 403, headers: { ...access.headers, 'Content-Type': 'application/json' } })

  try {
    const url = Deno.env.get('SUPABASE_URL')!
    const publishable = Deno.env.get('SUPABASE_ANON_KEY')!
    const serviceRole = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const authorization = request.headers.get('Authorization') || ''
    const caller = createClient(url, publishable, { global: { headers: { Authorization: authorization } } })
    const admin = createClient(url, serviceRole, { auth: { autoRefreshToken: false, persistSession: false } })
    const { data: auth, error: authError } = await caller.auth.getUser()
    if (authError || !auth.user) throw new Error('Sesión inválida')

    const payload = await request.json()
    const businessId = String(payload.businessId || '')
    const { data: membership } = await caller.from('memberships').select('role,active').eq('business_id', businessId).eq('user_id', auth.user.id).single()
    if (membership?.role !== 'admin' || !membership.active) throw new Error('Solo un administrador puede gestionar accesos')

    const action = payload.action === 'update' ? 'update' : 'create'
    const email = String(payload.email || '').trim().toLowerCase()
    const password = String(payload.password || '')
    const role = payload.role === 'admin' ? 'admin' : 'employee'
    const name = String(payload.name || '').trim()
    if (!name) throw new Error('El nombre es obligatorio')
    if (!/^\S+@\S+\.\S+$/.test(email)) throw new Error('Correo inválido')
    if (password && password.length < 8) throw new Error('La contraseña debe tener al menos 8 caracteres')

    const memberRecord = {
      role,
      display_name: name,
      email,
      job_title: String(payload.jobTitle || 'Funcionario').trim(),
      phone: String(payload.phone || '').trim() || null,
      document: String(payload.document || '').trim() || null,
      supervisor: Boolean(payload.supervisor),
      permissions: permissionsFor(payload.permissions),
      active: true,
      updated_at: new Date().toISOString(),
    }

    if (action === 'create') {
      if (password.length < 8) throw new Error('Informe una contraseña temporal de al menos 8 caracteres')
      const { data: created, error: createError } = await admin.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
        user_metadata: { name, must_change_password: true },
        app_metadata: { provisioned_by: 'manage-user', business_id: businessId },
      })
      if (createError || !created.user) throw createError || new Error('No fue posible crear el usuario')
      const { error: memberError } = await admin.from('memberships').insert({
        business_id: businessId,
        user_id: created.user.id,
        ...memberRecord,
        must_change_password: true,
      })
      if (memberError) {
        await admin.auth.admin.deleteUser(created.user.id)
        throw memberError
      }
      return new Response(JSON.stringify({ ok: true, userId: created.user.id }), { headers: { ...access.headers, 'Content-Type': 'application/json' } })
    }

    const userId = String(payload.userId || '')
    const { data: target, error: targetError } = await admin.from('memberships').select('role').eq('business_id', businessId).eq('user_id', userId).single()
    if (targetError || !target) throw new Error('Funcionario no encontrado')
    if (userId === auth.user.id && role !== 'admin') throw new Error('El administrador no puede quitar su propio acceso administrativo')
    if (target.role === 'admin' && role !== 'admin') {
      const { count } = await admin.from('memberships').select('user_id', { count: 'exact', head: true }).eq('business_id', businessId).eq('role', 'admin').eq('active', true)
      if ((count || 0) <= 1) throw new Error('La empresa debe conservar al menos un administrador')
    }

    const authUpdate: Record<string, unknown> = { email, email_confirm: true, user_metadata: { name, must_change_password: Boolean(password) } }
    if (password) authUpdate.password = password
    const { error: updateAuthError } = await admin.auth.admin.updateUserById(userId, authUpdate)
    if (updateAuthError) throw updateAuthError
    const { error: updateMemberError } = await admin.from('memberships').update({ ...memberRecord, must_change_password: Boolean(password) }).eq('business_id', businessId).eq('user_id', userId)
    if (updateMemberError) throw updateMemberError
    return new Response(JSON.stringify({ ok: true, userId }), { headers: { ...access.headers, 'Content-Type': 'application/json' } })
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error)
    return new Response(JSON.stringify({ ok: false, error: message }), { status: 400, headers: { ...cors(request).headers, 'Content-Type': 'application/json' } })
  }
})
