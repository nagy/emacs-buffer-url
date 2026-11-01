;;; buffer-url-tests.el --- Tests for buffer-url -*- lexical-binding: t; -*-

;; Copyright (C) 2026  Daniel Nagy

;; This file is free software: you can redistribute it and/or modify
;; it under the terms of the GNU Affero General Public License as
;; published by the Free Software Foundation, either version 3 of the
;; License, or (at your option) any later version.

;; This file is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU Affero General Public License for more details.

;; You should have received a copy of the GNU Affero General Public
;; License along with this file.  If not, see
;; <https://www.gnu.org/licenses/>.

;;; Commentary:

;; ERT tests for the pure helpers: remote URL conversion, the derived
;; mode predicate, the provider hook handling and the pretty printer.

;;; Code:

(require 'ert)
(require 'buffer-url)

;;; Remote URL conversion

(ert-deftest buffer-url-test-scp-remote ()
  (should
   (equal
    (buffer-url--remote-url-to-web
     "git@github.com:nagy/emacs-buffer-url.git")
    "https://github.com/nagy/emacs-buffer-url")))

(ert-deftest buffer-url-test-ssh-remote ()
  (should
   (equal
    (buffer-url--remote-url-to-web "ssh://git@github.com/nagy/repo.git")
    "https://github.com/nagy/repo"))
  (should
   (equal
    (buffer-url--remote-url-to-web "ssh://git@github.com:2222/nagy/repo.git")
    "https://github.com/nagy/repo"))
  ;; No user part, no port.
  (should
   (equal
    (buffer-url--remote-url-to-web "ssh://github.com/nagy/repo.git")
    "https://github.com/nagy/repo")))

(ert-deftest buffer-url-test-git-remote ()
  (should
   (equal
    (buffer-url--remote-url-to-web "git://git.kernel.org/pub/scm/git/git.git")
    "https://git.kernel.org/pub/scm/git/git")))

(ert-deftest buffer-url-test-https-remote ()
  (should
   (equal
    (buffer-url--remote-url-to-web "https://github.com/nagy/repo.git/")
    "https://github.com/nagy/repo"))
  (should
   (equal
    (buffer-url--remote-url-to-web "http://example.com/repo")
    "http://example.com/repo")))

(ert-deftest buffer-url-test-non-url ()
  (should-not (buffer-url--remote-url-to-web nil))
  (should-not (buffer-url--remote-url-to-web "not a url"))
  (should-not (buffer-url--remote-url-to-web "/local/path")))

;;; Derived mode predicate

(ert-deftest buffer-url-test-derived-p ()
  ;; Argument order: MODES first, MODE last, as `pcase' passes it.
  (should (buffer-url--derived-p '(prog-mode) 'emacs-lisp-mode))
  (should (buffer-url--derived-p '(special-mode) 'tabulated-list-mode))
  (should-not (buffer-url--derived-p '(magit-mode dired-mode)
                                     'emacs-lisp-mode)))

;;; Provider hook

(ert-deftest buffer-url-test-builtin-providers-registered ()
  (should (memq #'buffer-url--provider-magit
                buffer-url-provider-functions))
  (should (memq #'buffer-url--provider-git-remote
                buffer-url-provider-functions)))

(ert-deftest buffer-url-test-set-provider-functions-keeps-builtins ()
  ;; Customize replaces the whole hook value, so the :set function must
  ;; append the builtin providers again.
  (let ((hook (make-symbol "buffer-url-test-hook")))
    (set hook nil)
    (buffer-url--set-provider-functions hook '(ignore))
    (should (memq #'buffer-url--provider-magit (symbol-value hook)))
    (should (memq #'buffer-url--provider-git-remote (symbol-value hook)))))

(ert-deftest buffer-url-test-get-without-providers ()
  (with-temp-buffer
    (setq-local default-directory "/")
    (setq-local buffer-url-provider-functions nil)
    (should-not (buffer-url-get))))

(ert-deftest buffer-url-test-get-runs-providers ()
  (with-temp-buffer
    (setq-local default-directory "/")
    (setq-local buffer-url-provider-functions
                (list (lambda () "https://example.com/a")))
    (should (equal (buffer-url-get) "https://example.com/a"))))

(ert-deftest buffer-url-test-buffer-local-provider-wins ()
  ;; A buffer-local value replaces the whole hook, so the builtin
  ;; providers do not run.
  (with-temp-buffer
    (setq-local default-directory "/")
    (add-hook 'buffer-url-provider-functions
              (lambda () "https://example.com/local") nil t)
    (should (equal (buffer-url-get) "https://example.com/local"))))

(ert-deftest buffer-url-test-clear-cache ()
  (with-temp-buffer
    (setq-local default-directory "/")
    (setq-local buffer-url-provider-functions
                (list (lambda () "https://example.com/a")))
    (buffer-url-get)
    (should buffer-url--current)
    (buffer-url-clear-cache)
    (should-not buffer-url--current)))

(ert-deftest buffer-url-test-repo-remote-url-caches ()
  (let ((root (make-temp-file "buffer-url-test" t)))
    (unwind-protect
        (progn
          (should (zerop (call-process "git" nil nil nil "-C" root
                                       "init" "-q")))
          (should (zerop (call-process "git" nil nil nil "-C" root
                                       "remote" "add" "origin"
                                       "git@github.com:nagy/example.git")))
          (should (equal (buffer-url--repo-remote-url root)
                         "https://github.com/nagy/example"))
          ;; The second call returns the cached value.
          (should (equal (gethash root buffer-url--remote-cache)
                         "https://github.com/nagy/example")))
      (delete-directory root t))))

;;; Pretty printer

(ert-deftest buffer-url-test-pretty-print-uses-alist ()
  (with-temp-buffer
    (let ((buffer-url-shorten-alist '(("github.com" . "GH"))))
      (should (equal (buffer-url-pretty-print "https://github.com/a/b")
                     "GH/a/b")))))

(ert-deftest buffer-url-test-pretty-print-caches-per-url ()
  (with-temp-buffer
    (buffer-url-pretty-print "https://a.example/x")
    (should (equal (buffer-url-pretty-print "https://b.example/y")
                   "b.example/y"))))

(ert-deftest buffer-url-test-pretty-print-nil ()
  (with-temp-buffer
    (should-not (buffer-url-pretty-print nil))))

(ert-deftest buffer-url-test-shorten-alist-clears-cache ()
  (with-temp-buffer
    (buffer-url-pretty-print "https://a.example/x")
    (should buffer-url-pretty-printed)
    (buffer-url--set-shorten-alist 'buffer-url-shorten-alist nil)
    (should-not buffer-url-pretty-printed)))

(provide 'buffer-url-tests)
;;; buffer-url-tests.el ends here
