# Architecture Decision Records (ADRs)

ADRs capture **significant, stable decisions** with context and consequences. They complement [Constraints.md](../../Constraints.md): constraints state what must not break; ADRs record *why* a particular design was chosen. See the [documentation hub](../README.md) for the full doc map.

## Index

| ADR | Title |
|-----|--------|
| [0001-wiki-links-and-identity.md](0001-wiki-links-and-identity.md) | Wiki links, `noteID`, and resolution |
| [0002-auxiliary-storage-jsonl.md](0002-auxiliary-storage-jsonl.md) | Historical `_aux/` JSONL table layout (withdrawn; decode-only cleanup) |
| [0003-folders-paths-and-manifest-v2.md](0003-folders-paths-and-manifest-v2.md) | Nested folders, `relativePath`, manifest v2 |
| [0004-vault-level-databases-and-planning.md](0004-vault-level-databases-and-planning.md) | Vault-level databases (`_databases/`) and Miran Planning integration |
| [0005-block-metadata-invariants.md](0005-block-metadata-invariants.md) | Block metadata invariants (gapless UTF-16 partition, normalization contract) |
| [0006-threat-model-app-sandbox-vault-access.md](0006-threat-model-app-sandbox-vault-access.md) | Threat model, vault-root capability, bookmarks, App Sandbox path |

## Adding an ADR

1. Use the next number after the latest ADR (e.g. `0006-short-title.md`).
2. Include **Status**, **Context**, **Decision**, and **Consequences** (or equivalent).
3. Link the new file from the table above.
