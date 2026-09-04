begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

-- La règle d'appellation n'existe plus qu'à un seul endroit. Ce test fixe son
-- contrat : c'est lui qui doit être lu et modifié quand la règle change, pas
-- une copie perdue dans une fonction de lecture.

select is(
  public.person_display_name('Titi', 'Stéphane', 'Steph', 'Fernandez'),
  'Titi',
  'Le surnom passe avant tout.'
);

-- Le cas le plus fréquent en production : le client enregistre un surnom non
-- renseigné sous la forme d'une chaîne vide, pas d'un null.
select is(
  public.person_display_name('', 'Stéphane', 'Steph'),
  'Stéphane',
  'Un surnom vide n''écrase pas le prénom du compte.'
);

select is(
  public.person_display_name('   ', 'Stéphane', 'Steph'),
  'Stéphane',
  'Un surnom fait d''espaces n''écrase pas le prénom du compte.'
);

select is(
  public.person_display_name(null::text, null::text, 'Steph'),
  'Steph',
  'Sans compte renseigné, la fiche d''effectif fait foi.'
);

select is(
  public.person_display_name(null::text, null::text, '', 'Fernandez'),
  'Fernandez',
  'Sans prénom nulle part, on retombe sur le nom.'
);

select ok(
  public.person_display_name(null::text, null::text, null::text, null::text) is null,
  'Sans rien à afficher, la fonction renvoie null et laisse l''appelant décider de son repli.'
);

select is(
  public.person_display_name(' Titi ', null::text),
  'Titi',
  'Les espaces autour d''une appellation sont retirés.'
);

-- Le tri suit le nom réellement affiché. Trier sur le surnom brut regroupait
-- en tête, dans un ordre arbitraire, tous les comptes dont le surnom vaut ''.
select is(
  public.person_sort_key('', 'Stéphane', 'Steph'),
  'stéphane',
  'La clé de tri d''un compte sans surnom vaut son prénom, pas une chaîne vide.'
);

select ok(
  public.person_sort_key('', 'Adrien') < public.person_sort_key('', 'Stéphane'),
  'Deux comptes sans surnom se classent par prénom.'
);

select is(
  public.person_sort_key('Titi', 'Stéphane'),
  'titi',
  'La clé de tri d''un compte avec surnom suit le surnom affiché.'
);

-- Un invité n'a pas de compte, donc jamais de surnom.
select is(
  public.guest_display_name('Karim'),
  'Karim',
  'Un invité connu par son seul prénom s''affiche avec ce prénom.'
);

select is(
  public.guest_display_name('Karim', 'Benali'),
  'Karim Benali',
  'Un invité dont on connaît le nom s''affiche en entier.'
);

select is(
  public.guest_display_label('Karim'),
  'Karim (Invité)',
  'L''étiquette « (Invité) » est ajoutée par la fonction partagée.'
);

-- Le contrat de sécurité : les fonctions d'appellation ne sont pas ouvertes
-- aux visiteurs anonymes.
select ok(
  not has_function_privilege(
    'anon',
    'public.person_display_name(text, text, text, text)',
    'execute'
  ),
  'anon ne peut pas exécuter la règle d''appellation.'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.person_display_name(text, text, text, text)',
    'execute'
  ),
  'Un compte connecté peut exécuter la règle d''appellation.'
);

select * from finish();
rollback;
