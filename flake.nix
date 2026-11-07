{
  description = "Copy or browse the URL of the current Emacs buffer (Emacs package)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      # One nixpkgs closure, no duplicates.
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      flake-parts,
      nixpkgs,
      treefmt-nix,
      ...
    }:
    # Date of the last commit as YYYY-MM-DD, folded into the version
    # string below.  Flake source info gives it as e.g. "20260922133522".
    # A repository without commits reports the epoch, so the version only
    # becomes meaningful after the first commit..
    let
      lastModifiedDate = inputs.self.sourceInfo.lastModifiedDate;
      commitDate = "${builtins.substring 0 4 lastModifiedDate}-${
        builtins.substring 4 2 lastModifiedDate
      }-${builtins.substring 6 2 lastModifiedDate}";
    in
    flake-parts.lib.mkFlake { inherit inputs; } {
      # Emacs packages are pure Elisp: no ELF binaries, so evaluate on
      # every Linux arch (and darwin if the deps exist there).
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      perSystem =
        {
          pkgs,
          lib,
          config,
          ...
        }:
        {
          # makeOverridable gives the package `.override', so a consumer
          # can swap the Emacs build, e.g.
          # `buffer-url.override { emacs = pkgs.emacs-gtk; }'.
          packages.buffer-url = lib.makeOverridable (
            {
              emacs ? pkgs.emacs,
              emacsPackages ? emacs.pkgs,
              git ? pkgs.git,
              # Nix rejects versions Nixpkgs cannot parse. Convention for
              # unreleased packages: <upstream-version>-unstable-<YYYY-MM-DD>,
              # where the date is the last commit touching the source. Derived
              # from the flake's source info above, so it never goes stale.
              version ? "0.1.0-unstable-${commitDate}",
              src ? lib.cleanSource ./.,
            }:
            emacsPackages.melpaBuild {
              pname = "buffer-url";
              inherit version src;

              # Keep the ERT suite out of the installed package but leave it
              # in the source tree for `checkPhase' below.
              files = ''(:defaults (:exclude "buffer-url-tests.el"))'';

              # No packageRequires: the Package-Requires header only lists
              # Emacs itself.  Magit and browse-at-remote are optional
              # providers, called through `declare-function'.

              # Byte-compilation warnings fail the build. Keep it on: it is
              # the cheapest lint the package will ever get.
              turnCompilationWarningToError = true;

              # The ERT suite covers the pure helpers: remote URL conversion,
              # the provider hook, the repository remote cache and the pretty
              # printer.
              checkPhase = ''
                runHook preCheck
                # `package-initialize' (as elpa2nix does at install time) is
                # what puts the packageRequires dependencies on `load-path';
                # a plain batch Emacs cannot see them otherwise.
                emacs --batch -L . \
                  --eval "(require 'package)" \
                  -f package-initialize \
                  --eval '(setq byte-compile-error-on-warn t)' \
                  -f batch-byte-compile buffer-url-tests.el
                emacs --batch -L . \
                  --eval "(require 'package)" \
                  -f package-initialize \
                  -l buffer-url-tests.elc \
                  -f ert-run-tests-batch-and-exit
                runHook postCheck
              '';

              doCheck = true;

              # One test initializes a throwaway repository to exercise the
              # remote lookup and its cache, so the suite needs git.  The
              # nativeCheckInputs hooks also give the suite a writable HOME.
              nativeCheckInputs = [
                git
                pkgs.writableTmpDirAsHomeHook
              ];

              meta = {
                description = "Copy or browse the URL of the current buffer";
                longDescription = ''
                  Provides a generic "URL of this buffer" interface for Emacs.
                  Major modes register provider functions on
                  `buffer-url-provider-functions'; the commands `buffer-url-copy'
                  and `buffer-url-browse' then use the first provider that
                  returns a URL.

                  Builtin providers cover Magit buffers (the repository remote,
                  or the commit URL of a revision) and any buffer inside a git
                  repository.  Git remote URLs (scp-like, ssh:// and git://)
                  are rewritten to their browsable https form.
                '';
                # The license is declared in the file header.
                license = lib.licenses.agpl3Plus;
                homepage = "https://github.com/nagy/emacs-buffer-url";
                maintainers = with lib.maintainers; [ nagy ];
                platforms = lib.platforms.unix;
              };
            }
          ) { };

          packages.default = config.packages.buffer-url;

          checks = {
            # melpaBuild byte-compiles with warnings as errors and
            # `checkPhase' runs the ERT suite, so building the package is
            # the main check.
            default = config.packages.buffer-url;

            # checkdoc + package-lint: catch what byte-compilation cannot.
            lint =
              pkgs.runCommand "buffer-url-lint"
                {
                  nativeBuildInputs = [
                    (pkgs.emacsPackages.emacsWithPackages (p: [ p.package-lint ]))
                  ];
                  src = config.packages.buffer-url.src;
                  meta.description = "checkdoc and package-lint for buffer-url.el";
                }
                ''
                  export HOME=$TMPDIR
                  cp "$src"/buffer-url.el .
                  emacs --batch -l package-lint \
                    -f package-lint-batch-and-exit buffer-url.el
                  # checkdoc always exits zero; gate on its output instead.
                  lint_log=$(emacs --batch -l checkdoc --eval '(checkdoc-file "buffer-url.el")' 2>&1)
                  if [ -n "$lint_log" ]; then printf '%s\n' "$lint_log"; exit 1; fi
                  touch $out
                '';
          };

          # Dev shell with a real Emacs plus the optional providers, for
          # interactive testing:
          # nix build; emacs -l result/share/emacs/site-lisp/elpa/buffer-url-*/buffer-url-autoloads.el
          devShells.default = pkgs.mkShell {
            packages = [
              pkgs.emacs
              pkgs.emacsPackages.magit
              pkgs.emacsPackages.browse-at-remote
              pkgs.git
            ];
          };

          # `nix fmt' formats the flake via treefmt, never the formatters
          # standalone.
          formatter = treefmt-nix.lib.mkWrapper pkgs {
            projectRootFile = "flake.nix";
            programs.nixfmt.enable = true;
          };
        };
    };
}
