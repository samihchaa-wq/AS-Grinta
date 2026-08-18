-- AUD-006 follow-up: expose composition, convocation and waitlist capabilities only through
-- public RPC boundaries. Keep implementation functions private to the database owner.

-- Admin / staff public RPC boundaries.
alter function public.admin_create_postmatch_composition(uuid,text,jsonb,boolean,text) security definer;
alter function public.admin_finalize_match_waitlist_turns(uuid) security definer;
alter function public.admin_get_match_composition(uuid) security definer;
alter function public.admin_get_match_convocations(uuid) security definer;
alter function public.admin_get_sport_waitlist(uuid) security definer;
alter function public.admin_publish_match_composition(uuid,boolean,text) security definer;
alter function public.admin_publish_match_convocations(uuid,text) security definer;
alter function public.admin_publish_match_effectif(uuid,integer,jsonb,text) security definer;
alter function public.admin_reorder_sport_waitlist(uuid,uuid[],text) security definer;
alter function public.admin_save_match_composition(uuid,text,jsonb,boolean,text) security definer;
alter function public.admin_save_match_composition(uuid,text,jsonb,boolean,text,integer) security definer;
alter function public.admin_save_match_effectif(uuid,integer,jsonb,text) security definer;
alter function public.admin_set_match_convocation(uuid,uuid,text,boolean,text) security definer;
alter function public.admin_update_postmatch_composition(uuid,text,jsonb,boolean,text) security definer;

-- The recompute implementation is intentionally an internal primitive and has no admin
-- gate of its own, so make the authorization boundary explicit in the public wrapper.
create or replace function public.admin_recompute_match_convocations(
  p_match_id uuid,
  p_reset_overrides boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  return private.recompute_match_convocations_internal(p_match_id, p_reset_overrides);
end;
$function$;

-- Player-readable public boundaries. Authorization remains in the private implementations.
alter function public.get_published_match_composition(uuid) security definer;
alter function public.get_sport_waitlist(uuid) security definer;

-- Remove authenticated access to implementation functions and enrichment helpers.
revoke execute on function private.create_postmatch_composition(uuid,text,jsonb,boolean,text)
  from public, anon, authenticated;
revoke execute on function private.finalize_match_waitlist_turns_internal(uuid,boolean)
  from public, anon, authenticated;
revoke execute on function private.get_admin_match_composition(uuid)
  from public, anon, authenticated;
revoke execute on function private.get_match_convocations(uuid)
  from public, anon, authenticated;
revoke execute on function private.enrich_match_convocation_history(jsonb)
  from public, anon, authenticated;
revoke execute on function private.get_sport_waitlist(uuid)
  from public, anon, authenticated;
revoke execute on function private.enrich_sport_waitlist_history(jsonb)
  from public, anon, authenticated;
revoke execute on function private.publish_match_composition(uuid,boolean,text)
  from public, anon, authenticated;
revoke execute on function private.publish_match_convocations(uuid,text)
  from public, anon, authenticated;
revoke execute on function private.publish_match_effectif(uuid,integer,jsonb,text)
  from public, anon, authenticated;
revoke execute on function private.recompute_match_convocations_internal(uuid,boolean)
  from public, anon, authenticated;
revoke execute on function private.reorder_sport_waitlist(uuid,uuid[],text)
  from public, anon, authenticated;
revoke execute on function private.lock_match_composition_version(uuid,integer)
  from public, anon, authenticated;
revoke execute on function private.save_match_composition(uuid,text,jsonb,boolean,text)
  from public, anon, authenticated;
revoke execute on function private.set_match_convocation(uuid,uuid,text,boolean,text)
  from public, anon, authenticated;
revoke execute on function private.update_postmatch_composition(uuid,text,jsonb,boolean,text)
  from public, anon, authenticated;
revoke execute on function private.get_published_match_composition(uuid)
  from public, anon, authenticated;
revoke execute on function private.get_sport_waitlist_readonly(uuid)
  from public, anon, authenticated;

-- Keep the intended public API available only to authenticated clients and service_role.
revoke execute on function public.admin_create_postmatch_composition(uuid,text,jsonb,boolean,text) from public, anon;
revoke execute on function public.admin_finalize_match_waitlist_turns(uuid) from public, anon;
revoke execute on function public.admin_get_match_composition(uuid) from public, anon;
revoke execute on function public.admin_get_match_convocations(uuid) from public, anon;
revoke execute on function public.admin_get_sport_waitlist(uuid) from public, anon;
revoke execute on function public.admin_publish_match_composition(uuid,boolean,text) from public, anon;
revoke execute on function public.admin_publish_match_convocations(uuid,text) from public, anon;
revoke execute on function public.admin_publish_match_effectif(uuid,integer,jsonb,text) from public, anon;
revoke execute on function public.admin_recompute_match_convocations(uuid,boolean) from public, anon;
revoke execute on function public.admin_reorder_sport_waitlist(uuid,uuid[],text) from public, anon;
revoke execute on function public.admin_save_match_composition(uuid,text,jsonb,boolean,text) from public, anon;
revoke execute on function public.admin_save_match_composition(uuid,text,jsonb,boolean,text,integer) from public, anon;
revoke execute on function public.admin_save_match_effectif(uuid,integer,jsonb,text) from public, anon;
revoke execute on function public.admin_set_match_convocation(uuid,uuid,text,boolean,text) from public, anon;
revoke execute on function public.admin_update_postmatch_composition(uuid,text,jsonb,boolean,text) from public, anon;
revoke execute on function public.get_published_match_composition(uuid) from public, anon;
revoke execute on function public.get_sport_waitlist(uuid) from public, anon;

grant execute on function public.admin_create_postmatch_composition(uuid,text,jsonb,boolean,text) to authenticated, service_role;
grant execute on function public.admin_finalize_match_waitlist_turns(uuid) to authenticated, service_role;
grant execute on function public.admin_get_match_composition(uuid) to authenticated, service_role;
grant execute on function public.admin_get_match_convocations(uuid) to authenticated, service_role;
grant execute on function public.admin_get_sport_waitlist(uuid) to authenticated, service_role;
grant execute on function public.admin_publish_match_composition(uuid,boolean,text) to authenticated, service_role;
grant execute on function public.admin_publish_match_convocations(uuid,text) to authenticated, service_role;
grant execute on function public.admin_publish_match_effectif(uuid,integer,jsonb,text) to authenticated, service_role;
grant execute on function public.admin_recompute_match_convocations(uuid,boolean) to authenticated, service_role;
grant execute on function public.admin_reorder_sport_waitlist(uuid,uuid[],text) to authenticated, service_role;
grant execute on function public.admin_save_match_composition(uuid,text,jsonb,boolean,text) to authenticated, service_role;
grant execute on function public.admin_save_match_composition(uuid,text,jsonb,boolean,text,integer) to authenticated, service_role;
grant execute on function public.admin_save_match_effectif(uuid,integer,jsonb,text) to authenticated, service_role;
grant execute on function public.admin_set_match_convocation(uuid,uuid,text,boolean,text) to authenticated, service_role;
grant execute on function public.admin_update_postmatch_composition(uuid,text,jsonb,boolean,text) to authenticated, service_role;
grant execute on function public.get_published_match_composition(uuid) to authenticated, service_role;
grant execute on function public.get_sport_waitlist(uuid) to authenticated, service_role;
