;;; ref-man.el --- Manage bibliographic references and associated documents in  emacs. Integrates with org-mode to fetch, retrieve and manage the documents and metadata. ;;; -*- lexical-binding: t; -*-

;; Copyright (C) 2018,2019,2020
;; Akshay Badola

;; Author:	Akshay Badola <akshay.badola.cs@gmail.com>
;; Maintainer:	Akshay Badola <akshay.badola.cs@gmail.com>
;; Time-stamp:	<Wednesday 24 June 2020 09:16:15 AM IST>
;; Keywords:	pdfs, references, bibtex, org-mode, eww
;; Version:     0.3.1
;; Package-Requires: ((a "0.1.1") (async "1.9.4") (org "9.1.9") (biblio-core "0.2.1") (gscholar-bibtex "0.3.1") (websocket "1.12") (dash "2.17.0") (dash-functional "1.2.0") (bind-key "2.4") (org-ref "1.1.1"))

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
;; TODO

;;; Code:

;; TODO: Should make ref-man minor mode
;; TODO: Have to set debug levels. The info is way too much

(defcustom ref-man-sp-forward-remote-port nil
  "Whether to forward port from a remote ssh server."
  :type 'string
  :group 'ref-man)

(defcustom ref-man-science-parse-remote-host "localhost"
  "Hostname or address where the science parse server is running."
  :type 'string
  :group 'ref-man)

(defcustom ref-man-science-parse-server-port 8080
  "Server port on which to communicate with science parse server."
  :type 'integer
  :group 'ref-man)

(defcustom ref-man-science-parse-jar-file nil
  "Jar file which will launch the Science Parse Server.
This should be compiled from source.
See URL `https://github.com/allenai/science-parse' for details"
  :type 'file
  :group 'ref-man)

(defcustom ref-man-use-chrome-for-search nil
  "Whether chromium should be used for searching instead of eww"
  :type 'boolean
  :group 'ref-man)

(defconst ref-man-home-dir (file-name-directory load-file-name)
  "Home or install directory for `ref-man'.")

(defconst ref-man-version "0.3.1"
  "`ref-man' version number.")

(require 'ref-man-core)
(require 'ref-man-chrome)
(require 'ref-man-remote)

(unless (ref-man-python-process-running)
  ; (ref-man-chrome-init nil t)                 ; start chromium headless first
  (ref-man-start-python-server))

(ref-man-remote-load-public-links-cache)
;; FIXME: This throws an error if python-server is not running
;; (ref-man-remote-update-links-cache)

(defun ref-man-science-parse-server-running-p (&optional show-msg)
  (let ((port ref-man-science-parse-server-port))
    (if (string-match-p "Usage"
                        (shell-command-to-string (format "curl -s localhost:%d" port)))
        (progn (when show-msg
                 (message "[ref-man] Science Parse server is running"))
               t)
      (message "[ref-man] ERROR! Check connections")
      nil)))

(defun ref-man-science-parse-try-forward-remote-ssh-port (&optional show-msg)
  (let ((host ref-man-sp-forward-remote-port)
        (port ref-man-science-parse-server-port))
    (unless (and (string-empty-p host)
                 (string-match-p host (shell-command-to-string  "ps -ef | grep ssh")))
      (async-start-process "science-parse" "ssh" nil "-N" "-L"
                           (format  "%d:localhost:%d" port port) host)
      (ref-man-science-parse-server-running-p show-msg))))

(defun ref-man-science-parse-local-server-running-p (&optional show-msg)
  "Check if the Science Parse server running.
Return 'external if server is running but outside Emacs and
'internal if running inside Emacs,  nil otherwise."
  (let* ((java-proc (string-match-p "science-parse"
                                   (shell-command-to-string  "ps -ef | grep java")))
        (buf-proc (get-buffer-process "*science-parse*"))
        (proc (cond ((and java-proc (not buf-proc))
               'external)
              ((and java-proc buf-proc)
               'internal)
              (t nil))))
    (when proc
      (if (string-match-p "Usage"
                          (shell-command-to-string
                           (format "curl -s localhost:%d" ref-man-science-parse-server-port)))
          (progn (when show-msg
                   (message "[ref-man] Established connection to server successfully"))
                 proc)
        (message "[ref-man] Waiting for server to start up") 'waiting))))

(defun ref-man-kill-science-parse-process ()
  "Kill the Science Parse process."
  (interactive)
  (signal-process (get-buffer "*science-parse*") 15))

(defun ref-man-try-start-local-science-parse-server ()
  "Try to start the Science Parse server."
  (interactive)
  (let* ((status (ref-man-science-parse-local-server-running-p))
         (java (shell-command-to-string "which java"))
         (has-java (not (string-match-p "no java" java))))
    (if status status
      (if has-java
          (if (and ref-man-science-parse-jar-file ref-man-science-parse-server-port)
              (if (y-or-n-p-with-timeout "[ref-man] Science Parse Server not runing. Start it? " 3 nil)
                  (progn
                    (unless (string-match-p "science-parse" (shell-command-to-string  "ps -ef | grep java"))
                      (start-process "science-parse" "*science-parse*"
                                     "java" "-Xmx6g" "-jar" ref-man-science-parse-jar-file)
                      (message "[ref-man] Trying to start server. This may take some time"))
                    (ref-man-science-parse-server-running-p t))
                (message "[ref-man] Not starting Science Parse Server"))
            (message "[ref-man] Science Parse Jar File not given"))
        (message "[ref-man] java not found")))))
(defalias 'ref-man-start-local-science-parse-server 'ref-man-try-start-local-science-parse-server)
(defalias 'ref-man-try-start-science-parse-server 'ref-man-try-start-local-science-parse-server)

(provide 'ref-man)

;;; ref-man.el ends here
