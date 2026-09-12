-- Fecha de nacimiento del cliente, usada en la lista de clientes y en el crediario.
alter table public.clients
  add column if not exists birthdate date;
