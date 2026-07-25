alter table public.match_composition_publications
  drop constraint if exists match_composition_publications_publication_kind_check;

alter table public.match_composition_publications
  add constraint match_composition_publications_publication_kind_check
  check (publication_kind in ('initial', 'update', 'postmatch'));
