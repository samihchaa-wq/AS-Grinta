-- Bug 32 : typographie incoherente.
--
-- Le code Dart utilise 197 apostrophes typographiques contre 15 droites, mais
-- la base fait l'inverse : 30 des 56 descriptions de badges utilisaient
-- l'apostrophe droite contre une seule la typographique. L'armoire a badges
-- etait l'ecran le plus incoherent de l'application.
--
-- Seules les apostrophes situees entre deux lettres sont converties : ce sont
-- des apostrophes francaises (« d'une », « l'effectif »), jamais des
-- guillemets ni des symboles de mesure.

begin;

update public.badges
set name = regexp_replace(name, '([[:alpha:]])''([[:alpha:]])', '\1’\2', 'g')
where name ~ '[[:alpha:]]''[[:alpha:]]';

update public.badges
set description = regexp_replace(
      description, '([[:alpha:]])''([[:alpha:]])', '\1’\2', 'g'
    )
where description ~ '[[:alpha:]]''[[:alpha:]]';

commit;
