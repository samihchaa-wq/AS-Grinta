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

create or replace function private.prepare_profile_for_hard_deletion(p_profile_id uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_system_actor constant uuid := '00000000-0000-0000-0000-000000000001'::uuid;
begin
  if p_profile_id is null then
    raise exception 'Profile id is required' using errcode = '22023';
  end if;
  if p_profile_id = v_system_actor then
    raise exception 'Technical profile cannot be deleted' using errcode = '22023';
  end if;
  if not exists (select 1 from public.profiles where id = v_system_actor) then
    raise exception 'Technical replacement profile is missing' using errcode = '55000';
  end if;

  delete from public.sport_availability_notification_events where profile_id = p_profile_id;
  delete from public.match_sport_motm_votes where voter_profile_id = p_profile_id;

  update private.sport_admin_audit_log set actor_profile_id = v_system_actor where actor_profile_id = p_profile_id;
  update public.guest_players set created_by = v_system_actor where created_by = p_profile_id;
  update public.guest_players set updated_by = v_system_actor where updated_by = p_profile_id;
  update public.match_composition_publications set published_by = v_system_actor where published_by = p_profile_id;
  update public.match_compositions set last_modified_by = v_system_actor where last_modified_by = p_profile_id;
  update public.match_compositions set published_by = null where published_by = p_profile_id;
  update public.match_sport_finalization_versions set created_by = v_system_actor where created_by = p_profile_id;
  update public.match_sport_finalizations set validated_by = v_system_actor where validated_by = p_profile_id;
  update public.match_sport_finalizations set corrected_by = null where corrected_by = p_profile_id;
  update public.match_sport_workflows set created_by = v_system_actor where created_by = p_profile_id;
  update public.match_sport_workflows set updated_by = v_system_actor where updated_by = p_profile_id;
  update public.sport_waitlist_entries set created_by = v_system_actor where created_by = p_profile_id;
  update public.sport_waitlist_entries set updated_by = v_system_actor where updated_by = p_profile_id;
end;
$function$;

revoke all on function private.prepare_profile_for_hard_deletion(uuid) from public, anon, authenticated;
grant execute on function private.prepare_profile_for_hard_deletion(uuid) to service_role;