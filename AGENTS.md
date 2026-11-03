# AGENTS.md

Emacs Lisp package `buffer-url.el`: a generic "URL of the current
buffer" interface.  Providers run in
`buffer-url-provider-functions`; `buffer-url-copy` and
`buffer-url-browse` consume the result.

## Commands

- `nix flake check` — package (byte-compile, warnings as errors, ERT
  suite) + checkdoc + package-lint.  Meaningful gate; run before done.
- `nix build` — the melpaBuild package (runs the ERT suite too).
- `nix fmt` — treefmt/nixfmt; never run formatters standalone.
- Ad-hoc test run: `emacs --batch -L . -l buffer-url-tests.el -f
  ert-run-tests-batch-and-exit`.

## Layout

- `buffer-url.el` — the package: the provider hook, the commands, the
  builtin git/Magit providers, the caches and the pretty printer.
- `buffer-url-tests.el` — ERT suite for the pure helpers; excluded
  from the installed package by the recipe `:files` spec.  One test
  creates a throwaway git repository, so `git` is a `nativeCheckInputs`
  entry.
- `flake.nix` — melpaBuild package with `checkPhase`, the lint check,
  the devShell (Emacs + Magit + browse-at-remote + git), treefmt.
  The package is wrapped in `lib.makeOverridable`, so consumers can
  override `emacs`, `emacsPackages`, `git`, `version` and `src`.
- `README.org` — user-facing documentation.

## Conventions

- Emacs 30.1 minimum.  The `Package-Requires` header lists Emacs only;
  Magit, browse-at-remote and `git` are optional runtime providers,
  reached through `require ... nil t` and `declare-function`.
- License AGPL-3.0-or-later; keep the full header in every .el file.
- `turnCompilationWarningToError` stays on; fix warnings, do not
  silence.
- Prefix `buffer-url-` / `buffer-url--`; keep checkdoc and
  package-lint clean.
- Mode checks use `buffer-url--derived-p` (a `provided-mode-derived-p`
  wrapper), not a third-party `pcase` pattern.  `pcase` appends the
  matched value as the last argument, so the wrapper takes MODES first
  and MODE last.
- The `:set` function of `buffer-url-provider-functions` re-adds the
  builtin providers, because Customize replaces the whole hook value.
- Three caches: `buffer-url--current` (URL per buffer),
  `buffer-url-pretty-printed` (URL to shortened string) and
  `buffer-url--remote-cache` (repository root to remote URL).  The
  command `buffer-url-clear-cache` empties all of them; the `:set`
  functions of the two defcustoms clear the ones they invalidate.
