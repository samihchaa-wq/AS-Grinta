-- Canonical Realtime signal rows for fresh/local installations only.
-- These rows contain no club, user, player, match or historical data.

insert into public.feature_flag_change_signals(key, revision, updated_at)
select flag.key, 1, flag.updated_at
from private.app_feature_flags flag
on conflict (key) do nothing;

insert into public.shared_data_change_signals(key, revision, updated_at)
values ('global', 1, now())
on conflict (key) do nothing;
