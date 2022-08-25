;;; flymake-prototool.el --- prototool backend for flymake -*- lexical-binding: t; -*-

;; Copyright (C) 2020 Damien Merenne <dam@cosinux.org>

;; Author: Damien Merenne <dam@cosinux.org>
;; URL: https://github.com/purcell/flymake-ruby
;; Package-Version: 0
;; Package-Requires: ((flymake-easy "0.1"))

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;;

;;; Code:

(defvar-local flymake-prototool-proc nil)
(defvar-local flymake-protoc-proc nil)

(defun flymake-prototool-sentinel (source report-fn temp-dir original-proc proc _event)
  "Reporte flymake error from PROC for SOURCE buffer with REPORT-FN."
  (when (eq 'exit (process-status proc))
    (unwind-protect
        (if (with-current-buffer source (eq proc (symbol-value original-proc)))
            (with-current-buffer (process-buffer proc)
              (goto-char (point-min))
              (cl-loop
               while (search-forward-regexp "^\\(.*\.proto\\):\\([0-9]+\\):\\([0-9]+\\): *\\(.*\\)$"
                                            nil t)
               for msg =
               (match-string 4)
               for
               (beg . end)
               =
               (flymake-diag-region
                source
                (string-to-number (match-string 2))
                (string-to-number (match-string 3)))
               for type = :error
               collect
               (flymake-make-diagnostic source beg end type msg)
               into diags
               finally
               (funcall report-fn diags)))
          (flymake-log :warning "Canceling obsolete check %s" proc))
      ;; Cleanup the temporary buffer used to hold the
      ;; check's output.
      ;;
      (kill-buffer (process-buffer proc))
      (when temp-dir (delete-directory temp-dir t)))))

(defun flymake-prototool (report-fn &rest _args)
  (when (process-live-p flymake-prototool-proc) (kill-process flymake-prototool-proc))
  (let* ((executable (executable-find "prototool"))
         (source (current-buffer))
         (output-buffer (get-buffer-create "*flymake-prototool*")))
    (save-restriction
      (widen)
      (with-current-buffer output-buffer (erase-buffer))
      (setq
       flymake-prototool-proc
       (make-process
        :name "flymake-prototool" :noquery t :connection-type 'pipe
        :buffer output-buffer
        :command `(,executable "lint" ,(buffer-file-name))
        :sentinel (apply-partially #'flymake-prototool-sentinel source report-fn nil 'flymake-prototool-proc))))))

(defun flymake-protoc (report-fn &rest _args)
  (when (process-live-p flymake-protoc-proc) (kill-process flymake-protoc-proc))
  (let* ((executable (executable-find "protoc"))
         (source (current-buffer))
         (output-buffer (get-buffer-create "*flymake-protoc*"))
         (path (expand-file-name (locate-dominating-file (buffer-file-name) "prototool.yaml")))
         (temp-dir (make-temp-file "flymake-" t)))
    (save-restriction
      (widen)
      (with-current-buffer output-buffer (erase-buffer))
      (setq
       flymake-protoc-proc
       (make-process
        :name "flymake-protoc" :noquery t :connection-type 'pipe
        :buffer output-buffer
        :command (list executable (format "-I%s" path) (format "--java_out=%s" temp-dir) (buffer-file-name))
        :sentinel (apply-partially #'flymake-prototool-sentinel source report-fn temp-dir 'flymake-protoc-proc))))))

;;;###autoload
(defun flymake-prototool-load ()
  "Configure flymake mode to check the current buffer's prototool syntax."
  (interactive)
  (setq-local flymake-diagnostic-functions nil)
  (add-hook 'flymake-diagnostic-functions #'flymake-prototool nil t)
  (add-hook 'flymake-diagnostic-functions #'flymake-protoc nil t)
  (flymake-mode))

(provide 'flymake-prototool)

;;; flymake-prototool.el ends here
