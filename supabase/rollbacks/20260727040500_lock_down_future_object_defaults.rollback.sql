begin;

-- Retour arrière volontairement sans effet. Restaurer EXECUTE à PUBLIC ou des
-- privilèges anon par défaut réintroduirait la vulnérabilité corrigée. En cas de
-- besoin, accorder explicitement le privilège requis à une fonction ou relation
-- déterminée plutôt que de modifier ces valeurs globales.

commit;
