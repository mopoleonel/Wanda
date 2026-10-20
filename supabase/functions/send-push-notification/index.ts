// Edge Function Supabase : envoie une notification push (FCM) à tous les
// appareils enregistrés d'un utilisateur.
//
// Appelée soit directement par le client (cas rares), soit — c'est l'usage
// principal — par un trigger de base de données (voir
// supabase/sql/003_push_triggers.sql) quand une sollicitation ou un
// signalement change d'état.
//
// Secrets requis (supabase secrets set ...) :
//   FIREBASE_SERVICE_ACCOUNT  -> le JSON complet du compte de service Firebase
//                                 (Firebase Console > Paramètres du projet >
//                                 Comptes de service > Générer une nouvelle clé privée)
//   SUPABASE_SERVICE_ROLE_KEY -> déjà disponible automatiquement dans les
//                                 Edge Functions Supabase, pas besoin de la définir.
//
// Déploiement :
//   supabase secrets set FIREBASE_SERVICE_ACCOUNT="$(cat service-account.json)"
//   supabase functions deploy send-push-notification

import { createClient } from 'jsr:@supabase/supabase-js@2';
import { GoogleAuth } from 'npm:google-auth-library@9';

interface NotifyRequest {
  userId: string;
  title: string;
  body: string;
  data?: Record<string, string>;
}

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') {
    return jsonResponse({ error: 'Method not allowed' }, 405);
  }

  // Cette fonction envoie des notifications arbitraires à n'importe quel
  // utilisateur : elle ne doit jamais être appelable publiquement, seulement
  // par les triggers de base de données (qui utilisent la clé service-role).
  const authHeader = req.headers.get('Authorization');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!authHeader || authHeader !== `Bearer ${serviceRoleKey}`) {
    return jsonResponse({ error: 'Non autorisé' }, 401);
  }

  let payload: NotifyRequest;
  try {
    payload = await req.json();
  } catch {
    return jsonResponse({ error: 'Corps de requête invalide' }, 400);
  }

  const { userId, title, body, data } = payload;
  if (!userId || !title || !body) {
    return jsonResponse({ error: 'userId, title et body sont requis' }, 400);
  }

  const serviceAccountRaw = Deno.env.get('FIREBASE_SERVICE_ACCOUNT');
  if (!serviceAccountRaw) {
    return jsonResponse(
      { error: 'Configuration serveur incomplète (FIREBASE_SERVICE_ACCOUNT)' },
      500,
    );
  }
  const serviceAccount = JSON.parse(serviceAccountRaw);
  const projectId = serviceAccount.project_id;

  // Tokens de l'utilisateur, via un client service-role (contourne RLS —
  // légitime ici puisque c'est un contexte serveur de confiance).
  const supabaseAdmin = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
  );
  const { data: tokens, error } = await supabaseAdmin
    .from('device_tokens')
    .select('fcm_token')
    .eq('user_id', userId);

  if (error) {
    return jsonResponse({ error: error.message }, 500);
  }
  if (!tokens || tokens.length === 0) {
    return jsonResponse({ sent: 0, message: 'Aucun appareil enregistré' }, 200);
  }

  const auth = new GoogleAuth({
    credentials: serviceAccount,
    scopes: ['https://www.googleapis.com/auth/firebase.messaging'],
  });
  const client = await auth.getClient();
  const accessToken = (await client.getAccessToken()).token;

  let sent = 0;
  const errors: string[] = [];

  for (const { fcm_token } of tokens) {
    const res = await fetch(
      `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${accessToken}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          message: {
            token: fcm_token,
            notification: { title, body },
            data: data ?? {},
          },
        }),
      },
    );
    if (res.ok) {
      sent++;
    } else {
      errors.push(await res.text());
    }
  }

  return jsonResponse({ sent, total: tokens.length, errors }, 200);
});

function jsonResponse(data: unknown, status: number): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}
