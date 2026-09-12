import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

Deno.serve(async request => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: cors })
  try {
    const url = Deno.env.get('SUPABASE_URL')!
    const publishable = Deno.env.get('SUPABASE_ANON_KEY')!
    const serviceRole = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const authorization = request.headers.get('Authorization') || ''
    const caller = createClient(url, publishable, { global: { headers: { Authorization: authorization } } })
    const admin = createClient(url, serviceRole)
    const { data: auth, error: authError } = await caller.auth.getUser()
    if (authError || !auth.user) throw new Error('Sesión inválida')
    const payload = await request.json()
    const { data: membership } = await caller.from('memberships').select('business_id,role').eq('user_id', auth.user.id).eq('business_id', payload.businessId).eq('active', true).single()
    if (membership?.role !== 'admin') throw new Error('Solo un administrador puede crear accesos')
    const { data: invited, error: inviteError } = await admin.auth.admin.inviteUserByEmail(payload.email, { data: { name: payload.name } })
    if (inviteError || !invited.user) throw inviteError || new Error('No fue posible invitar')
    const { error: memberError } = await admin.from('memberships').insert({ business_id: payload.businessId, user_id: invited.user.id, role: payload.role === 'admin' ? 'admin' : 'employee', display_name: payload.name, email: payload.email, job_title: payload.jobTitle || 'Funcionario', supervisor: Boolean(payload.supervisor) })
    if (memberError) throw memberError
    return new Response(JSON.stringify({ ok: true, userId: invited.user.id }), { headers: { ...cors, 'Content-Type': 'application/json' } })
  } catch (error) {
    return new Response(JSON.stringify({ ok: false, error: error.message }), { status: 400, headers: { ...cors, 'Content-Type': 'application/json' } })
  }
})
