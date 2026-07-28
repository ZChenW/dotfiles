# Separate Update from Snapshot

Update is a consumption-only flow that pulls repository state, applies the saved machine profile, and verifies the result; it never publishes local state. Snapshot is the publication flow: from a clean worktree it first pulls with `--ff-only`, then captures the current machine, reviews the diff, and only then commits and pushes. This separation keeps routine installation and updates automatic while refusing to guess when two computers have divergent local changes.
