// Edge Function Supabase : analyse IA des photos d'une demande de service
// ménager (état du logement, volume de linge, de poubelles, nuisibles).
//
// Même principe qu'analyze-signalement :
// * la clé GROQ_API_KEY ne quitte jamais le serveur (secrets Supabase) ;
// * seul un utilisateur connecté peut appeler la fonction (JWT vérifié).
//
// Spécificités :
// * l'app envoie les CHEMINS des photos déjà déposées dans le bucket privé
//   « demandes » ; la fonction les télécharge avec le JWT de l'utilisateur
//   (il ne peut donc faire analyser que ses propres photos) — les pièces
//   d'identité (bucket « identites ») ne sont jamais lues ici ;
// * le résultat est enregistré dans la table analyses_ia avec la clé
//   service_role (l'app ne peut pas le falsifier), puis renvoyé ;
// * l'IA ne bloque jamais une réservation : en cas d'échec (réseau, quota,
//   réponse illisible), la fonction répond 200 avec `resultat: null` et le
//   prix est calculé sur le questionnaire seul.
//
// Déploiement :
//   supabase secrets set GROQ_API_KEY=gsk_xxx
//   supabase secrets set GROQ_VISION_MODEL=qwen/qwen3.8-27b   (facultatif)
//   supabase functions deploy analyze-demande-menage

import { createClient } from 'jsr:@supabase/supabase-js@2';
import { encodeBase64 } from 'jsr:@std/encoding@1/base64';

// Modèle de vision Groq (llama-4-scout a été arrêté le 17/07/2026).
// Remplaçable sans redéployer : secret GROQ_VISION_MODEL.
const MODELE_PAR_DEFAUT = 'qwen/qwen3.8-27b';
const MAX_PHOTOS = 3; // limite Groq par requête
const MAX_OCTETS = 4 * 1024 * 1024;
const DELAI_MS = 25000;

type Service = 'menage' | 'linge' | 'dechets' | 'nuisibles';

interface Requete {
  service: Service;
  reponses: Record<string, unknown>;
  photos: string[];
}

const CONSIGNES: Record<Service, string> = {
  menage: `Service : ménage à domicile. Estime l'ÉTAT du logement visible :
"normal" (entretien courant), "sale" (pas nettoyé depuis un moment) ou
"tres_sale" (après travaux, déménagement, longue absence). Donne-le dans
estimation.niveau. quantite_min / quantite_max : nombre de pièces visibles
si tu peux l'estimer, sinon null.`,
  linge: `Service : lessive et repassage. Estime la QUANTITÉ de linge en
PANIERS standards (environ 5 kg chacun) : estimation.quantite_min et
estimation.quantite_max. estimation.niveau : null.`,
  dechets: `Service : ramassage des poubelles à domicile. Estime le NOMBRE
DE SACS de 50 litres visibles : estimation.quantite_min et
estimation.quantite_max. estimation.niveau : null.`,
  nuisibles: `Service : désinsectisation / dératisation. Identifie le
nuisible (estimation.nuisible parmi "cafards", "moustiques", "punaises",
"rongeurs", "fourmis", ou null) et le NIVEAU d'infestation visible
(estimation.niveau : "faible", "moyenne" ou "forte"). quantite_min /
quantite_max : null.`,
};

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') {
    return json({ error: 'Method not allowed' }, 405);
  }

  // Authentification : utilisateur connecté obligatoire (quota Groq).
  const authHeader = req.headers.get('Authorization');
  if (!authHeader) return json({ error: 'Non authentifié' }, 401);
  const url = Deno.env.get('SUPABASE_URL') ?? '';
  const userClient = createClient(url, Deno.env.get('SUPABASE_ANON_KEY') ?? '', {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: userData, error: userError } = await userClient.auth.getUser();
  const user = userData?.user;
  if (userError || !user) return json({ error: 'Non authentifié' }, 401);

  let body: Requete;
  try {
    body = await req.json();
  } catch {
    return json({ error: 'Corps de requête invalide' }, 400);
  }
  const { service, reponses, photos } = body;
  if (!(service in CONSIGNES) || !Array.isArray(photos) ||
      photos.length < 1 || photos.length > MAX_PHOTOS) {
    return json({ error: 'service et 1 à 3 photos sont requis' }, 400);
  }
  // Uniquement ses propres photos de demande.
  if (photos.some((p) => typeof p !== 'string' || !p.startsWith(`${user.id}/`))) {
    return json({ error: 'Photo non autorisée' }, 403);
  }

  const admin = createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '');
  const modele = Deno.env.get('GROQ_VISION_MODEL') || MODELE_PAR_DEFAUT;

  // Enregistre l'analyse (réussie ou non) et répond toujours 200 : l'IA ne
  // bloque jamais la réservation.
  const terminer = async (resultat: unknown, erreur: string | null) => {
    const { data } = await admin.from('analyses_ia').insert({
      citoyen_id: user.id, service, reponses: reponses ?? {}, photos,
      resultat, erreur, modele,
    }).select('id').single();
    return json({ analyse_id: data?.id ?? null, resultat, erreur }, 200);
  };

  const groqApiKey = Deno.env.get('GROQ_API_KEY');
  if (!groqApiKey) return terminer(null, 'configuration');

  // Photos depuis le bucket privé « demandes », avec les droits de
  // l'utilisateur.
  const images: string[] = [];
  for (const chemin of photos) {
    const { data, error } = await userClient.storage.from('demandes').download(chemin);
    if (error || !data) return terminer(null, 'photo_introuvable');
    if (data.size > MAX_OCTETS) return terminer(null, 'photo_trop_lourde');
    images.push(encodeBase64(new Uint8Array(await data.arrayBuffer())));
  }

  const consigne = `Tu vérifies les photos d'une demande de service à domicile
au Cameroun, pour fixer un prix juste.
${CONSIGNES[service]}

Réponses du client au questionnaire : ${JSON.stringify(reponses ?? {})}.

1. Vérifie que les photos montrent bien ce qui est demandé (sinon
   photos_conformes = false et explique dans raison_non_conforme).
2. Estime ce qui est demandé ci-dessus.
3. Compare avec les réponses du client et liste chaque incohérence en une
   phrase courte en français (ex. « Environ 4 sacs visibles, 2 déclarés »).
4. confiance : de 0 à 1.

Réponds UNIQUEMENT en JSON, exactement ce format :
{"photos_conformes": true, "raison_non_conforme": null,
 "estimation": {"quantite_min": null, "quantite_max": null,
                "niveau": null, "nuisible": null},
 "confiance": 0.0, "incoherences": []}`;

  const controleur = new AbortController();
  const minuterie = setTimeout(() => controleur.abort(), DELAI_MS);
  try {
    const reponse = await fetch('https://api.groq.com/openai/v1/chat/completions', {
      method: 'POST',
      signal: controleur.signal,
      headers: {
        Authorization: `Bearer ${groqApiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: modele,
        temperature: 0.2,
        response_format: { type: 'json_object' },
        messages: [{
          role: 'user',
          content: [
            { type: 'text', text: consigne },
            ...images.map((b64) => ({
              type: 'image_url',
              image_url: { url: `data:image/jpeg;base64,${b64}` },
            })),
          ],
        }],
      }),
    });
    if (!reponse.ok) {
      return terminer(null, `groq_${reponse.status}`);
    }
    const decode = await reponse.json();
    const contenu = decode.choices?.[0]?.message?.content;
    if (!contenu) return terminer(null, 'reponse_vide');
    return terminer(normaliser(JSON.parse(contenu)), null);
  } catch {
    return terminer(null, controleur.signal.aborted ? 'delai_depasse' : 'erreur_ia');
  } finally {
    clearTimeout(minuterie);
  }
});

// Garde uniquement des champs attendus, aux bons types (JSON strict).
function normaliser(brut: Record<string, unknown>) {
  const e = (brut.estimation ?? {}) as Record<string, unknown>;
  const entier = (v: unknown) =>
    typeof v === 'number' && Number.isFinite(v) && v >= 0 ? Math.round(v) : null;
  const texte = (v: unknown, permis: string[]) =>
    typeof v === 'string' && permis.includes(v) ? v : null;
  const confiance = typeof brut.confiance === 'number'
    ? Math.min(1, Math.max(0, brut.confiance)) : 0;
  return {
    photos_conformes: brut.photos_conformes !== false,
    raison_non_conforme: typeof brut.raison_non_conforme === 'string'
      ? brut.raison_non_conforme.slice(0, 300) : null,
    estimation: {
      quantite_min: entier(e.quantite_min),
      quantite_max: entier(e.quantite_max),
      niveau: texte(e.niveau,
        ['normal', 'sale', 'tres_sale', 'faible', 'moyenne', 'forte']),
      nuisible: texte(e.nuisible,
        ['cafards', 'moustiques', 'punaises', 'rongeurs', 'fourmis']),
    },
    confiance,
    incoherences: Array.isArray(brut.incoherences)
      ? brut.incoherences.filter((x) => typeof x === 'string')
          .slice(0, 5).map((x) => (x as string).slice(0, 200))
      : [],
  };
}

function json(data: unknown, status: number): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}
