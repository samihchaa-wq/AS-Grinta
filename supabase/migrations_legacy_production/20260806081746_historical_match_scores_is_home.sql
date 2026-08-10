alter table public.historical_match_scores
  add column if not exists is_home boolean not null default true;

comment on column public.historical_match_scores.is_home is
  'true si AS Grinta recevait ; false si le match se jouait à l''extérieur.';
;
