-- Projetos novos podem conceder EXECUTE explicitamente ao papel anon.
-- As RPCs do ERP são exclusivas para sessões autenticadas.
revoke execute on function public.is_member(uuid) from public, anon;
revoke execute on function public.is_admin(uuid) from public, anon;
revoke execute on function public.complete_password_change(uuid) from public, anon;
revoke execute on function public.record_client_movement(uuid,uuid,public.ledger_kind,numeric,text) from public, anon;
revoke execute on function public.record_audit_event(uuid,text,text,text,text,text,text,text) from public, anon;
revoke execute on function public.register_sale(uuid,uuid,text,jsonb,text,text,text) from public, anon;

alter default privileges for role postgres in schema public
  revoke execute on functions from public, anon;
