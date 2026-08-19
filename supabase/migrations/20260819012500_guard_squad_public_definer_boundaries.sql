-- AUD-006: guards must be explicit at every authenticated SECURITY DEFINER public boundary.

create or replace function public.admin_create_postmatch_composition(p_match_id uuid,p_formation_code text,p_entries jsonb,p_allow_squad_size_exception boolean default false,p_reason text default null)
returns jsonb language plpgsql security definer set search_path='' as $f$
begin if not private.is_admin() then raise exception 'Active administrator role required' using errcode='42501'; end if; return private.create_postmatch_composition(p_match_id,p_formation_code,p_entries,p_allow_squad_size_exception,p_reason); end;$f$;

create or replace function public.admin_get_match_composition(p_match_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $f$
begin if not private.is_admin() then raise exception 'Active administrator role required' using errcode='42501'; end if; return private.get_admin_match_composition(p_match_id); end;$f$;

create or replace function public.admin_get_match_convocations(p_match_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $f$
begin if not private.is_admin() then raise exception 'Active administrator role required' using errcode='42501'; end if; return private.enrich_match_convocation_history(private.get_match_convocations(p_match_id)); end;$f$;

create or replace function public.admin_get_sport_waitlist(p_season_id uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $f$
begin if not private.is_admin() then raise exception 'Active administrator role required' using errcode='42501'; end if; return private.enrich_sport_waitlist_history(private.get_sport_waitlist(p_season_id)); end;$f$;

create or replace function public.admin_publish_match_composition(p_match_id uuid,p_allow_squad_size_exception boolean default false,p_reason text default null)
returns jsonb language plpgsql security definer set search_path='' as $f$
declare v_status text; v_kickoff_at timestamptz; begin if not private.is_admin() then raise exception 'Active administrator role required' using errcode='42501'; end if; select m.status,m.kickoff_at into v_status,v_kickoff_at from public.matches m where m.id=p_match_id; if not found then raise exception 'Match not found' using errcode='P0002'; end if; if v_status='a_venir' and v_kickoff_at is not null and now()>=v_kickoff_at-interval '15 minutes' then raise exception 'La composition est figée depuis l’ouverture du Live.' using errcode='22023'; end if; return private.publish_match_composition(p_match_id,p_allow_squad_size_exception,p_reason); end;$f$;

create or replace function public.admin_publish_match_convocations(p_match_id uuid,p_reason text default null)
returns jsonb language plpgsql security definer set search_path='' as $f$
begin if not private.is_admin() then raise exception 'Active administrator role required' using errcode='42501'; end if; return private.publish_match_convocations(p_match_id,p_reason); end;$f$;

create or replace function public.admin_publish_match_effectif(p_match_id uuid,p_squad_size_limit integer,p_decisions jsonb,p_reason text default null)
returns jsonb language plpgsql security definer set search_path='' as $f$
declare v_status text; v_kickoff_at timestamptz; begin if not private.is_admin() then raise exception 'Active administrator role required' using errcode='42501'; end if; select m.status,m.kickoff_at into v_status,v_kickoff_at from public.matches m where m.id=p_match_id; if not found then raise exception 'Match not found' using errcode='P0002'; end if; if v_status='a_venir' and v_kickoff_at is not null and now()>=v_kickoff_at-interval '15 minutes' then raise exception 'L’effectif est figé depuis l’ouverture du Live.' using errcode='22023'; end if; return private.publish_match_effectif(p_match_id,p_squad_size_limit,p_decisions,p_reason); end;$f$;

create or replace function public.admin_reorder_sport_waitlist(p_season_id uuid,p_ordered_player_ids uuid[],p_reason text default null)
returns jsonb language plpgsql security definer set search_path='' as $f$
begin if not private.is_admin() then raise exception 'Active administrator role required' using errcode='42501'; end if; return private.enrich_sport_waitlist_history(private.reorder_sport_waitlist(p_season_id,p_ordered_player_ids,p_reason)); end;$f$;

create or replace function public.admin_save_match_composition(p_match_id uuid,p_formation_code text,p_entries jsonb,p_allow_squad_size_exception boolean,p_reason text,p_expected_version integer)
returns jsonb language plpgsql security definer set search_path='' as $f$
declare v_status text; v_kickoff_at timestamptz; begin if not private.is_admin() then raise exception 'Active administrator role required' using errcode='42501'; end if; select m.status,m.kickoff_at into v_status,v_kickoff_at from public.matches m where m.id=p_match_id; if not found then raise exception 'Match not found' using errcode='P0002'; end if; if v_status='a_venir' and v_kickoff_at is not null and now()>=v_kickoff_at-interval '15 minutes' then raise exception 'La composition est figée depuis l’ouverture du Live.' using errcode='22023'; end if; perform private.lock_match_composition_version(p_match_id,p_expected_version); perform private.save_match_composition(p_match_id,p_formation_code,p_entries,p_allow_squad_size_exception,p_reason); return private.publish_match_composition(p_match_id,p_allow_squad_size_exception,p_reason); end;$f$;

create or replace function public.admin_save_match_composition(p_match_id uuid,p_formation_code text,p_entries jsonb,p_allow_squad_size_exception boolean default false,p_reason text default null)
returns jsonb language plpgsql security definer set search_path='' as $f$
begin if not private.is_admin() then raise exception 'Active administrator role required' using errcode='42501'; end if; return public.admin_save_match_composition(p_match_id,p_formation_code,p_entries,p_allow_squad_size_exception,p_reason,null::integer); end;$f$;

create or replace function public.admin_save_match_effectif(p_match_id uuid,p_squad_size_limit integer,p_decisions jsonb,p_reason text default null)
returns jsonb language plpgsql security definer set search_path='' as $f$
begin if not private.is_admin() then raise exception 'Active administrator role required' using errcode='42501'; end if; return private.publish_match_effectif(p_match_id,p_squad_size_limit,p_decisions,p_reason); end;$f$;

create or replace function public.admin_set_match_convocation(p_match_id uuid,p_season_player_id uuid,p_status text,p_turn_should_consume boolean,p_reason text default null)
returns jsonb language plpgsql security definer set search_path='' as $f$
begin if not private.is_admin() then raise exception 'Active administrator role required' using errcode='42501'; end if; return private.set_match_convocation(p_match_id,p_season_player_id,p_status,p_turn_should_consume,p_reason); end;$f$;

create or replace function public.admin_update_postmatch_composition(p_match_id uuid,p_formation_code text,p_entries jsonb,p_allow_squad_size_exception boolean default false,p_reason text default null)
returns jsonb language plpgsql security definer set search_path='' as $f$
begin if not private.is_admin() then raise exception 'Active administrator role required' using errcode='42501'; end if; return private.update_postmatch_composition(p_match_id,p_formation_code,p_entries,p_allow_squad_size_exception,p_reason); end;$f$;

create or replace function public.get_published_match_composition(p_match_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $f$
begin if not private.is_active_profile() then raise exception 'Active profile required' using errcode='42501'; end if; return private.get_published_match_composition(p_match_id); end;$f$;

create or replace function public.get_sport_waitlist(p_season_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $f$
begin if not private.is_active_profile() then raise exception 'Active profile required' using errcode='42501'; end if; return private.enrich_sport_waitlist_history(private.get_sport_waitlist_readonly(p_season_id)); end;$f$;
