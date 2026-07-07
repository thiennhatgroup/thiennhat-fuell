# Code review — Batch 9: Tịnh téc / Kiểm kê

Review target: commit `2ca2794 "ok"` (fixed point `64183f1`).
Files: `public/index.html`, `supabase/migrations/0025_stock_period_record.sql`.
Two-axis review (Standards + Spec). Nothing here is fixed yet — this is a backlog to improve later.

## Priority fixes (worth doing regardless of axis)

- [x] **Server-side biên bản check (Spec hole).** ~~`rpc_stock_period_record` inserts `p_bien_ban_path`
  with no check that it is non-null when `p_kind='kiem_ke'`.~~ **FIXED** — migration
  `0026_kiemke_bienban_required.sql` create-or-replaces the RPC with a guard:
  `if p_kind='kiem_ke' and nullif(trim(coalesce(p_bien_ban_path,'')),'') is null then raise…`.
  Allocation math copied verbatim from 0025 (untouched). Needs `supabase db push` to take effect.
- [x] **Orphaned upload on RPC failure (Storage leak).** ~~`recordPeriod` uploads the biên bản to the
  `chung-tu` bucket FIRST, then calls the RPC. If the RPC throws, the image is left in the bucket with
  no cleanup.~~ **FIXED** — `recordPeriod` now sets `bienBanPath` only after a successful upload and, in
  the catch, `sb.storage.from('chung-tu').remove([bienBanPath])` removes the orphan (mirrors the pump
  flow). Verified: RPC-fail → orphan removed (exact path); RPC-success → no removal.

## Standards axis

Documented AGENTS.md standards: **0 hard violations.** Compliant on: new-migration-only (no editing
old migrations), all writes via `SECURITY DEFINER` RPC + `require_permission()` + `set search_path`,
no storage buckets/policies created in migrations (helper-only edit), no emojis.

Baseline smells (judgement calls):

- [ ] **Duplicated Code / Shotgun Surgery (strongest).** The tinh/allocation block in
  `rpc_stock_period_record` (0025) is copy-pasted from `rpc_stock_period_close` in
  `0012_stock_period.sql`: same `v_sum_am/v_sum_duong/v_max_veh` declares, same
  `entry_type='bom' and tt.kind='xuat'` aggregation, same proportional "phân bổ theo tỉ lệ lít" loop,
  same largest-vehicle rounding fix-up. A change to allocation rules now needs edits in two functions.
  → Extract a shared `stock_period_allocate(period_id, tank_id, start, close)`.
- [ ] **Duplicated Code within the RPC.** The ledger aggregation query appears twice inside
  `rpc_stock_period_record` — once for `v_total`, again verbatim (with `group by`) in the alloc loop.
- [ ] **Data Clumps / Primitive Obsession (minor).** `p_kind text` with sentinel strings
  `'tinh_tec'`/`'kiem_ke'` validated ad-hoc; the FE mirrors this with the `P` field-map and repeated
  `kind==='tinh_tec'` switches in `recordPeriod`. A domain enum would centralize it.
- [ ] **Speculative Generality (very minor).** `renderPeriodList` keeps the `status==='Mo'` branch
  though the new flow only writes `'DaChot'`. Justified by legacy `Mo` periods possibly existing —
  probably leave as-is.

## Spec axis

Feature delivered correctly: base-oil reset relocated to this screen with distinct fields
(Tồn gốc vs Tồn thực tế), real actual-volume inputs replacing `prompt()`, Tịnh with both start+close
dates, Kiểm kê person/timestamp capture, removal of the "Tồn cuối = …" paragraph. RPC signature matches
the FE call; upload path/permission (`chungtu_can_upload` widened to `adjust:manage`) is sound.

- [ ] (a) Missing: server-side mandatory biên bản — see Priority fixes.
- [ ] (c) Wrong: orphaned upload on failure — see Priority fixes.
- [x] (c) **Removed "Chốt" button.** ~~`renderPeriodList` only rendered Xóa for `status==='Mo'`.~~
  **FIXED** — restored the Chốt button (+ `closePeriod` → `rpc_stock_period_close`) for legacy `Mo`
  rows. Verified in preview: click fires `rpc_stock_period_close({p_id, p_actual_liters})` then refresh.
- [ ] (b) Scope creep (defensible, no action needed): `overflow-x:auto` wrappers on inventory +
  period-list tables; `closed_by/closed_at/now()` stamped for `tinh_tec` too, not just kiểm kê.

---

# Architecture review — deepening candidates

From `/improve-codebase-architecture` (report was generated to a temp HTML file, not committed).
Vocabulary from `/codebase-design`: module, interface, implementation, depth, seam, adapter,
leverage, locality.

## Candidate 1 — Collapse the chứng-từ-ảnh staging module  **[Strong — top pick]**

Files: `public/index.html` — `renderPumpPhotoBox`/`uploadStagedPumpPhotos`,
`renderNhapPhotoBox`/`uploadStagedNhapPhotos`, `renderBienBanBox` + inline upload in `recordPeriod`.

- **Problem.** The same stage → build-path → `sb.storage.upload` → record-path-via-RPC →
  remove-on-error shape is implemented three times. Each interface is nearly as complex as its
  implementation (shallow). The newest copy (biên bản) silently dropped the rollback — the storage
  leak the Spec review found.
- **Deletion test:** passes. Delete any one copy and the stage/upload/rollback complexity reappears
  at the caller.
- **Seam is real, not hypothetical:** three adapters already exist (pump ledger, nhập ledger, stock
  period) over the same `chung-tu` bucket. What varies across the seam is small: which slots exist,
  and which RPC records the path.

Proposed deep-module interface (small surface, lots of behaviour behind it):

```
stageDocPhoto(scope, kind, file)     // hold a file for a slot, render its preview
clearDocPhoto(scope, kind)           // drop a staged file
commitDocPhotos(scope) → paths       // upload all staged → record → rollback ALL on any failure
```

Each `scope` declares only its variable facts:

```
{ bucket:'chung-tu', slots:[...], pathFor(kind,file), record(path) }
```

Behind the seam (implementation absorbs the three copies): path construction (`monthOf`/`photoPath`),
the storage upload, the record-RPC dispatch, and ONE rollback that removes every uploaded object if
any step throws.

Wins:
- leverage: 3 call sites (and future doc types) learn one 3-method interface.
- locality: rollback bug, bucket name, path convention live in one module — fix once.
- the interface is the test surface: `commitDocPhotos` testable via an in-memory storage adapter.
- internal seam for testability: module ACCEPTS its storage adapter rather than reaching for global
  `sb.storage`.

## Candidate 2 — Extract stock_period_allocate() behind one seam  **[Strong — HELD]**

Files: `0012_stock_period.sql` (rpc_stock_period_close) · `0025_stock_period_record.sql`
(rpc_stock_period_record). Same as Standards smell #1 above — the proportional tịnh-âm/dương split +
largest-vehicle rounding is copy-pasted across two RPCs (and the ledger-sum query twice inside the
record RPC). Extract one `stock_period_allocate(period, tank, start, close, am, duong, total)` +
`stock_period_pump_total(tank, start, close)`; both RPCs call them. Locality: the math lives once.

**HELD — deliberately not done yet.** No local Postgres (migrations only deploy via the
`supabase db push` GitHub Action), so this refactor of the per-vehicle fuel-allocation *math* cannot be
executed/tested here. A silent extraction error would corrupt vehicle accounting. The duplication is a
maintainability smell, not an active bug — not worth shipping blind. Do it when a staging DB is
available: extract, `db push`, then cross-check `stock_period_alloc` totals against a known period
before/after.

## Candidate 3 — Move the kiểm-kê invariant onto the RPC seam  **[DONE]**

Files: `recordPeriod` (FE) · `rpc_stock_period_record`. Same as Spec finding (a). "Kiểm kê must have a
biên bản" was enforced only in the frontend; the RPC seam accepted a null path. **DONE** — guard moved
into the RPC via migration `0026_kiemke_bienban_required.sql`; the invariant now holds for every caller.
The FE `recordPeriod` check stays as fast feedback. Pairs with candidate 1's rollback fix (both done).

## Next step
Grill candidate 1's design (`/grilling`) before writing code — pressure-test the three scopes' real
differences, the rollback semantics on partial failure, and which tests survive the deepening.
