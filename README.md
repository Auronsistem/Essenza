# ESSENZA

Plataforma web de catálogo de perfumes, pedidos y mensajería entre compradores y administración.

## Supabase
1. Proyecto independiente: `ldpuldkxqddgltymnyzo`.
2. Ejecuta `supabase-schema.sql` en el SQL Editor para instalar o sincronizar el esquema.
3. Activa la confirmación de correo en Authentication > Providers > Email.
4. Configura códigos OTP de 6 dígitos y usa `{{ .Token }}` en la plantilla de confirmación.
5. El primer usuario que verifique su correo recibe el rol admin. Los siguientes reciben user.
6. El catálogo es visible para usuarios autenticados; las publicaciones solo las puede crear el administrador.
7. Mensajes son privados entre cada comprador y el administrador; están protegidos con RLS y Realtime.

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
