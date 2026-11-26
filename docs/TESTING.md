# Pruebas

Ejecuta `make check` y `git diff --check` antes de entregar cambios de código. Make comprueba tipos, ejecuta pruebas deterministas y valida plist, scripts y YAML.

Cuando importe verificar el ensamblado de la app, ejecuta `make ARCH="$(uname -m)" CODESIGN_IDENTITY=-`.

- Añade pruebas de regresión deterministas para los fallos reproducibles o documenta por qué no se puede. Usa datos sintéticos y dependencias locales o simuladas. Evita llamar a proveedores de IA reales.
- Micrófono, atajos globales, Accesibilidad, Grabación de pantalla, portapapeles, pegado, actualizador y app firmada requieren prueba manual documentada antes de fusionar. Un borrador puede indicar que falta esa prueba.
- Pide autorización antes de abrir un diálogo de permisos o cambiar permisos del sistema. Indica qué comprobación se ejecutó y qué queda pendiente.
