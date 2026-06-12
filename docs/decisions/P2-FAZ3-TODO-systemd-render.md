# Faz 3 — Init Script TODO (Faz 1'den devredilen iş)

## Bağlam
Faz 1'de Karar 3-C verildi: systemd dosyaları statik content gerektirdiği için
auto-detect uygulanamaz. Bunlar `.tmpl` placeholder'lı olarak commit edilecek,
**Faz 3'te `dev-studio-init.sh` render edecek.**

## Render edilecek dosyalar (Faz 1'de `.tmpl` yapıldı)

| Source (commit edilen) | Target (init script render eder) |
|---|---|
| `scripts/install/systemd/dev-studio-watcher@.service.tmpl` | `scripts/install/systemd/dev-studio-watcher@.service` |
| `scripts/install/systemd/dev-studio-watcher-reload.service.tmpl` | `scripts/install/systemd/dev-studio-watcher-reload.service` |
| `scripts/install/systemd/dev-studio-watcher-reload.path.tmpl` | `scripts/install/systemd/dev-studio-watcher-reload.path` |
| `systemd/dev-studio-health.service.tmpl` | `systemd/dev-studio-health.service` |

## Placeholder'lar
- `{{REPO_ROOT}}` — `$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)` ile çözülecek
- `{{GITHUB_OWNER}}` — `gh api user --jq .login` (Faz 2'de gelecek)
- `{{GITHUB_REPO}}` — `gh repo view --json name --jq .name` (Faz 2'de gelecek)

## .gitignore'a Faz 3'te eklenecek (render output)
```
scripts/install/systemd/*.service
scripts/install/systemd/*.path
systemd/dev-studio-health.service
!**/*.tmpl
```

## Init script pseudo-kod
```bash
render_systemd_templates() {
  local repo_root="$1"
  local gh_owner="$2"
  local gh_repo="$3"

  for tmpl in $(find . -name "*.tmpl"); do
    target="${tmpl%.tmpl}"
    sed -e "s|{{REPO_ROOT}}|${repo_root}|g" \
        -e "s|{{GITHUB_OWNER}}|${gh_owner}|g" \
        -e "s|{{GITHUB_REPO}}|${gh_repo}|g" \
        "$tmpl" > "$target"
  done
}
```

## ÖNEMLİ: Init script idempotent olmalı
Aynı repo'da `dev-studio-init.sh` iki kez çalıştırılırsa hata vermemeli,
sadece mevcut render'ı güncellemeli.
