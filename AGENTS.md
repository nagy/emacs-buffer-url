# AGENTS.md — emacs-buffer-url

## Purpose

`buffer-url.el`: Emacs Lisp package that returns the URL of the current buffer.
Emacs 30.1 or newer. License: AGPL-3.0-or-later. The user documentation lives in
`README.org`.

## Build and test

- `nix flake check` — the gate. Byte-compile with warnings as errors, ERT suite,
  checkdoc, package-lint. Run it before you finish.
- `nix build` — build the package only.
- `nix fmt` — format the flake. Do not run the formatters standalone.
- Ad-hoc run: `emacs --batch -L . -L test -l test/buffer-url-test.el -f
  ert-run-tests-batch-and-exit`.

## Rules

- Do not silence byte-compilation warnings. Fix them.
- Load an optional runtime dependency (Magit, browse-at-remote, the `git`
  executable) through `require ... nil t` plus `declare-function`. Do not add it
  to `Package-Requires`.
- Keep the full AGPL-3.0-or-later header in every `.el` file.
- Keep checkdoc and package-lint clean.
- Tests live in `test/`, one file per source unit, named `<unit>-test.el`.
  Shared fixtures go in `buffer-url-test-helper.el` and must not match
  `*-test.el`. Prefix every `ert-deftest` with `buffer-url-`.
- The `checkPhase` loader globs `test/*-test.el`, so a new test file needs no
  flake edit. Do not hardcode test file names there. The lint check covers
  `*.el` and `test/*.el`.

## Conventions

- Prefix public names with `buffer-url-` and private names with `buffer-url--`.
- Declare `(declare (side-effect-free t))` in a pure helper.
