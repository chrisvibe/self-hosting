# Restore round-trip tests

Proves that the deployed backups for each service are **actually restorable**, by restoring the
**latest real production backup** into a **throwaway** container/dir and comparing it against the
**live** production data. Designed to be re-run any time the backup/restore scripts change.

## Safety model (no production data is ever written)

- A fresh, **non-destructive** dump is taken via a throwaway backup container attached to the prod
  DB network (`pg_dump`/`pg_dumpall` are read-only on the server).
- The dump is restored into a **throwaway** `bkptest-<svc>-db` container (own empty volume) — never
  a prod volume. Archives (matrix `synapse_data`, nextcloud config) are extracted into a throwaway
  dir.
- Verification reads prod **read-only**: `SELECT` fingerprints over `docker exec`, and prod data
  volumes mounted `:ro` for the tar anchor check.
- Throwaway containers are `docker rm -f`'d at the end.

## What it verifies

- **DB (all services):** runs the deployed `restore_db.sh`; then compares a fingerprint of the
  restored throwaway DB vs live prod: `public-table count | exact total row count | extension set`.
  Tables + extensions must match exactly; row count must fall within the prod before/after bracket
  (live writes between dump and now are legitimate drift, not a restore bug).
- **matrix `synapse_data` tar / nextcloud config tar:** runs the deployed `restore_data.sh` /
  `restore_config.sh` into a throwaway dir, asserts the pre-seeded junk was wiped, that the restored
  tree matches an independent extraction (faithful extract incl. dotfiles), and that an **immutable
  anchor** (matrix signing key / nextcloud `config.php`) is **byte-identical to the live volume**.

## How to run (on elis)

```sh
# from a checkout of the review/ tree, copied to elis:
scp -F ssh/config -r review elis:/tmp/review
ssh -F ssh/config elis 'cd /tmp/review/restore-tests && bash roundtrip.sh all'
# or one service, via its own test folder:
ssh -F ssh/config elis 'cd /tmp/review && bash parvis/test/restore_roundtrip.sh'
```

`roundtrip.sh [parvis|nextcloud|matrix|immich|all]` is the engine; each `<svc>/test/` folder holds
a thin wrapper that calls it for that one service.

## Results — 2026-06-09 (all PASS)

| Service | DB fingerprint (tables\|rows\|exts) | Archive anchor vs live |
|---|---|---|
| parvis | 5\|3\|plpgsql ✅ | — |
| nextcloud | 133\|130861\|plpgsql ✅ | config.php sha256 match ✅ |
| matrix | 168\|58739\|plpgsql ✅ | signing key sha256 match ✅ |
| immich | 60\|395233\|cube,earthdistance,pg_trgm,plpgsql,unaccent,uuid-ossp,vchord,vector ✅ | — |

### Two issues this surfaced (see project notes)

1. **immich backup was not restorable as deployed.** The `immich-backup` sidecar ran
   `postgres:18-alpine`, so its `pg_dumpall` emitted v18 SQL (`LOCALE_PROVIDER`,
   `transaction_timeout`) that the immich **PG14** server rejects on restore (`template1 does not
   exist` cascade). Fix: pin the sidecar image to the server's major version (`postgres:14-alpine`).
   With a v14 client the round-trip passes exactly. (Only `pg_dumpall`/plain-SQL is this
   version-sensitive; the custom-format `pg_restore` services tolerate a minor skew.)
2. **Stale `/scripts` bind mounts.** `nextcloud-backup`, `matrix-backup`, `immich-backup` were
   running with an empty `/scripts` (the host dir's inode was replaced after the containers
   started), so their next cron backup would fail. Fix: recreate/restart those sidecars.
