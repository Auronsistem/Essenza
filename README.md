# ESSENZA
Sitio estático inicial de gestión de perfumes.

## Configuración requerida
1. Crear un proyecto Supabase independiente para ESSENZA. No reutilizar la base de AUREON.
2. Ejecutar `supabase-schema.sql` en SQL Editor.
3. Activar confirmación de correo en Authentication > Providers > Email.
4. En Auth settings, configurar OTP de 6 dígitos si se desea; el formulario admite códigos de hasta 8 dígitos.
5. Copiar Project URL y Publishable key (o anon heredada) en el archivo index.html, sustituyendo los dos valores `PEGA_AQUI...`.
6. En Vercel conectar este repositorio. El proyecto se llamará essenza y su URL prevista será https://essenza.vercel.app si el subdominio está disponible.

La primera cuenta registrada en el proyecto de Auth recibe el rol admin mediante un trigger de base de datos; las siguientes reciben rol user. Nunca colocar la service_role/secret key en el navegador.
