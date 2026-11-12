# AGENTS.md

Emacs Lisp package.  The user documentation lives in `README.org`.

## Commands

- `nix flake check` — the gate.  Byte-compiles with warnings as errors,
  runs the ERT suite, checkdoc and package-lint.  Run it before you
  finish.
- `nix build` — build the package only.
- `nix fmt` — format the flake.  Do not run the formatters standalone.
- Ad-hoc test run: `emacs --batch -L . -L test -l test/buffer-url-test.el -f
  ert-run-tests-batch-and-exit`.

## Test layout

- Tests live in `test/`, one file per source unit, named
  `<unit>-test.el`.  Shared fixtures go in `buffer-url-test-helper.el`
  and must not match `*-test.el`.
- The `checkPhase` loader globs `test/*-test.el`, so a new test file
  needs no flake edit.  Do not hardcode test file names there.
- The lint check covers `*.el` and `test/*.el`.  Prefix every
  `ert-deftest` with `buffer-url-`.

## Conventions

- Support Emacs 30.1 and newer.
- Load an optional runtime dependency (Magit, browse-at-remote, the
  `git` executable) through `require ... nil t` plus
  `declare-function`.  Do not add it to `Package-Requires`.
- Use the AGPL-3.0-or-later license.  Keep the full header in every .el
  file.
- Fix byte-compilation warnings.  Do not silence them.
- Prefix public names with `buffer-url-` and private names with
  `buffer-url--`.
- Keep checkdoc and package-lint clean.
- Declare `(declare (side-effect-free t))` in a pure helper.
