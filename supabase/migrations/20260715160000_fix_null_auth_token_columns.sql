-- Correctif d'un bug GoTrue : certains comptes (créés/importés tôt) avaient des
-- colonnes de jetons à NULL dans auth.users, alors que GoTrue les lit comme des
-- chaînes non-nulles. Résultat : « converting NULL to string is unsupported »,
-- qui cassait le chargement du compte côté GoTrue — donc la suppression, la
-- réinitialisation de mot de passe, etc. renvoyaient une erreur 500.
-- On normalise ces colonnes à '' (chaîne vide), la valeur attendue par GoTrue.
update auth.users set
  confirmation_token = coalesce(confirmation_token, ''),
  recovery_token = coalesce(recovery_token, ''),
  email_change = coalesce(email_change, ''),
  email_change_token_new = coalesce(email_change_token_new, ''),
  email_change_token_current = coalesce(email_change_token_current, ''),
  phone_change = coalesce(phone_change, ''),
  phone_change_token = coalesce(phone_change_token, ''),
  reauthentication_token = coalesce(reauthentication_token, '')
where confirmation_token is null
   or recovery_token is null
   or email_change is null
   or email_change_token_new is null
   or email_change_token_current is null
   or phone_change is null
   or phone_change_token is null
   or reauthentication_token is null;
