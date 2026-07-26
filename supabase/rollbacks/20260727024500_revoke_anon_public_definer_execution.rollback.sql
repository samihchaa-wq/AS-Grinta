begin;

-- Rollback volontairement non ré-exposant : les anciens droits anonymes ne sont
-- pas restaurés automatiquement, car cela rouvrirait une surface privilégiée
-- sans connaître l’intention métier fonction par fonction. Une réouverture doit
-- faire l’objet d’une migration explicite, ciblée et testée.

commit;
