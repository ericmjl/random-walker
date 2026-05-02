# Code conventions

## Placement

- **Domain logic** that should be unit-tested belongs in **RandomWalkerCore** with tests in **RandomWalkerCoreTests**.
- **MapKit-specific** types stay in the iOS target unless there is a strong reason to share; prefer plain snapshot types in core (see `RoutedStep` vs `MKRoute.Step`).

## Documentation in source

- Preserve **Sphinx-style** docstrings in core code to match existing style.
- **No types in docstrings** (project convention); use type hints in Swift signatures instead.

## Agent-oriented note

Agents should treat [docs/index.md](index.md) as the entry point for repository intent and structure.
