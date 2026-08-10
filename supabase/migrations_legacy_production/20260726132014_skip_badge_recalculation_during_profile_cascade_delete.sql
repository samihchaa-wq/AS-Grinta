create or replace function public.trg_badges_on_roster_change()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if new.profile_id is not null then
    perform public.recalculate_profile_badges(new.profile_id);
  end if;

  if tg_op = 'UPDATE'
     and old.profile_id is not null
     and old.profile_id is distinct from new.profile_id
     and pg_trigger_depth() <= 1 then
    perform public.recalculate_profile_badges(old.profile_id);
  end if;

  return null;
end;
$function$;

comment on function public.trg_badges_on_roster_change() is
  'Recalcule les badges lors des modifications directes de l effectif, mais ignore le profil source pendant une mise a null declenchee en cascade par la suppression du compte.';;
