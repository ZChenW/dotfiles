# Dotfiles Installation

The vocabulary used to describe installation scopes and machine-specific setup choices in this repository.

## Language

**Lightweight installation profile**:
A machine profile for resource-constrained systems that retains the core desktop and daily-use capabilities while excluding heavyweight or optional software. It remains the machine's software scope across initial setup and later package synchronization.
_Avoid_: Minimal update, minimal install

**Standard installation profile**:
The default machine profile containing the repository's complete portable software scope.
_Avoid_: Full profile, full packages

**Lightweight daily development machine**:
A resource-constrained computer intended for routine coding, browsing, communication, and desktop use rather than gaming, media production, or heavyweight specialist workloads.
_Avoid_: Minimal computer, full workstation

**Update**:
The consumption flow that brings repository state onto the current machine without publishing that machine's local state.
_Avoid_: Two-way sync, snapshot

**Snapshot**:
The publication flow that captures a machine's managed state into the repository for other machines to consume.
_Avoid_: Update, backup
