# Forens_iQ Operations

## Live topology

`app.intune.dev` terminates TLS in Caddy and proxies to the production Next.js
service on `127.0.0.1:3000`. `api.intune.dev` and `supabase.intune.dev` proxy to
the self-hosted Supabase Kong gateway on `127.0.0.1:8000`.

The application is managed by `forensiq-web.service`. The Supabase stack is
managed by Docker Compose in `/home/deploy/apps/supabase-project`; its
containers use the `unless-stopped` restart policy.

## Deploy the web application

```bash
cd /home/deploy/apps/In.Tellect/web
sudo -u deploy env PATH=/home/deploy/apps/In.Tellect/.tools/node/bin:/usr/local/bin:/usr/bin:/bin npm ci
sudo -u deploy env PATH=/home/deploy/apps/In.Tellect/.tools/node/bin:/usr/local/bin:/usr/bin:/bin npm run build
systemctl restart forensiq-web.service
systemctl --no-pager status forensiq-web.service
curl --fail --silent --show-error https://app.intune.dev/ >/dev/null
```

Never run `next dev` as the live application. Production uses `next build`
followed by `next start` through systemd.

Document processing requires the host packages `poppler-utils`, `tesseract-ocr`,
`antiword`, and `unzip`. The production host has these installed. PDF processing
uses embedded-text extraction first and falls back to 200-DPI Tesseract OCR.

## Logs and health

```bash
journalctl -u forensiq-web.service -f
journalctl -u caddy.service -f
cd /home/deploy/apps/supabase-project && docker compose ps
curl --fail --silent --show-error https://app.intune.dev/ >/dev/null
```

Supabase Auth health requires the configured anonymous API key when requested
through Kong. A 401 at the gateway root without a key is expected.

## Database migrations

Migrations live in `supabase/migrations` and are applied in numeric order. This
self-hosted stack assigns application schema ownership to `supabase_admin`, not
the restricted `postgres` login:

```bash
docker exec -i supabase-db psql -U supabase_admin -d postgres -v ON_ERROR_STOP=1 \
  < /home/deploy/apps/In.Tellect/supabase/migrations/NNNN_description.sql
```

Take a database backup before every migration.

After adding a PostgREST-exposed schema, add it to `PGRST_DB_SCHEMAS` in the
Supabase deployment environment and recreate/restart the `rest` container.

## Evidence storage

The private `evidence` bucket is WORM-protected at the database layer. The web
upload endpoint therefore validates access and size, writes the evidence-file
and SHA-256 metadata first, and performs the irreversible object upload last.
Do not change this ordering or attempt to implement routine object deletion.
Corrections are new evidence-file versions.

## Backup and restore

Create a compressed database backup:

```bash
install -d -m 700 -o deploy -g deploy /home/deploy/backups/forensiq
docker exec supabase-db pg_dump -U postgres -d postgres -Fc \
  > /home/deploy/backups/forensiq/forensiq-$(date -u +%Y%m%dT%H%M%SZ).dump
chmod 600 /home/deploy/backups/forensiq/*.dump
```

Restore into a controlled maintenance environment, never over the live database
without a tested rollback plan:

```bash
docker exec -i supabase-db pg_restore -U supabase_admin -d postgres \
  --clean --if-exists < /path/to/forensiq-backup.dump
```

Local backups protect against migration mistakes but are not disaster recovery.
Replicate encrypted backups off-host and regularly test restoration before a
production launch.

## Secrets

`web/.env.local` and `supabase-project/.env` are mode `0600` and excluded from
Git. The web service loads both at runtime; the existing `OPENAI_API_KEY` is
used with the configured Anthropic-compatible endpoint for Veritas. Never add
either environment file to a commit.
