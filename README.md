# ESSENZA

Plataforma web de catálogo de perfumes, pedidos y mensajería entre compradores y administración.

## Supabase
1. Proyecto independiente: `ldpuldkxqddgltymnyzo`.
2. Ejecuta `supabase-schema.sql` en el SQL Editor para instalar o sincronizar el esquema.
3. Activa la confirmación de correo en Authentication > Providers > Email.
4. Configura códigos OTP de 6 dígitos y usa `{{ .Token }}` en la plantilla de confirmación.
5. El primer usuario que verifique su correo recibe el rol admin. Los siguientes reciben user.
6. El catálogo es visible para usuarios autenticados; las publicaciones solo las puede crear el administrador.
7. Mensajes privados entre usuarios: búsqueda por correo exacto, lista de conversaciones y entrega en tiempo real. RLS limita la lectura y escritura de cada conversación a sus dos participantes. El buscador devuelve únicamente una coincidencia exacta y no expone el directorio completo. Los mensajes quedan guardados en Supabase aunque el destinatario no esté conectado; al volver a abrir ESSENZA podrá leerlos. La alerta en tiempo real aparece cuando tiene la web abierta.
8. Llamadas de voz y videollamadas 1 a 1 usan WebRTC, invitaciones persistidas en `call_sessions` y señalización Realtime privada. El navegador solicita micrófono/cámara al iniciar o aceptar una llamada. Se incluye STUN para conectividad inicial; para máxima compatibilidad entre redes se debe configurar un servicio TURN con credenciales seguras.

## Vercel
- Repositorio: `Auronsistem/Essenza`
- Dominio principal: https://essenza-auronsistem.vercel.app
- Las funciones de servidor están en `api/`.

## Soporte IA
- El asistente incluye respuestas de ayuda ESSENZA y una calculadora local para operaciones aritméticas sencillas.
- La ruta `/api/support` valida la sesión de Supabase antes de procesar preguntas.
- La IA generativa está apagada por defecto para evitar consumo o cargos inesperados.
- Para activarla, un adulto responsable debe revisar primero el uso y posibles costos de AI Gateway; después se puede configurar `ESSENZA_AI_ENABLED=true` en las variables de entorno de Vercel. Se puede usar `AI_GATEWAY_API_KEY` o la autenticación OIDC de Vercel.
- Nunca guardes claves secretas en el navegador ni en GitHub.

## Seguridad
No compartas contraseñas, códigos OTP ni claves secretas. El frontend utiliza únicamente la publishable key de Supabase.
