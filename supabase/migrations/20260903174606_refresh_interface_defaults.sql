alter table public.business_settings
  alter column theme set default '{"mode":"light","palette":"blue","accent":"#3b82f6","scale":"medium","font":"inter","shell":"nex"}'::jsonb,
  alter column pos_layout set default '{"dock":"sidebar","density":"comfortable","theme":"touch","mode":"light","palette":"blue","borders":"strong","items":["client","wholesale","delivery","notes","payment"]}'::jsonb;

update public.business_settings
set
  theme = coalesce(theme, '{}'::jsonb) || jsonb_build_object(
    'font', 'inter',
    'palette', 'blue',
    'accent', '#3b82f6'
  ),
  pos_layout = coalesce(pos_layout, '{}'::jsonb) || jsonb_build_object(
    'mode', 'light',
    'palette', 'blue',
    'borders', 'strong'
  ),
  updated_at = now();
