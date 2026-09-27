# Consolidating the device patch series — done, with two exceptions

Carried out 2026-09-27. Kept rather than deleted because two items are deliberately unfinished and the
method is worth reusing.

`check-patch-series.sh` reported **12 pairs** where a later patch undid an earlier one, across **38**
device patches. It now reports **1**, across **35**.

One of the original 12 was never real. `system/core` 0001 adds `"Mode": "0755",` to `cgroups.json` and
0003 removes an identically worded line from `cgroups.recovery.json` -- different files, nothing undone.
The checker was matching line bodies across a whole project instead of per file, and this plan recorded
the result as work to do. Fixed in rom-forge; a pair now requires the same file, and the report names
it. So the real count was 11, and 10 of them are gone.

## What was done

| step | result |
|---|---|
| Capability advertisement folded (0004, 0025, 0026, 0035, 0037 → one patch) | 6 pairs gone |
| IMS blob staging: 0018 ships the final guarded form, 0023 dropped | 1 pair gone |
| Each ld-preload shim registered in its own `+=` block | 1 pair gone |
| ImsBridge restructured: 3 patches → 2 (surface, then implementation) | 2 pairs gone |
| Volume panel split out of the CNE property patch | legibility |
| Series reordered into families | legibility |

Three patches turned out to be doing a second, unrelated job, and only one of them was in the original
plan: `0004` also disabled PMF, `0026` also set the vt boolean, and `0034` also appended a comment to
`vendor.xml`. Asking "what files does this patch touch" found the third; reading titles would not have.

## Method — this is the part worth keeping

1. Record `git rev-parse HEAD^{tree}` for the project.
2. Reset to the vendored base commit, replay the series with the change applied, compare the tree
   object. **It must be identical.** If it is not, the fold changed behaviour, however plausible it
   looked. This caught two wrong attempts.
3. `refresh-patches.sh --force` (it refuses to drop patches without it), then
   `check-patch-series.sh` to confirm the count fell.

Traps met, all of which produced a silently wrong patch rather than an error:

- Patches are exported `--no-signature`, so there is no `-- ` trailer and the file's final newline
  lives inside the last diff section. Strip that section and the patch ends without a newline, which
  `git apply` reports as "corrupt patch at line N".
- Strip whole per-file sections, never individual hunks, or the `@@` counts need recomputing.
- Retargeting context is fine as long as the **line count** does not change.
- Editing a line a patch *adds* turns it into context for every later patch that quotes it. Changing
  two `VOLTE.md` references meant retargeting the nanopb and VT patches too.
- `set -e` is not reliable in this harness. Check exit codes explicitly; a `&&` chain let one replay
  commit a patch that had failed to apply.

## Still open

- **The full eight-family grouping.** Only 8 of 35 patches can move freely; the rest share `device.mk`
  (14 of them) or `BoardConfig.mk` (7), so moving them means retargeting context through most of the
  series. The families that could be formed were. Getting `0011` (modem bring-up) adjacent to the IMS
  block, or the sepolicy patches together at the end, is what remains.
- **The one pair left is deliberate.** `0033` refines a method `0023` wrote as pure delegation, to log
  a refusal instead of reading as a completed set. Folding a diagnostic into the bridging patch would
  muddy both.

## Not yet compiled

Two commits deliberately changed the tree rather than preserving it byte-for-byte: the `+=` shim
registration, and `carrier_vt_available_bool` going false to match the device leg. Both are
argued-identical rather than proven-identical. The next build is the confirmation.
