# Seed Checksums

Deterministic checksums for verifying seed integrity across runs and architectures.

## Small Seed (n_users=1000, n_posts=10000, n_likes_total=40000)

| Table | Checksum Sum | Rows |
|-------|--------------|------|
| users | 591578021177384881311 | 1000 |
| posts | 5743868484899149596353 | 10000 |
| likes | 23082984434147688443726 | 40000 |

## Full Seed (n_users=50000, n_posts=500000, n_likes_total=2000000)

| Table | Checksum Sum | Rows |
|-------|--------------|------|
| users | 28940049546933938605670 | 50000 |
| posts | 287944207565051385610002 | 500000 |
| likes | 1154082181330134313540272 | 2000000 |

## Verification

Run `./run.sh db-check` to verify checksums against expected values.

## Notes

- Checksums are order-independent sum of per-row 60-bit hashes
- Per-row hash: `md5(column1|column2|...|extract(epoch from created_at))` using first 15 hex chars (60 bits)
- Timestamps rendered via `extract(epoch from created_at)` for timezone independence
- Identical checksums confirm deterministic seed across runs and architectures