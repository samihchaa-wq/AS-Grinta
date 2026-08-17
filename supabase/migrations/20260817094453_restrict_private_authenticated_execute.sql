-- AUD-006 / #542
-- Remove direct authenticated EXECUTE from private helpers that are not
-- direct entry points for public SECURITY INVOKER RPCs and are not used by RLS.
-- postgres/service_role grants are intentionally preserved.

revoke execute on function private.adjust_match_live_score(uuid,text,integer,uuid) from authenticated;
revoke execute on function private.composition_snapshot(uuid) from authenticated;
revoke execute on function private.ensure_sport_waitlist(uuid,uuid) from authenticated;
revoke execute on function private.finalize_due_waitlist_turns_for_season(uuid) from authenticated;
revoke execute on function private.get_notifications_paused() from authenticated;
revoke execute on function private.handle_convoked_withdrawal(uuid,uuid,uuid,text) from authenticated;
revoke execute on function private.is_match_coach_or_admin(uuid) from authenticated;
revoke execute on function private.is_moderator() from authenticated;
revoke execute on function private.match_sport_finalization_snapshot(uuid) from authenticated;
revoke execute on function private.require_sports_management_enabled() from authenticated;
revoke execute on function private.resequence_sport_waitlist(uuid,uuid) from authenticated;
revoke execute on function private.resolve_open_sport_season(uuid) from authenticated;
revoke execute on function private.save_match_effectif(uuid,integer,jsonb,text) from authenticated;
revoke execute on function private.save_match_live_lineup(uuid,jsonb,jsonb) from authenticated;
