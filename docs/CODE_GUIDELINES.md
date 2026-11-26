# Reglas de trabajo

- Busca antes de editar con `rg` o `rg --files` y conserva el trabajo ajeno.
- Trabaja en rama con cambios acotados y una PR en borrador. En mantenimiento autorizado puedes subir o actualizar esa rama y corregir observaciones de CI o de revisión.
- Subir directamente a `main` está prohibido. Fusionar, etiquetar, publicar o mover la etiqueta `dev` requiere autorización explícita.
- Usa la biblioteca estándar y las dependencias existentes cuando cubran el caso.
- Make detecta las fuentes de producción. Declara las fuentes de pruebas en `TEST_PRODUCTION_SOURCES`.
- En la PR, describe el impacto en privacidad, permisos, migración y publicación. Señala cambios en peticiones a proveedores, prompts, almacenamiento, portapapeles, Accesibilidad, verificación de actualizaciones, firma y workflows.
- En revisión, señala rutas que registren, guarden, exporten o transmitan contenido o credenciales sin autorización ni ocultación. Si cambia la coincidencia exacta de atajos, recuperación del portapapeles, validación de actualizaciones, firma o permisos, exige una prueba de regresión y una ruta segura documentada.
- El código de los workflows ejecutado desde `main` puede acceder a los secretos de firma y notarización de las tareas de publicación.
