const SUPABASE_URL = "https://ldpuldkxqddgltymnyzo.supabase.co";
const SUPABASE_PUBLISHABLE_KEY = "sb_publishable_b00djy5Gg358ITYlJpUvuA_kwr_-dTJ";

module.exports = async function handler(req, res) {
  res.setHeader("Cache-Control", "no-store");
  res.setHeader("X-Content-Type-Options", "nosniff");

  if (req.method !== "POST") {
    res.setHeader("Allow", "POST");
    return res.status(405).json({ error: "Método no permitido." });
  }

  const origin = req.headers.origin;
  const allowedOrigins = new Set([
    "https://essenza-auronsistem.vercel.app",
    "https://essenza-gold.vercel.app",
    "https://essenza-git-main-auronsistem.vercel.app"
  ]);
  if (origin && !allowedOrigins.has(origin)) {
    return res.status(403).json({ error: "Origen no permitido." });
  }

  const bearer = String(req.headers.authorization || "").match(/^Bearer\\s+(.+)$/i);
  if (!bearer) return res.status(401).json({ error: "Inicia sesión para usar el soporte." });

  try {
    const authCheck = await fetch(SUPABASE_URL + "/auth/v1/user", {
      headers: {
        apikey: SUPABASE_PUBLISHABLE_KEY,
        Authorization: "Bearer " + bearer[1]
      }
    });
    if (!authCheck.ok) {
      return res.status(401).json({ error: "Tu sesión expiró. Vuelve a iniciar sesión." });
    }

    // Se mantiene apagado por defecto para evitar consumo o cargos inesperados.
    if (process.env.ESSENZA_AI_ENABLED !== "true") {
      return res.status(503).json({
        code: "AI_DISABLED",
        error: "La IA avanzada aún no está activada."
      });
    }

    let payload = req.body;
    if (typeof payload === "string") payload = JSON.parse(payload);
    const input = Array.isArray(payload?.messages) ? payload.messages.slice(-10) : [];
    const messages = input
      .filter(item => item && (item.role === "user" || item.role === "assistant") && typeof item.content === "string")
      .map(item => ({ role: item.role, content: item.content.trim().slice(0, 1200) }))
      .filter(item => item.content);

    if (!messages.length || messages[messages.length - 1].role !== "user") {
      return res.status(400).json({ error: "Escribe una pregunta para continuar." });
    }

    const systemPrompt = `Eres el asistente oficial de ESSENZA, una plataforma de catálogo y solicitudes de perfumes. Responde siempre en español claro, amable y breve.
Conocimiento confirmado de ESSENZA:
- Las cuentas se registran con correo y contraseña y se verifican por correo con un código de seis dígitos.
- La primera cuenta cuyo correo queda verificado recibe el rol de administrador. Las cuentas siguientes son compradores.
- El administrador puede registrar perfumes indicando nombre, precio, stock y descripción.
- Los compradores pueden consultar el catálogo y solicitar una cantidad de unidades disponible.
- En “Mis pedidos”, el comprador ve el estado: solicitud enviada, en preparación o pedido listo.
- En la bandeja de solicitudes, el administrador puede pulsar “Iniciar” y después “Terminar”.
- En “Mensajes”, el comprador conversa de forma privada con el administrador.
- El botón “¿Olvidaste tu contraseña?” permite iniciar la recuperación de acceso.
Reglas:
- Puedes responder preguntas generales y ayudar con matemáticas, operaciones y explicaciones escolares.
- No inventes precios, existencias, fechas de entrega, políticas de envío ni datos de un pedido que no se te hayan proporcionado.
- No solicites contraseñas, códigos de verificación ni datos bancarios.
- Si una consulta requiere revisar la cuenta o un pedido, explica dónde verlo en ESSENZA.
- No afirmes que has realizado acciones dentro de la plataforma si no tienes acceso a ellas.
- Si no sabes algo, dilo con honestidad.`;

    // Prioriza el mismo proveedor configurable que SPLASH AI.
    const baseUrl = process.env.AUREON_AI_BASE_URL?.trim();
    const providerKey = process.env.AUREON_AI_API_KEY?.trim();
    const providerModel = process.env.AUREON_AI_MODEL?.trim();

    let endpoint;
    let authorization;
    let model;

    if (baseUrl || providerKey || providerModel) {
      if (!baseUrl || !providerKey || !providerModel) {
        return res.status(503).json({
          code: "AI_PROVIDER_NOT_CONFIGURED",
          error: "La conexión compartida de IA no está configurada por completo."
        });
      }
      try {
        const parsed = new URL(baseUrl);
        if (parsed.protocol !== "https:") throw new Error("HTTPS_REQUIRED");
        while (parsed.pathname.endsWith("/")) parsed.pathname = parsed.pathname.slice(0, -1);
        if (!parsed.pathname.endsWith("/chat/completions")) parsed.pathname += "/chat/completions";
        endpoint = parsed.toString();
      } catch {
        return res.status(503).json({
          code: "AI_PROVIDER_URL_INVALID",
          error: "La dirección segura del proveedor de IA no es válida."
        });
      }
      authorization = providerKey;
      model = providerModel;
    } else {
      // Compatibilidad con la configuración anterior de Vercel AI Gateway.
      const gatewayToken = process.env.AI_GATEWAY_API_KEY || req.headers["x-vercel-oidc-token"];
      if (!gatewayToken) {
        return res.status(503).json({
          code: "AI_AUTH_MISSING",
          error: "Falta configurar la autenticación del servicio de IA."
        });
      }
      endpoint = "https://ai-gateway.vercel.sh/v1/chat/completions";
      authorization = gatewayToken;
      model = "openai/gpt-4.1-mini";
    }

    const aiResponse = await fetch(endpoint, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: "Bearer " + authorization
      },
      signal: AbortSignal.timeout(45000),
      body: JSON.stringify({
        model,
        messages: [{ role: "system", content: systemPrompt }, ...messages],
        max_tokens: 600,
        temperature: 0.55,
        stream: false
      })
    });

    if (!aiResponse.ok) {
      if (aiResponse.status === 429) {
        return res.status(429).json({ error: "La IA alcanzó el límite temporal del proveedor. Inténtalo más tarde." });
      }
      return res.status(502).json({ error: "El servicio de IA no respondió correctamente. Inténtalo más tarde." });
    }
    const result = await aiResponse.json();
    const rawReply = result?.choices?.[0]?.message?.content;
    const reply = typeof rawReply === "string"
      ? rawReply.trim()
      : Array.isArray(rawReply)
        ? rawReply.map(part => typeof part?.text === "string" ? part.text : "").join("").trim()
        : "";
    if (!reply) {
      return res.status(502).json({ error: "El servicio de IA devolvió una respuesta vacía." });
    }
    return res.status(200).json({ reply, model });
  } catch (error) {
    return res.status(500).json({ error: "No se pudo procesar la consulta de soporte." });
  }
};
