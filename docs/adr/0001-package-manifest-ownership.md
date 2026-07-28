# Keep package manifest ownership profile-specific

Each machine profile owns its package snapshot output: Standard machines refresh only the Standard manifests, while Lightweight machines refresh only `packages/arch-lightweight.txt`. Both exports derive from the machine's explicitly installed packages, exclude machine-local and globally excluded packages, and expose their diff for review before commit. This preserves automatic snapshots on both computers without allowing one profile to overwrite or silently expand the other.
