begin;

create or replace function private.reset_internal_match_composition_on_first_effectif_publish()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if coalesce(old.convocation_version, 0) <> 0
     or coalesce(new.convocation_version, 0) <= 0 then
    return new;
  end if;

  if exists (
    select 1
    from public.matches match
    where match.id = new.match_id
      and match.match_type = 'entre_nous'
  ) then
    delete from public.match_internal_composition_entries
    where match_id = new.match_id;
  end if;

  return new;
end;
$function$;

revoke all on function private.reset_internal_match_composition_on_first_effectif_publish()
  from public, anon, authenticated;

drop trigger if exists trg_reset_internal_composition_on_first_effectif_publish
  on public.match_sport_workflows;

create trigger trg_reset_internal_composition_on_first_effectif_publish
after update of convocation_version
on public.match_sport_workflows
for each row
when (old.convocation_version is distinct from new.convocation_version)
execute function private.reset_internal_match_composition_on_first_effectif_publish();

comment on function private.reset_internal_match_composition_on_first_effectif_publish() is
  'Au premier enregistrement de l''effectif d''un match entre nous, repart de deux équipes vides : tous les joueurs commencent dans Non affectés.';

commit;
