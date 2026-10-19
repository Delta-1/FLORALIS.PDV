// The confirmation code is an extra operator check, never an authentication method.
// This helper can only act for a verified, active administrator in the same company.
export async function resetPassword({ payload, businessId, membership, auth, caller, admin }) {
  if (!auth?.user?.id || membership?.role !== 'admin' || !membership.active) throw new Error('Solo un administrador conectado puede restablecer contraseñas')
  if (String(payload.supervisorCode || '') !== '1234') throw new Error('Código del supervisor incorrecto')
  const userId = String(payload.userId || '')
  const password = String(payload.password || '')
  if (!userId) throw new Error('Seleccione el usuario')
  if (password.length < 8 || password.length > 128) throw new Error('La contraseña debe tener entre 8 y 128 caracteres')
  const { data: target, error: targetError } = await admin.from('memberships').select('user_id,active').eq('business_id', businessId).eq('user_id', userId).single()
  if (targetError || !target?.active) throw new Error('Usuario activo no encontrado en esta empresa')
  const { error: updateError } = await admin.auth.admin.updateUserById(userId, { password, user_metadata: { must_change_password: true } })
  if (updateError) throw updateError
  const { error: memberError } = await admin.from('memberships').update({ must_change_password: true, updated_at: new Date().toISOString() }).eq('business_id', businessId).eq('user_id', userId)
  if (memberError) throw memberError
  const { error: auditError } = await caller.rpc('record_audit_event', {
    p_business_id: businessId, p_module: 'Accesos', p_action: 'Contraseña temporal restablecida',
    p_details: `Usuario ${userId}. Cambio obligatorio en el próximo acceso.`, p_level: 'info',
    p_terminal_id: null, p_channel: 'web', p_user_agent: null,
  })
  return { ok: true, userId, mustChangePassword: true, auditSaved: !auditError }
}
