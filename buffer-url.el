;;; buffer-url.el --- URL of the current buffer -*- lexical-binding: t; -*-

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

;; Author: Daniel Nagy <danielnagy@posteo.de>
;; Maintainer: Daniel Nagy <danielnagy@posteo.de>
;; Version: 0.1.0
;; Keywords: convenience, hypermedia
;; Package-Requires: ((emacs "30.1"))
;; URL: https://github.com/nagy/emacs-buffer-url

;;; Commentary:

;; Generic "URL of this buffer" interface.
;;
;; Major modes report a URL by adding a provider function to the
;; buffer-local value of `buffer-url-provider-functions'.  The
;; commands below then copy or browse that URL.
;;
;;   (add-hook 'buffer-url-provider-functions
;;             #'my-mode-url nil t)
;;
;; A provider takes no arguments.  It returns a URL string, or nil
;; when the current buffer has no known URL.  Use DEPTH -10 for a
;; provider that must win over the builtin ones.
;;
;; Builtin providers handle Magit buffers (the remote of the
;; repository, or the commit URL of a revision) and any buffer inside
;; a git repository.  Git remote URLs are converted to browsable http
;; or https form, so ssh and git remotes work too.

;;; Code:

(require 'cl-lib)
(require 'subr-x)

(defgroup buffer-url nil
  "Report and use the URL of the current buffer."
  :group 'convenience
  :prefix "buffer-url-")

(defvar buffer-url--builtin-providers
  '((buffer-url--provider-magit . -30)
    (buffer-url--provider-git-remote . 0))
  "Builtin providers, as (FUNCTION . DEPTH) conses.")

(defun buffer-url--set-provider-functions (var value)
  "Set VAR to VALUE, then append the builtin providers.
Customize replaces the whole value of a hook, so the builtin
providers must come back on every set.  `add-hook' skips duplicates."
  (set-default var value)
  (dolist (provider buffer-url--builtin-providers)
    (add-hook var (car provider) (cdr provider))))

(defcustom buffer-url-provider-functions nil
  "Functions that return the URL of the current buffer.
Each function takes no arguments and returns a URL string, or nil
when the current buffer has no URL.

Builtin providers fill the global value.  Add a provider to the
buffer-local value to override them:

  (add-hook \\='buffer-url-provider-functions #\\='my-provider -10 t)"
  :type 'hook
  :set #'buffer-url--set-provider-functions
  :group 'buffer-url)

(defun buffer-url--clear-pretty-caches ()
  "Forget the cached pretty URLs of all buffers."
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (kill-local-variable 'buffer-url-pretty-printed))))

(defun buffer-url--set-shorten-alist (var value)
  "Set VAR to VALUE, then forget the cached pretty URLs.
The cache holds shortened strings, so it goes stale when the labels
change."
  (set-default var value)
  (buffer-url--clear-pretty-caches))

(defcustom buffer-url-shorten-alist nil
  "Alist of host names and the short labels that replace them.
`buffer-url-pretty-print' replaces each host name with its label."
  :type '(alist :key-type string :value-type string)
  :set #'buffer-url--set-shorten-alist
  :group 'buffer-url)

(defvar-local buffer-url--current nil
  "URL of the current buffer, cached for `buffer-url-get'.")
(put 'buffer-url--current 'permanent-local t)

;;;###autoload
(defun buffer-url-get (&optional force)
  "Return the URL of the current buffer, or nil.
If FORCE is non-nil, ignore the cached value.  Providers do not
run in remote buffers, and nil results stay out of the cache."
  (when force
    (setq buffer-url--current nil))
  (unless (file-remote-p default-directory)
    (with-memoization buffer-url--current
      (run-hook-with-args-until-success
       'buffer-url-provider-functions))))

;;;###autoload
(defun buffer-url-browse ()
  "Open the URL of the current buffer in a browser."
  (interactive)
  (if-let* ((url (buffer-url-get)))
      (browse-url url)
    (user-error "No URL for this buffer")))

;;;###autoload
(defun buffer-url-copy ()
  "Copy the URL of the current buffer to the kill ring."
  (interactive)
  (if-let* ((url (buffer-url-get)))
      (progn
        (kill-new url)
        (message "Killed: %s" url))
    (user-error "No URL for this buffer")))

;;; Contrib

(declare-function magit-get-current-remote "magit")
(declare-function magit-get "magit")
(declare-function browse-at-remote-get-url "browse-at-remote")
(declare-function project-root "project")

(defun buffer-url--derived-p (modes mode)
  "Return non-nil if MODE is derived from any of MODES.
Argument order fits the `pcase' `pred' pattern, which appends the
matched value as the last argument."
  (declare (side-effect-free t))
  (apply #'provided-mode-derived-p mode modes))

(defun buffer-url--remote-url-to-web (url)
  "Convert a git remote URL to a browsable URL, or nil.
Handle scp-like (git@HOST:PATH), ssh:// and git:// remotes.
Strip a trailing slash and the .git suffix from the path.  Return
nil when URL is not a string, or not an http or https URL."
  (declare (side-effect-free t))
  (when (stringp url)
    (setq url (string-trim url))
    (cond
     ;; scp-like syntax: git@github.com:owner/repo.git
     ((string-match "\\`[^@/]+@\\([^:/]+\\):\\(.+\\)\\'" url)
      (setq url (format "https://%s/%s"
                        (match-string 1 url) (match-string 2 url))))
     ;; ssh://[USER@]HOST[:PORT]/PATH
     ((string-match "\\`ssh://\\(?:[^@/]+@\\)?\\([^:/]+\\)\\(?::[0-9]+\\)?/\\(.+\\)\\'"
                    url)
      (setq url (format "https://%s/%s"
                        (match-string 1 url) (match-string 2 url))))
     ;; git://HOST[:PORT]/PATH
     ((string-match "\\`git://\\([^:/]+\\)\\(?::[0-9]+\\)?/\\(.+\\)\\'" url)
      (setq url (format "https://%s/%s"
                        (match-string 1 url) (match-string 2 url)))))
    (when (string-match-p "\\`https?://" url)
      (string-remove-suffix ".git" (string-remove-suffix "/" url)))))

(defun buffer-url--provider-magit ()
  "Return the URL of a Magit revision, or of a Magit or Dired buffer."
  (pcase major-mode
    ((pred (buffer-url--derived-p '(magit-revision-mode)))
     (when (require 'browse-at-remote nil t)
       (browse-at-remote-get-url)))
    ((pred (buffer-url--derived-p '(magit-mode dired-mode)))
     (when (require 'magit nil t)
       (when-let* ((project (project-current))
                   (default-directory (project-root project)))
         (buffer-url--remote-url-to-web
          (magit-get "--local"
                     (format "remote.%s.url"
                             (magit-get-current-remote)))))))))

(defvar buffer-url--remote-cache (make-hash-table :test #'equal)
  "Cache of repository roots and their browsable remote URLs.")

(defun buffer-url--repo-remote-url (root)
  "Return the browsable origin URL of the repository at ROOT, or nil.
Cache the result in `buffer-url--remote-cache', so the buffers of
one repository fork `git' only once."
  (let ((cached (gethash root buffer-url--remote-cache 'missing)))
    (if (not (eq cached 'missing))
        cached
      (let ((url (with-temp-buffer
                   (when (zerop (call-process "git" nil t nil
                                              "-C" (expand-file-name root)
                                              "remote" "get-url" "origin"))
                     (buffer-string)))))
        (puthash root (buffer-url--remote-url-to-web url)
                 buffer-url--remote-cache)))))

(defun buffer-url--provider-git-remote ()
  "Return the URL of the git remote of the current buffer."
  (when-let* ((root (locate-dominating-file default-directory ".git")))
    (buffer-url--repo-remote-url root)))

(dolist (provider buffer-url--builtin-providers)
  (add-hook 'buffer-url-provider-functions (car provider) (cdr provider)))

(defvar-local buffer-url-pretty-printed nil
  "Cached (URL . PRETTY) pair for `buffer-url-pretty-print'.")
(put 'buffer-url-pretty-printed 'permanent-local t)

(defun buffer-url-pretty-print (url)
  "Return a shortened form of URL for display, or nil.
Strip the https:// prefix and replace host names with the labels
from `buffer-url-shorten-alist'.  Cache the result per URL."
  (when url
    (unless (equal (car-safe buffer-url-pretty-printed) url)
      (setq buffer-url-pretty-printed
            (cons url
                  (let ((pretty (string-remove-prefix "https://" url)))
                    (dolist (el buffer-url-shorten-alist)
                      (setq pretty (string-replace (car el) (cdr el) pretty)))
                    pretty))))
    (cdr buffer-url-pretty-printed)))

;;;###autoload
(defun buffer-url-clear-cache ()
  "Forget the cached URLs of every buffer.
Also empty the repository remote cache, so a changed remote URL
takes effect."
  (interactive)
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (kill-local-variable 'buffer-url--current)
      (kill-local-variable 'buffer-url-pretty-printed)))
  (clrhash buffer-url--remote-cache)
  (force-mode-line-update t))

(provide 'buffer-url)
;;; buffer-url.el ends here
