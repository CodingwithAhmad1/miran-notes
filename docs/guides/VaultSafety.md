# Vault safety: sync folders and backups

Miran Notes stores your library as normal files under a folder you choose (the **vault**). The app uses coordinated saves and recovery for its own writes, but **cloud sync tools and other apps** can still change files while you edit. This guide sets expectations without exaggerating risk.

## Cloud-sync folders (Dropbox, iCloud Drive, Google Drive, etc.)

**You may** keep the vault inside a synced directory. Many people do. Sync is convenient; it is not part of Miran’s product guarantees—the filesystem and the sync client own timing, conflict files, and temporary names.

**What often goes wrong (and why it is not a Miran bug):**

- **Two devices or apps edit the same note** — the sync service may merge, duplicate, or produce “conflict” copies with extra filenames. Miran cannot prevent that; it reacts when it sees the file on disk change.
- **Large bulk changes** while sync is busy — copies, imports, or git operations alongside sync can produce transient odd states. Prefer **pausing sync** or waiting for sync to finish before massive moves.
- **Conflict sidecar files** — if you see unexpected `.txt` or extra files, check whether the sync tool created duplicates; reconcile manually if needed.

**Practical habits:**

- Treat one vault as **one writer at a time** per note when possible (finish editing on one Mac before relying on another copy).
- After copying **many** files into the vault, open it in Miran once and let **manifest reconcile** complete (see [ImportingNotes.md](ImportingNotes.md)).

## When the app tells you the file changed elsewhere

If the on-disk note changes while you have unsaved edits, Miran can show a structured choice (keep your edits, use the saved file, Finder, compare, details). That flow is the supported way to resolve **external** changes—including those caused by sync. It complements this guide: sync increases how often that situation appears; the UI is there to make it explicit.

## Backups

**Recommended:** rely on **Time Machine** or another whole-disk / whole-folder backup that you actually restore-test occasionally.

**Also fine:** periodic **zip or copy** of the vault folder to another disk. Miran’s saves aim to be atomic for the files they touch; backups still protect you from accidental deletes, disk failure, and sync mistakes.

Miran does **not** replace a backup strategy. It also does not encrypt the vault for you; encryption-at-rest is an OS or full-disk feature unless you add it yourself.

## Related

- [ImportingNotes.md](ImportingNotes.md) — layout, identity, bulk import, drift checks.
- [vault-data-layer.md](../architecture/vault-data-layer.md) — how the app reads and commits vault data (including path expectations).
