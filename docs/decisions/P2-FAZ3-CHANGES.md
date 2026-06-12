# P2 Faz 3 — Init Script (dev-studio-init.sh) — DONE

## Kararlar (kullanıcı onayı: 12 Jun 2026, 16:16)
- Karar 1-A: Tam otomatik resolve (`gh` + `git config`)
- Karar 2-A: Render output gitignored, sadece `.tmpl` commit'lenir
- Karar 3-A: Always-fresh render + `--dry-run` flag
- Karar 4-A: `scripts/dev-studio-init.sh`, manuel çalıştırılır

## Yeni dosyalar

| Dosya | Hedef VM path | Boyut |
|---|---|---|
| `dev-studio-init.sh` | `scripts/dev-studio-init.sh` | ~7.7KB, 240 satır |
| `gitignore-faz3-fragment` | `.gitignore`'a append edilecek | 14 satır |

## Init script özellikleri

1. **Auto-detect REPO_ROOT** — BASH_SOURCE'tan, env override desteği
2. **Preflight** — gh/git/sed varlığı + gh auth status
3. **Resolve** — 4 placeholder otomatik:
   - `REPO_ROOT` → BASH_SOURCE'tan
   - `GITHUB_OWNER` → `gh api user --jq .login`
   - `GITHUB_REPO` → `gh repo view --json name --jq .name`
   - `HUMAN_OWNER_NAME` → `git config user.name`
4. **Render** — repo'daki tüm `*.tmpl` dosyaları
5. **Verify** — render sonrası unresolved placeholder kontrolü
6. **Summary** — özet rapor + sonraki adımlar

## Flag'ler
- `--dry-run` → ne render edileceğini göster, dosya yazma
- `--verbose` → ekstra diagnostic output
- `--help` → built-in help (dosya başından çıkarılır)

## Self-test sonuçları (mock gh ile, /tmp/faz3-test-repo'da)

| Test | Sonuç |
|---|---|
| Bash syntax (`bash -n`) | ✅ OK |
| `--help` çıktısı | ✅ Doğru |
| gh auth eksikse fail | ✅ Exit 1, anlaşılır mesaj |
| Dry-run | ✅ 9 .tmpl listelendi, dosya yazılmadı |
| Gerçek render | ✅ 9 dosya render edildi |
| Render sonrası verify | ✅ "no unresolved placeholders" |
| Örnek output (orchestrator) | ✅ `Test User, @testowner` |
| Örnek output (CODEOWNERS) | ✅ `@testowner` |
| Örnek output (systemd .service) | ✅ Doğru path + URL |
| Idempotency (2x çalıştırma) | ✅ Aynı checksum |

## .gitignore'a eklenecek pattern (9 dosya)
```
CODEOWNERS
.github/ISSUE_TEMPLATE/config.yml
.claude/agents/orchestrator.md
.claude/commands/standup.md
.claude/commands/sprint-start.md
scripts/install/systemd/dev-studio-watcher@.service
scripts/install/systemd/dev-studio-watcher-reload.service
scripts/install/systemd/dev-studio-watcher-reload.path
systemd/dev-studio-health.service
```

## Edge case'ler ve riskler

| Risk | Mitigation |
|---|---|
| `git config user.name` boş | Anlaşılır hata + komut önerisi |
| gh CLI authenticated değil | Preflight'ta fail + `gh auth login` öner |
| Repo henüz push edilmemiş | `gh repo view` fail eder, anlaşılır hata |
| Username'de `\|` karakteri | sed delimiter çakışması — pratikte imkansız |
| Unknown placeholder (örn. `{{FOO}}` typo) | Verify aşaması warn verir, render bozulmaz |

## VM Deploy planı
1. Branch: `chore/p2-faz3-init-script`
2. `scripts/dev-studio-init.sh` ekle
3. `.gitignore`'a 9 satır ekle
4. **GERÇEK VM TESTİ** — `bash scripts/dev-studio-init.sh` çalıştır, 9 dosya render edilsin
5. PR + merge (Faz 2'nin "kısmen bozuk" state'ini de KAPATIYOR)

## Önemli not
Bu merge sonrası repo TEKRAR ÇALIŞIR DURUMA gelecek:
- `CODEOWNERS` render edilir → GitHub kuralı aktif
- `/orchestrator`, `/standup`, `/sprint-start` Claude komutları render edilir
- systemd units render edilir → `install-systemd.sh` çalışır
