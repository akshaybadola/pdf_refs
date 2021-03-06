;;; ref-man-py.el --- Module for managing the python process. ;;; -*- lexical-binding: t; -*-

;; Copyright (C) 2018,2019,2020,2021
;; Akshay Badola

;; Author:	Akshay Badola <akshay.badola.cs@gmail.com>
;; Maintainer:	Akshay Badola <akshay.badola.cs@gmail.com>
;; Time-stamp:	<Tuesday 06 July 2021 05:24:22 AM IST>
;; Keywords:	pdfs, references, bibtex, org, eww

;; This file is *NOT* part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify it
;; under the terms of the GNU General Public License as published by the Free
;; Software Foundation; either version 3, or (at your option) any later
;; version.

;; This program is distributed in the hope that it will be useful, but WITHOUT
;; ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
;; FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
;; more details.

;; You should have received a copy of the GNU General Public License along with
;; GNU Emacs; see the file COPYING.  If not, write to the Free Software
;; Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.


;;; Commentary:
;;
;; Functions for managing python virtualenv and processes for `ref-man'.  Has
;; functions to check if a virtualenv exists for a given path, if correct python
;; version is installed in the system and starting and stopping python
;; processes.

;;; Code:

(defcustom ref-man-python-server-port-start 9999
  "Server port on which to communicate with python server."
  :type 'integer
  :group 'ref-man)

(defcustom ref-man-python-server-port 9999
  "Port on which to communicate with python server."
  :type 'integer
  :group 'ref-man)

(defcustom ref-man-python-data-dir (expand-file-name "~/.ref-man/data/")
  "Server port on which to communicate with python server."
  :type 'directory
  :group 'ref-man)

(defcustom ref-man-proxy-port nil
  "Whether to use http proxy for all python requests.
If this is non-nil then the all the requests by the python server
go through this http proxy at localhost, specified by this port."
  :type 'integer
  :group 'ref-man)

(defcustom ref-man-chrome-debug-script ""
  "Path to the chrome debugger javascript file.
The file contains code to get the Semantic Scholar Search
params.  As they can change, we need to update them once the
server starts.  Requires some kind of chrome(ium) to be installed
on the system."
  :type 'file
  :group 'ref-man)


;; NOTE: External variables
(defvar ref-man-home-dir)               ; from `ref-man'
(defvar ref-man-pdf-proxy-port)         ; from `ref-man-url'
(defvar ref-man-documents-dir)          ; from `ref-man-files'
(defvar ref-man-remote-documents-dir)   ; from `ref-man-remote'
(defvar ref-man-public-links-cache-file) ; from `ref-man-remote'

;; NOTE: Internal variables
(defvar ref-man-py-external-process-pid nil)

(defun ref-man-py-create-venv (path)
  "Create a new `ref-man' virtual env in directory PATH."
  (if (and (string-match-p "no.*module.*virtualenv.*"
                           (shell-command-to-string
                            (format "python3 -m virtualenv -p python3 %s" path)))
           (string-match-p "no.*module.*virtualenv.*"
                           (shell-command-to-string
                            (format "/usr/bin/python3 -m virtualenv -p python3 %s" path))))
      nil (message "Create venv in %s" path)))

(defun ref-man-py-no-mod-in-venv-p (python)
  "Check if `ref-man' python environment has py module installed.
PYTHON is the python executable for that virtualenv."
  (string-match-p "no.*module.*ref.*"
                  (shell-command-to-string
                   (format "%s -m ref_man --version" python))))

(defun ref-man-py-installed-mod-version (python)
  "Return version for installed python module.
PYTHON is the path for python executable."
  (shell-command-to-string
   (format "%s -m ref_man --version" python)))

(defun ref-man-py-file-mod-version ()
  "Return the version of python module in file `const.py'."
  (let* ((const-file (path-join ref-man-home-dir "ref_man" "const.py"))
        (buf (find-file-noselect const-file)))
    (with-current-buffer buf
      (goto-char (point-min))
      (re-search-forward "__version__ = \"\\(.+\\)\"")
      (substring-no-properties (match-string 1)))))

(defun ref-man-py-env-needs-update-p ()
  "Check if `ref-man' module needs to be updated."
  (not (equal (ref-man-py-file-mod-version)
              (string-trim (replace-regexp-in-string
                            "ref-man.*? version \\(.*\\)" "\\1"
                            (ref-man-py-installed-mod-version
                             (path-join ref-man-home-dir "env" "bin" "python")))))))

(defun ref-man-py-env-uninstall-module (env)
  "Install the `ref-man' module in virtualenv ENV."
  (shell-command
   (concat "source " (path-join env "bin" "activate") " && pip uninstall ref-man")
   "*ref-man-uninstall-cmd*" "*ref-man-uninstall-cmd*"))

(defun ref-man-py-env-install-module (env)
  "Uninstall the `ref-man' module from virtualenv ENV."
  (shell-command
   (concat "source " (path-join env "bin" "activate") " && "
           (format "cd %s && python -m pip install -U ."
                   ref-man-home-dir))
   "*ref-man-install-cmd*" "*ref-man-install-cmd*"))

;; TODO: Check python3 version > 3.6.9
(defun ref-man-py-setup-env (&optional reinstall update)
  "Setup python virtualenv.
Optional non-nil REINSTALL removes the virtualenv and installs
everything again.  Optional non-nil UPDATE only updates the
`ref-man' python module.  The directory is relative to `ref-man'
install directory `ref-man-home-dir'.  With optional REINSTALL
non-nil clean the venv and install all dependencies again."
  (unless (executable-find "python3")
    (error "No python3 found in current paths.\n
If python3 is in some other path, add that path to the exec path"))
  (let ((env (path-join ref-man-home-dir "env")))
    (when (and reinstall (f-exists? env)
               (y-or-n-p (format "Clean and reinstall virtualenv %s? " env)))
      (f-delete env t))
    (unless (f-exists? env)
      (f-mkdir env)
      (unless (ref-man-py-create-venv env)
        (error "Could not install venv.\n
Make sure package 'virtualenv' exists in current python environment")))
    (let* ((env-has-python (f-exists? (path-join env "bin" "python3")))
           (python (and env-has-python
                        (path-join env "bin" "python3"))))
      (when (and (not python) (ref-man-py-create-venv env))
        (error "Could not install venv.\n
Make sure package 'virtualenv' exists in current python environment"))
      (let* ((env-has-no-ref-man (ref-man-py-no-mod-in-venv-p python))
             (need-update (or update (ref-man-py-env-needs-update-p))))
        (when (or need-update env-has-no-ref-man)
          (cond (need-update
                 (message "New version of ref-man. Updating existing ref-man-server in %s" env)
                 (ref-man-py-env-uninstall-module env))
                (env-has-no-ref-man
                 (message "ref-man-server not found. Installing in %s" env)))
          (ref-man-py-env-install-module env))
        (if (ref-man-py-installed-mod-version python)
            (message "%s found in %s" (ref-man--trim-whitespace
                                       (ref-man-py-installed-mod-version python))
                     env)
          (error "Could not install ref-man in %s" env))))))

;; TODO: Requests to python server should be dynamic according to whether I want
;;       to use proxy or not at that point
(defun ref-man-py-process-helper (data-dir port &optional
                                                proxy-port proxy-everything-port
                                                docs-dir)
  "Start the python server.
DATA-DIR is the server data directory.  PORT is the port to which
the server binds.

When called from `ref-man-py-start-server', DATA-DIR is set
to `ref-man-python-data-dir' and the port
`ref-man-python-server-port'.

Optional arguments PROXY-PORT, PROXY-EVERYTHING-PORT, DOCS-DIR
are specified for modularity and are set to `ref-man-proxy-port',
nil, `ref-man-python-data-dir' respectively by
`ref-man-py-start-server'."
  ;; NOTE: Hack so that process isn't returned
  (prog1
      (message (format "[ref-man] Starting python process on port: %s"
                       ref-man-python-server-port))
    (let ((python (path-join ref-man-home-dir "env" "bin" "python")))
      (condition-case nil
          (ref-man-py-setup-env))
      (let ((args (-filter #'identity (list (format "--data-dir=%s" data-dir)
                                            (format "--port=%s" port)
                                            (and ref-man-proxy-port "--proxy-everything")
                                            (and ref-man-proxy-port
                                                 (format "--proxy-everything-port=%s"
                                                         ref-man-proxy-port))
                                            (and ref-man-pdf-proxy-port
                                                 (format "--proxy-port=%s"
                                                         ref-man-pdf-proxy-port))
                                            (and ref-man-chrome-debug-script
                                                 (format "--chrome-debugger-path=%s"
                                                         ref-man-chrome-debug-script))
                                            (and ref-man-documents-dir
                                                 (format "--local-pdfs-dir=%s"
                                                         ref-man-documents-dir))
                                            (and ref-man-remote-documents-dir
                                                 (format "--remote-pdfs-dir=%s"
                                                         ref-man-remote-documents-dir))
                                            (and ref-man-public-links-cache-file
                                                 (format "--remote-links-cache=%s"
                                                         ref-man-public-links-cache-file))
                                            "--verbosity=debug"))))
        (message "Python process args are %s" args)
        (apply #'start-process "ref-man-python-server" "*ref-man-python-server*"
               python "-m" "ref_man" args)))))

(defun ref-man-py-stop-server ()
  "Stop the python server by sending a shutdown command.
This is sent via http and lets the server exit gracefully."
  (interactive)
  (let ((buf (url-retrieve-synchronously
              (format "http://localhost:%s/shutdown" ref-man-python-server-port))))
    (with-current-buffer buf
      (goto-char (point-min))
      (re-search-forward "\r?\n\r?\n")
      (message (buffer-substring-no-properties (point) (point-max))))))

(defun ref-man-py-kill-internal-process ()
  "Kill the internal python process process by sending SIGKILL."
  (signal-process (get-buffer "*ref-man-python-server*") 15))

(defun ref-man-py-kill-external-process ()
  "Kill the external python process process by sending SIGKILL."
  (signal-process ref-man-py-external-process-pid 15))

(defun ref-man-py-server-reachable-p ()
  "Check if python server is reachable."
  (condition-case nil
      (let ((buf (url-retrieve-synchronously
                  (format "http://localhost:%s/version" ref-man-python-server-port) t)))
        (when buf
          (string-match-p "ref-man python server"
                          (with-current-buffer buf (buffer-string)))))
    (error nil)))

(defun ref-man-py-process-running ()
  "Check if python server is running.
Returns 'external or 'internal according to where the process is
running if it's running else nil."
  (cond ((get-buffer-process "*ref-man-python-server*")
         (setq ref-man-py-external-process-pid nil)
         'internal)
        ((ref-man-py-external-process-p)
         'external)
        (t nil)))

(defun ref-man-py-server-running ()
  "Check if python server is already running."
  (let ((python-process (ref-man-py-process-running)))
    (when python-process
      (if (ref-man-py-server-reachable-p)
          python-process
        (if (eq python-process 'internal)
            'internal-error 'external-error)))))

(defun ref-man-py-external-process-p ()
  "Check for `server.py' python processes outside Emacs.
In case a process is found, `ref-man-python-server-port' is set
to the port of that process and
`ref-man-py-external-process-pid' is set to its pid."
  (let ((python-strings
         (split-string (shell-command-to-string "ps -ef | grep python | grep server") "\n")))
    (cl-loop for x in python-strings
             do
             (when (and (string-match-p "port" x) (string-match-p "data-dir" x))
               (setq ref-man-python-server-port
                     (string-to-number
                      (cadr (split-string
                             (car (split-string
                                   (substring x (string-match "port" x)))) "="))))
               (setq ref-man-py-external-process-pid (string-to-number (nth 1 (split-string x))))
               (cl-return t)))))

(defun ref-man-py-start-server ()
  "Start the python server, unless already running.

The server can be running outside Emacs also in which case
`ref-man-python-server-port' is set to port.

See accompanying `server.py' for the server details.  The API and
methods are still evolving but as of now it supports DBLP and
ArXiv.  The process if started opens a local port and can fetch
data in multiple threads from supported APIs before preprocessing
and consolidating.  It also maintains a local datastore."
  (interactive)
  ;; FIXME: for 'internal-error and 'external-error
  (if (ref-man-py-server-running)
      (message (format "Found existing process running on port: %s"
                       ref-man-python-server-port))
    (message "No existing python process found")
    (let ((port (find-open-port ref-man-python-server-port-start))
          (data-dir ref-man-python-data-dir))
      (setq ref-man-python-server-port port)
      (ref-man-py-process-helper data-dir port))))

(defun ref-man-py-restart-server ()
  "Restart the python server."
  (interactive)
  (cond ((or (eq 'internal (ref-man-py-server-running))
             (eq 'external (ref-man-py-server-running)))
         (ref-man-py-stop-server))
        ((eq 'internal-error (ref-man-py-server-running))
         (ref-man-py-kill-internal-process))
        ((eq 'external-error (ref-man-py-server-running))
         (ref-man-py-kill-external-process)))
  ;; FIXME: This runs before server shuts down
  (ref-man-py-start-server))

(provide 'ref-man-py)

;;; ref-man-py.el ends here
