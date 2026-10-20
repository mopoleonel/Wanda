// Edge Function Supabase : analyse IA d'une photo de signalement via Groq.
//
// La clé GROQ_API_KEY ne vit plus jamais dans l'app mobile — elle est lue
// ici côté serveur depuis les secrets du projet Supabase, injoignable par
// rétro-ingénierie de l'APK/IPA.
//
// Déploiement (depuis la racine du projet) :
//   supabase login
//   supabase link --project-ref <ton-project-ref>
//   supabase secrets set GROQ_API_KEY=gsk_xxx
//   supabase functions deploy analyze-signalement
//
// Le client appelle cette fonction via `supabase.functions.invoke(...)`,
// qui transmet automatiquement le JWT de l'utilisateur connecté — vérifié
// ci-dessous pour éviter tout appel anonyme qui consommerait le quota Groq.

import { createClient } from 'jsr:@supabase/supabase-js@2';

const GROQ_MODEL = 'meta-llama/llama-4-scout-17b-16e-instruct';

interface AnalyzeRequest {
  category: string;
  imageBase64: string;
}

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') {
    return jsonResponse({ error: 'Method not allowed' }, 405);
  }

  // Authentification : seul un utilisateur connecté (citoyen) peut
  // déclencher une analyse — évite l'abus anonyme du quota Groq.
  const authHeader = req.headers.get('Authorization');
  if (!authHeader) {
    return jsonResponse({ error: 'Non authentifié' }, 401);
  }
  const supabaseClient = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_ANON_KEY') ?? '',
    { global: { headers: { Authorization: authHeader } } },
  );
  const { data: userData, error: userError } = await supabaseClient.auth.getUser();
  if (userError || !userData?.user) {
    return jsonResponse({ error: 'Non authentifié' }, 401);
  }

  let body: AnalyzeRequest;
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: 'Corps de requête invalide' }, 400);
  }

  const { category, imageBase64 } = body;
  if (!category || !imageBase64) {
    return jsonResponse({ error: 'category et imageBase64 sont requis' }, 400);
  }

  const groqApiKey = Deno.env.get('GROQ_API_KEY');
  if (!groqApiKey) {
    return jsonResponse({ error: "Configuration serveur incomplète (GROQ_API_KEY)" }, 500);
  }

  try {
    const groqResponse = await fetch('https://api.groq.com/openai/v1/chat/completions', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${groqApiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: GROQ_MODEL,
        messages: [
          {
            role: 'user',
            content: [
              {
                type: 'text',
                text: `Analyse cette image de signalement citoyen.
                  Catégorie choisie : ${category}.
                  Instructions :
                  1. Vérifie si l'image est une photo réelle de terrain.
                  2. Si 'Autre (IA)', identifie précisément le problème.
                  3. Réponds uniquement en JSON : {"valid": bool, "detected_type": "string", "reason": "string"}`,
              },
              {
                type: 'image_url',
                image_url: { url: `data:image/jpeg;base64,${imageBase64}` },
              },
            ],
          },
        ],
        response_format: { type: 'json_object' },
      }),
    });

    if (!groqResponse.ok) {
      const errText = await groqResponse.text();
      return jsonResponse({ error: `Erreur API Groq: ${errText}` }, 502);
    }

    const decoded = await groqResponse.json();
    const content = decoded.choices?.[0]?.message?.content;
    if (!content) {
      return jsonResponse({ error: 'Réponse IA vide' }, 502);
    }

    const aiData = JSON.parse(content);
    return jsonResponse(aiData, 200);
  } catch (e) {
    return jsonResponse({ error: `Erreur inattendue: ${e}` }, 500);
  }
});

function jsonResponse(data: unknown, status: number): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}
