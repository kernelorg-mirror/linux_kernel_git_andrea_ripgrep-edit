;;; rg-edit.el --- Invoke ripgrep-edit  -*- lexical-binding: t; -*-
;;; SPDX-License-Identifier: GPL-3.0-or-later OR AGPL-3.0-or-later

;; Copyright (C) 2025  Red Hat Inc.

;;; Commentary:

;; This module provides helper functions to invoke the `rg-edit` executable
;; with the current region or word as the search pattern. It requires the `rg-edit`
;; binary to be installed and accessible in the system PATH or configured via
;; `rg-edit-executable`.

;;; Example configuration:

;; (add-to-list 'load-path "~/.../ripgrep-edit/emacs/")
;; (use-package rg-edit
;;   :ensure nil
;;   :config
;;   (setq-default rg-edit-auto-mark-whole-buffer t)
;;   (setq-default rg-edit-executable "~/.../ripgrep-edit/target/release/rg-edit"))

;;; Code:

(defgroup rg-edit nil
  "Edit ripgrep search results across multiple files."
  :group 'tools
  :prefix "rg-edit-")

(defcustom rg-edit-executable "rg-edit"
  "The rg-edit executable to use."
  :type 'string
  :group 'rg-edit)

(defcustom rg-edit-gptel-system-message
  (concat "You are a careful programmer. Rewrite cross-file snippets.\n"
	  "Rewrite everything exactly the same except: the required change.\n"
	  "Keep the filenames at the start of the files.\n"
	  "Keep the separators at the end of the snippets.\n"
	  "Do not delete the filenames and the separators.\n"
	  "Do not add markdown fences.\n"
	  "Do not ask clarification.")
  "The rg-edit gptel-system-message to use when in a rg-edit buffer."
  :type 'string
  :group 'rg-edit)

(defcustom rg-edit-auto-mark-whole-buffer nil
  "If non-nil, mark the whole buffer when entering rg-edit-mode.
This prepares the buffer for AI rewriting by selecting all content."
  :type 'boolean
  :group 'rg-edit)

(defcustom rg-edit-prefill-extra-args "-U --multiline-dotall --smart-case"
  "Prefill the rg-edit commands extra-args parameter with this value.
These extra arguments are used only if the extra-args parameter is otherwise nil."
  :type 'string
  :group 'rg-edit)

(defvar rg-edit--history-regexp nil "History for rg-edit regexp patterns.")
(defvar rg-edit--history-extra-args nil "History for rg-edit extra-args.")

(define-key global-map (kbd "C-c r") #'rg-edit-git)

(require 'server)
(defun rg-edit--check-server ()
  "Check if the Emacs server is running and signal an error if not."
  (unless (server-running-p)
    (user-error "Emacs server is not running. Please start it with 'M-x server-start'")))

(defun rg-edit--collect-extra-args (extra-args)
  "Collect extra arguments for rg-edit command."
  (let ((extra-args (read-string "Extra args: "
                                  (or extra-args rg-edit-prefill-extra-args)
                                  'rg-edit--history-extra-args)))
    (unless (string-empty-p extra-args)
      extra-args)))

(defun rg-edit--terminate ()
  "Terminate all outstanding rg-edit processes by closing the *rg-edit* buffer."
  (interactive)
  (kill-buffer))

(defun rg-edit--setup-buffer (rg-buffer)
  "Setup the *rg-edit* buffer before running rg-edit."
  (switch-to-buffer rg-buffer)
  (read-only-mode -1)
  (erase-buffer)
  (goto-char (point-min))
  (unless (current-local-map)
    (let ((map (make-sparse-keymap)))
      (define-key map (kbd "C-c C-k") #'rg-edit--terminate)
      (use-local-map map)))
  (insert "C-c C-k on this buffer will close it and terminate any outstanding rg-edit session\n\n")
  (when (rg-edit--gptel-gbnf-enabled-p)
    (insert "GBNF Grammar Enabled\n\n"))
  (with-current-buffer rg-buffer
    (visual-line-mode)))

(require 'cl-lib)
(defun rg-edit--gptel-gbnf-enabled-p ()
  "Return t if at least one model of a configured gptel backend supports GBNF or EBNF."
  (when (and (fboundp 'gptel--model-capable-p)
             (boundp 'gptel--known-backends))
    (cl-loop for backend-entry in gptel--known-backends
             for backend-value = (cdr backend-entry)
             thereis (and (gptel-backend-p backend-value)
                          (cl-loop for model in (gptel-backend-models backend-value)
                                   thereis (or (gptel--model-capable-p 'gbnf model)
                                               (gptel--model-capable-p 'ebnf model)))
                          t))))

(defun rg-edit--run-command (regexp path extra-args)
  "Run rg-edit with REGEXP, PATH, and EXTRA-ARGS."
  (let* ((path-dir (directory-file-name path))
	 (base-name (file-name-nondirectory path-dir))
	 ;; When the search path is the filesystem root, the base
	 ;; name is empty: search "." from within the root instead of
	 ;; passing an empty path argument to rg
	 (root-p (string-empty-p base-name))
	 (dir-name (if root-p "." base-name))
	 (work-dir (if root-p
		       (file-name-as-directory path-dir)
		     (file-name-directory path-dir)))
	 (rg-buffer (get-buffer-create "*rg-edit*" t))
	 (gbnf (when (rg-edit--gptel-gbnf-enabled-p)
		 "--gbnf"))
	 (extra-args (concat gbnf
			     (when (and gbnf extra-args) " ")
			     extra-args)))
    (save-some-buffers
     nil (lambda ()
	   (when-let* ((file (buffer-file-name)))
	     (let ((root (file-truename path-dir))
		   (file (file-truename file)))
	       (or (string= root file)
		   (string-prefix-p (file-name-as-directory root) file))))))
    (rg-edit--setup-buffer rg-buffer)
    (cd work-dir)
    (apply #'start-process "rg-edit"
	   rg-buffer
	   rg-edit-executable
	   "-e" regexp
	   "-E" "emacsclient"
	   "--dump-on-error"
	   "--output-size-limit=100m"
	   dir-name
	   (split-string-shell-command (string-trim extra-args)))))

(defun rg-edit--get-path (path buffer-file)
  "Get the search path for rg-edit, using PATH or buffer file location."
  (or path
      (if buffer-file
	  (file-name-directory buffer-file)
	default-directory)))

(defun rg-edit--get-buffer-path (path buffer-file)
  "Get the search path for rg-edit, using PATH or buffer file location."
  (or path
      buffer-file
      default-directory))

(defun rg-edit--get-git-path (path buffer-file)
  "Get the git repository root as search path for rg-edit, using PATH or buffer file location."
  (or path
      (if buffer-file
	  (let ((git-root (locate-dominating-file buffer-file ".git")))
	    (if git-root
		(file-name-directory git-root)
	      (file-name-directory buffer-file)))
	default-directory)))

(defun rg-edit--invoke (regexp path extra-args get-path-fn refine-path)
  "Invoke rg-edit with REGEXP, PATH, EXTRA-ARGS using GET-PATH-FN to determine the path."
  (rg-edit--check-server)
  (rg-edit--warn-if-auto-revert-disabled)
  (let ((search-regexp (or regexp
			   (if (use-region-p)
			       (buffer-substring-no-properties (region-beginning) (region-end))
			     (or (current-word) "")))))
    (let ((search-regexp (read-string "Regexp: " search-regexp 'rg-edit--history-regexp))
	  (buffer-file (buffer-file-name)))
      (unless (and (stringp search-regexp)
		   (> (length search-regexp) 0))
	(user-error "No regexp provided"))
      (let ((search-path (funcall get-path-fn path buffer-file)))
	(let ((search-path (expand-file-name (if (or refine-path (null buffer-file))
						 (read-directory-name "Path: " search-path)
					       search-path)))
	      (extra-args (rg-edit--collect-extra-args extra-args)))
	  (rg-edit--run-command search-regexp search-path extra-args))))))

(defun rg-edit ()
  "Invoke rg-edit with the path in the current directory."
  (interactive)
  (rg-edit--invoke nil nil nil #'rg-edit--get-path t))

(defun rg-edit-buffer ()
  "Invoke rg-edit with the path in the current buffer."
  (interactive)
  (rg-edit--invoke nil nil nil #'rg-edit--get-buffer-path nil))

(defun rg-edit-git-conflicts ()
  "Invoke rg-edit-git with regex and extra-args preset to edit git conflicts."
  (interactive)
  (rg-edit--invoke "(?s)^<<<<<<<+ .*?^\\|\\|\\|\\|\\|\\|\\|+ .*?^>>>>>>>+ " nil "-U -C10" #'rg-edit--get-git-path nil))

(defun rg-edit-git (&optional arg)
  "Invoke rg-edit-git with the search path set in the git root.

ARG is the numeric prefix argument:
- no prefix (1): invoke rg-edit with the search path set in the git root.
- C-0 (0): invoke `rg-edit' instead.
- C-- (-1): invoke `rg-edit-buffer' instead.
- C-u (4): invoke `rg-edit-git-conflicts' instead."
  (interactive "p")
  (let ((arg (prefix-numeric-value arg)))
    (cond
     ((= arg 1) (rg-edit--invoke nil nil nil #'rg-edit--get-git-path nil))
     ((= arg 0) (rg-edit))
     ((= arg -1) (rg-edit-buffer))
     ((= arg 4) (rg-edit-git-conflicts))
     (t (user-error "Unsupported prefix argument: %s" arg)))))

(defun rg-edit--warn-if-auto-revert-disabled ()
  "Warn if automatic file revert is not enabled."
  (unless (bound-and-true-p global-auto-revert-mode)
    (display-warning 'rg-edit
		     "Automatic file revert is not enabled. Consider enabling it with `M-x global-auto-revert-mode`."
		    :warning)))

(defun rg-edit--gptel-rewrite ()
  (when-let* (((boundp 'gptel-version))
              (file (buffer-file-name))
              ((string-match-p "\\.rg-edit\\'" file)))
    rg-edit-gptel-system-message))
(add-hook 'gptel-rewrite-directives-hook #'rg-edit--gptel-rewrite)

(defun rg-edit--setup-gptel-directives ()
  "Set up gptel directives for rg-edit."
  (when (boundp 'gptel-directives)
    (setf (alist-get 'rg-edit gptel-directives)
          rg-edit-gptel-system-message)))

(defun rg-edit--setup-gptel--rewrite-directive ()
  ;; workaround for gptel issue in pull request #1095
  ;; fixed in 129032fca88f29c20343e973c98fa17db3000405 and
  ;; the following commit f4344b8a7950fd6b969b32f84f0fe427a9bc925b
  ;; introduced gptel-version
  (unless (boundp 'gptel-version)
    (setq-local gptel--rewrite-directive
		rg-edit-gptel-system-message)))

(defun rg-edit--kill-buffer-hook ()
  "Interrupt any in-flight gptel-send request when the buffer is closed."
  (when (fboundp 'gptel-abort)
    (gptel-abort (current-buffer))))

(defvar-local rg-edit--gbnf-content nil)

(defun rg-edit--gbnf ()
  "Read the .gbnf file and inject its contents into the JSON as the 'grammar' field."
  (when-let* (((rg-edit--gptel-gbnf-enabled-p))
              (buffer-file (buffer-file-name))
              (gbnf-path (concat buffer-file ".gbnf"))
              ((file-exists-p gbnf-path))
              (content (with-temp-buffer
                         (insert-file-contents gbnf-path)
                         (buffer-string))))
    (add-hook 'gptel-prompt-transform-functions #'rg-edit--gptel-set-gbnf)
    (setq-local rg-edit--gbnf-content content)))

(defun rg-edit--gptel-set-gbnf (fsm)
  "Set the grammar in the request if the model supports GBNF or EBNF."
  (when-let* (((fboundp 'gptel--model-capable-p))
              (buf (plist-get (gptel-fsm-info fsm) :buffer))
              (content (with-current-buffer buf
                         (bound-and-true-p rg-edit--gbnf-content))))
    (cond
     ((gptel--model-capable-p 'gbnf)
      (setq-local gptel--request-params
                  (plist-put (copy-sequence gptel--request-params) :grammar content)))
     ((gptel--model-capable-p 'ebnf)
      (setq-local gptel--request-params
                  (plist-put (copy-sequence gptel--request-params) :structured_outputs
                             (list :grammar content)))))))

(defun rg-edit--commit ()
  "Commit changes made in the rg-edit buffer."
  (interactive)
  (save-buffer)
  (kill-buffer))

(defun rg-edit--abort ()
  "Abort changes made in the rg-edit buffer."
  (interactive)
  (erase-buffer)
  (rg-edit--commit))

(defvar rg-edit-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-c") #'rg-edit--commit)
    (define-key map (kbd "C-c C-k") #'rg-edit--abort)
    map)
  "Keymap for `rg-edit-mode'.")

;;;###autoload
(define-derived-mode rg-edit-mode prog-mode "rg-edit"
  "Major mode for editing rg-edit temporary files.

\\{rg-edit-mode-map}"
  :group 'rg-edit
  (let ((rg-buffer (get-buffer "*rg-edit*")))
    (when rg-buffer
      (with-current-buffer rg-buffer
        (bury-buffer))))
  (rg-edit--setup-gptel-directives)
  (rg-edit--setup-gptel--rewrite-directive)
  (add-hook 'kill-buffer-hook #'rg-edit--kill-buffer-hook nil t)
  (rg-edit--gbnf)
  (when rg-edit-auto-mark-whole-buffer
    (mark-whole-buffer))
  (setq-local server-client-instructions nil)
  (message "When done C-c C-c to commit, C-c C-k to abort or C-x # to manually close the session"))

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.rg-edit\\'" . rg-edit-mode))

(provide 'rg-edit)

;;; rg-edit.el ends here
