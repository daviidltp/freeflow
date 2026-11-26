# Publicación

- `.github/workflows/check.yml` comprueba las PR.
- `.github/workflows/release.yml` publica con etiqueta semver y usa [CHANGELOG.md](../CHANGELOG.md) como fuente de las notas. Consulta la [skill de publicación](../.claude/skills/freeflow-release/SKILL.md).
- `.github/workflows/dev-release.yml` firma la variante de desarrollo desde `main`.
- El mantenimiento ordinario deja intactas las versiones, notas, firma, notarización y workflows de publicación. La autorización para fusionar y publicar está en [CODE_GUIDELINES.md](CODE_GUIDELINES.md).
