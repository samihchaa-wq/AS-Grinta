-- Remise a zero des visuels de badges.
--
-- Les 55 badges du catalogue portaient une image personnalisee affichee dans
-- la partie haute de l'embleme. Le projet repart d'une page blanche sur ce
-- sujet : on efface la reference (badges.image_url) pour que l'embleme
-- retombe sur l'emoji du badge, deja renseigne pour chaque badge.
--
-- Aucun badge n'est supprime, aucune attribution n'est touchee, et la
-- couleur, le titre, la description et le bareme restent inchanges. Le
-- moderateur pourra reposer une image quand il le voudra via l'editeur
-- existant.

begin;

-- Le declencheur trg_cleanup_replaced_badge_image supprime, pour chaque ligne
-- remise a NULL, le fichier correspondant du bucket badge-images.
update public.badges
set image_url = null
where image_url is not null;

-- Filet de securite : le declencheur ignore les URL qu'il ne sait pas
-- rattacher au bucket et n'echoue jamais bruyamment. On vide donc ce qui
-- resterait, le bucket n'ayant plus aucune image legitime a conserver.
do $cleanup$
begin
  perform set_config('storage.allow_delete_query', 'true', true);
  delete from storage.objects
  where bucket_id = 'badge-images';
exception when others then
  raise warning 'purge du bucket badge-images ignoree : %', sqlerrm;
end;
$cleanup$;

commit;
