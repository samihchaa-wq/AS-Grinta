-- The leaderboard is a security_invoker view over profiles. The QA-account
-- marker introduced by 20260818001000 is part of the view predicate, so
-- authenticated readers need SELECT on that single column as well.
--
-- Keep the profile surface column-scoped: this does not grant table-wide
-- SELECT and does not grant UPDATE on the internal marker.
grant select (is_test_account)
on table public.profiles
to authenticated;
