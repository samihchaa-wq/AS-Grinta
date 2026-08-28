begin;

set local search_path = public, extensions, pg_catalog;
select plan(8);

select is(
  (select threshold from public.badges where code = 'assists_season__3'),
  5,
  'Première passe se débloque à 5 passes décisives sur une saison'
);
select is(
  (select description from public.badges where code = 'assists_season__3'),
  'Délivrer 5 passes décisives au cours d’une même saison.',
  'Première passe affiche le nouveau barème'
);

select is(
  (select threshold from public.badges where code = 'assists_season__5'),
  10,
  'Passeur se débloque à 10 passes décisives sur une saison'
);
select is(
  (select description from public.badges where code = 'assists_season__5'),
  'Délivrer 10 passes décisives au cours d’une même saison.',
  'Passeur affiche le nouveau barème'
);

select is(
  (select threshold from public.badges where code = 'assists_season__10'),
  15,
  'Créateur se débloque à 15 passes décisives sur une saison'
);
select is(
  (select description from public.badges where code = 'assists_season__10'),
  'Délivrer 15 passes décisives au cours d’une même saison.',
  'Créateur affiche le nouveau barème'
);

select is(
  (select threshold from public.badges where code = 'assists_season__15'),
  20,
  'Chef d’orchestre se débloque à 20 passes décisives sur une saison'
);
select is(
  (select description from public.badges where code = 'assists_season__15'),
  'Délivrer 20 passes décisives au cours d’une même saison.',
  'Chef d’orchestre affiche le nouveau barème'
);

select * from finish();
rollback;
