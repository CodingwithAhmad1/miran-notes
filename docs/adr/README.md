# Architecture Decision Records (ADRs)

ADRs capture **significant, stable decisions** with context and consequences. They complement [Constraints.md](../../Constraints.md): constraints state what must not break; ADRs record *why* a particular design was chosen. See the [documentation hub](../README.md) for the full doc map.

## Index

| ADR | Title |
|-----|--------|
| [0001-wiki-links-and-identity.md](0001-wiki-links-and-identity.md) | Wiki links, `noteID`, and resolution |
| [0002-auxiliary-storage-jsonl.md](0002-auxiliary-storage-jsonl.md) | Auxiliary storage for tables / JSONL under `_aux/` |
| [0003-folders-paths-and-manifest-v2.md](0003-folders-paths-and-manifest-v2.md) | Nested folders, `relativePath`, manifest v2 |
| [0004-vault-level-databases-and-planning.md](0004-vault-level-databases-and-planning.md) | Vault-level databases (`_databases/`) and Miran Planning integration |

## Adding an ADR

1. Use the next number after the latest ADR (e.g. `0005-short-title.md`).
2. Include **Status**, **Context**, **Decision**, and **Consequences** (or equivalent).
3. Link the new file from the table above.
