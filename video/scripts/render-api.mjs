// Échanges avec la fonction Supabase « lineup-presentations ».
//
// Aucune dépendance : ce module sert aussi à vérifier s'il y a du travail
// avant même d'installer le moteur de rendu. Le workflow prouve son identité
// avec le jeton OIDC que GitHub lui remet (permission « id-token: write ») :
// aucun secret Supabase n'est stocké chez GitHub.
//
// Le dépôt est public, donc les journaux du workflow aussi : rien de ce qui
// est écrit ici ne doit contenir un prénom, une photo ou une adresse signée.
import {readFileSync} from 'node:fs';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const OIDC_AUDIENCE = 'as-grinta-lineup-presentations';

const supabaseUrl = () => {
  const fromEnv = process.env.SUPABASE_URL?.trim();
  if (fromEnv) return fromEnv.replace(/\/+$/, '');
  // Même source que l'application : les valeurs publiques de production.
  const config = JSON.parse(readFileSync(join(root, 'config', 'production.json'), 'utf8'));
  return String(config.SUPABASE_URL).replace(/\/+$/, '');
};

const githubOidcToken = async () => {
  const url = process.env.ACTIONS_ID_TOKEN_REQUEST_URL;
  const token = process.env.ACTIONS_ID_TOKEN_REQUEST_TOKEN;
  if (!url || !token) {
    throw new Error('Jeton OIDC indisponible : à lancer depuis le workflow GitHub de rendu.');
  }
  const response = await fetch(`${url}&audience=${encodeURIComponent(OIDC_AUDIENCE)}`, {
    headers: {Authorization: `Bearer ${token}`},
  });
  if (!response.ok) throw new Error(`Jeton OIDC refusé (${response.status})`);
  const body = await response.json();
  return body.value;
};

/** Appelle une action de la fonction ; un jeton neuf à chaque appel. */
export const callRenderApi = async (action, payload = {}) => {
  const response = await fetch(`${supabaseUrl()}/functions/v1/lineup-presentations`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${await githubOidcToken()}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({action, ...payload}),
  });
  if (!response.ok) {
    throw new Error(`Action « ${action} » refusée (${response.status})`);
  }
  return response.json();
};
