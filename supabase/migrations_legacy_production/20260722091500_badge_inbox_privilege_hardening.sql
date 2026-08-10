revoke all on public.badge_inbox_state from authenticated;
revoke all on public.badge_inbox_state from anon;
grant select, insert, update on public.badge_inbox_state to authenticated;;
