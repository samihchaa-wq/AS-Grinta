alter table public.matches alter column match_time drop not null;

update public.matches
set match_time = null
where status = 'archive'
  and match_time = time '15:00:00';
