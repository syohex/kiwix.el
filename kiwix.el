;;; kiwix.el --- Searching offline Wikipedia through Kiwix.
;;; -*- coding: utf-8 -*-

;; Author: stardiviner <numbchild@gmail.com>
;; Maintainer: stardiviner <numbchild@gmail.com>
;; Keywords: kiwix wikipedia
;; URL: https://github.com/stardiviner/kiwix.el
;; Created: 23th July 2016
;; Version: 1.0.0
;; Package-Requires: ((emacs "24.4") (cl-lib "0.5") (request "0.3.0"))

;;; Commentary:

;;; This currently only works for Linux, not tested for Mac OS X and Windows.

;;; Kiwix installation
;;
;; http://www.kiwix.org

;;; Config:
;;
;; (use-package kiwix
;;   :ensure t
;;   :after org
;;   :commands (kiwix-launch-server kiwix-at-point-interactive)
;;   :bind (:map document-prefix ("w" . kiwix-at-point-interactive))
;;   :init (setq kiwix-server-use-docker t
;;               kiwix-server-port 8080
;;               kiwix-default-library "wikipedia_zh_all_2015-11.zim"))

;;; Usage:
;;
;; 1. [M-x kiwix-launch-server] to launch Kiwix server.
;; 2. [M-x kiwix-at-point] to search the word under point or the region selected string.

;;; Code:


(require 'cl-lib)
(require 'request)
(if (featurep 'ivy) (require 'ivy))

(defgroup kiwix-mode nil
  "Kiwix customization options."
  :group 'kiwix-mode)

(defcustom kiwix-server-use-docker nil
  "Using Docker container for kiwix-serve or not?"
  :type 'boolean
  :safe #'booleanp
  :group 'kiwix-mode)

(defcustom kiwix-server-port 8000
  "Specify default kiwix-serve server port."
  :type 'number
  :safe #'numberp
  :group 'kiwix-mode)

(defcustom kiwix-server-url (format "http://127.0.0.1:%s" kiwix-server-port)
  "Specify Kiwix server URL."
  :type 'string
  :group 'kiwix-mode)

(defcustom kiwix-server-command
  (cond
   ((string-equal system-type "gnu/linux")
    "/usr/lib/kiwix/bin/kiwix-serve ")
   ((string-equal system-type "darwin")
    (warn "You need to specify Mac OS X Kiwix path. And send a PR to my repo."))
   ((string-equal system-type "windows-nt")
    (warn "You need to specify Windows Kiwix path. And send a PR to my repo.")))
  "Specify kiwix server command."
  :type 'string
  :group 'kiwix-mode)

(defun kiwix-dir-detect ()
  "Detect Kiwix profile directory exist."
  (let ((kiwix-dir (concat (getenv "HOME") "/.www.kiwix.org/kiwix")))
    (if (file-accessible-directory-p kiwix-dir)
        kiwix-dir
      (warn "ERROR: Kiwix profile directory \".www.kiwix.org/kiwix\" is not accessible."))))

(defcustom kiwix-default-data-profile-name
  (when (kiwix-dir-detect)
    (car (directory-files
          (concat (getenv "HOME") "/.www.kiwix.org/kiwix") nil ".*\\.default")))
  "Specify the default Kiwix data profile path."
  :type 'string
  :group 'kiwix-mode)

(defcustom kiwix-default-data-path
  (when (kiwix-dir-detect)
    (concat (getenv "HOME") "/.www.kiwix.org/kiwix/" kiwix-default-data-profile-name))
  "Specify the default Kiwix data path."
  :type 'string
  :safe #'stringp
  :group 'kiwix-mode)

(defcustom kiwix-default-library-path (file-name-directory
                                       (concat kiwix-default-data-path "/data/library/library.xml"))
  "Kiwix libraries path."
  :type 'string
  :safe #'stringp
  :group 'kiwix-mode)

(defcustom kiwix-default-completing-read 'ivy
  "Kiwix default completion frontend. Currently Ivy ('ivy) and Helm ('helm) both supported."
  :type 'symbol
  :safe #'symbolp
  :group 'kiwix-mode)

(defcustom kiwix-default-browser-function browse-url-browser-function
  "Set default browser for open kiwix query result URL."
  :type '(choice
          (const :tag "browse-url default function" browse-url-default-browser)
          (const :tag "EWW" eww-browse-url)
          (const :tag "EAF web browser" eaf-open-browser)
          (const :tag "Firefox web browser" browse-url-firefox)
          (const :tag "Google Chrome web browser" browse-url-chrome)
          (const :tag "Conkeror web browser" browse-url-conkeror)
          (const :tag "xwidget browser" xwidget-webkit-browse-url))
  :safe #'symbolp
  :group 'kiwix-mode)

;;;###autoload
(defun kiwix--get-library-name (file)
  "Extract library name from library file."
  (replace-regexp-in-string "\.zim" "" file))

(defun kiwix-get-libraries ()
  "Check out all available Kiwix libraries."
  (when (kiwix-dir-detect)
    (mapcar #'kiwix--get-library-name
            (directory-files kiwix-default-library-path nil ".*\.zim"))))

(defvar kiwix-libraries (kiwix-get-libraries)
  "A list of Kiwix libraries.")

(defun kiwix-libraries-refresh ()
  "A helper function to refresh available Kiwx libraries."
  (setq kiwix-libraries (kiwix-get-libraries)))

(defvar kiwix--selected-library nil
  "Global variable of currently select library used in anonymous function.
Like in function `kiwix-ajax-search-hints'.")

;; - examples:
;; - "wikipedia_en_all" - "wikipedia_en_all_2016-02"
;; - "wikipedia_zh_all" - "wikipedia_zh_all_2015-17"
;; - "wiktionary_en_all" - "wiktionary_en_all_2015-17"
;; - "wiktionary_zh_all" - "wiktionary_zh_all_2015-17"
;; - "wikipedia_en_medicine" - "wikipedia_en_medicine_2015-17"

(defun kiwix-select-library (&optional filter)
  "Select Kiwix library name."
  (kiwix-libraries-refresh)
  (completing-read "Kiwix library: " kiwix-libraries nil t filter))

(defcustom kiwix-default-library "wikipedia_en_all.zim"
  "The default kiwix library when library fragment in link not specified."
  :type 'string
  :safe #'stringp
  :group 'kiwix-mode)

(defcustom kiwix-search-interactively t
  "`kiwix-at-point' search interactively."
  :type 'boolean
  :safe #'booleanp
  :group 'kiwix-mode)

(defcustom kiwix-mode-prefix nil
  "Specify kiwix-mode keybinding prefix before loading."
  :type 'kbd
  :group 'kiwix-mode)

;; update kiwix server url and port
(defun kiwix-server-url-update ()
  "Update `kiwix-server-url' everytime used. In case setting port is lated."
  (setq kiwix-server-url (format "http://127.0.0.1:%s" kiwix-server-port)))

;; launch Kiwix server
;;;###autoload
(defun kiwix-launch-server ()
  "Launch Kiwix server."
  (interactive)
  (let ((library-option "--library ")
        (port (concat "--port=" kiwix-server-port " "))
        (daemon "--daemon ")
        (library-path kiwix-default-library-path))
    (if kiwix-server-use-docker
        (async-shell-command
         (concat "docker container run -d "
                 "--name kiwix-serve "
                 "-v " (file-name-directory library-path) ":" "/data "
                 "kiwix/kiwix-serve "
                 "--library library.xml"))
      (async-shell-command
       (concat kiwix-server-command
               library-option port daemon (shell-quote-argument library-path))))))

(defun kiwix-capitalize-first (string)
  "Only capitalize the first word of STRING."
  (concat (string (upcase (aref string 0))) (substring string 1)))

(defun kiwix-query (query &optional selected-library)
  "Search `QUERY' in `LIBRARY' with Kiwix."
  (kiwix-server-url-update)
  (let* ((library (or selected-library (kiwix--get-library-name kiwix-default-library)))
         (url (concat kiwix-server-url "/search?content=" library "&pattern=" (url-hexify-string query)))
         (browse-url-browser-function kiwix-default-browser-function))
    (browse-url url)))

(defun kiwix-docker-check ()
  "Make sure Docker image 'kiwix/kiwix-server' is available."
  (let ((docker-image (replace-regexp-in-string
                       "\n" ""
                       (shell-command-to-string
                        "docker image ls kiwix/kiwix-serve | sed -n '2p' | cut -d ' ' -f 1"))))
    (string-equal docker-image "kiwix/kiwix-serve")))

(defvar kiwix-server-available? nil
  "The kiwix-server current available?")

(defun kiwix-ping-server ()
  "Ping Kiwix server to set `kiwix-server-available?' global state variable."
  (if kiwix-server-use-docker
      (kiwix-docker-check)
    (async-shell-command "docker pull kiwix/kiwix-serve"))
  (let ((inhibit-message t))
    (kiwix-server-url-update)
    (request kiwix-server-url
      :type "GET"
      :sync t
      :parser (lambda () (libxml-parse-html-region (point-min) (point-max)))
      :error (cl-function
              (lambda (&rest args &key error-thrown &allow-other-keys)
                (setq kiwix-server-available? nil)
                (when (string-equal (cdr error-thrown) "exited abnormally with code 7\n")
                  (warn "kiwix.el failed to connect to host. exited abnormally with status code: 7."))))
      :success (cl-function
                (lambda (&key data &allow-other-keys)
                  (setq kiwix-server-available? t)))
      :status-code '((404 . (lambda (&rest _) (message (format "Endpoint %s does not exist." url))))
                     (500 . (lambda (&rest _) (message (format "Error from  %s." url))))))))

(defun kiwix-ajax-search-hints (input &optional selected-library)
  "Instantly AJAX request to get available Kiwix entry keywords
list and return a list result."
  (kiwix-server-url-update)
  (kiwix-ping-server)
  (when (and input kiwix-server-available?)
    (let* ((library (or selected-library
                        (kiwix--get-library-name (or kiwix--selected-library
                                                     kiwix-default-library))))
           (ajax-api (format "%s/suggest?content=%s&term="
                             kiwix-server-url
                             library))
           (ajax-url (concat ajax-api input))
           (data (request-response-data
                  (let ((inhibit-message t))
                    (request ajax-url
                      :type "GET"
                      :sync t
                      :headers '(("Content-Type" . "application/json"))
                      :parser #'json-read
                      :success (function*
                                (lambda (&key data &allow-other-keys)
                                  data)))))))
      (if (vectorp data)
          (mapcar 'cdar data)))))

;;;###autoload
(defun kiwix-at-point (&optional interactively)
  "Search for the symbol at point with `kiwix-query'.

Or When prefix argument `INTERACTIVELY' specified, then prompt
for query string and library interactively."
  (interactive "P")
  (unless (kiwix-ping-server)
    (kiwix-launch-server))
  (if kiwix-server-available?
      (progn
        (setq kiwix--selected-library (kiwix-select-library))
        (let* ((library kiwix--selected-library)
               (query (case kiwix-default-completing-read
                        ('helm
                         (helm :source (helm-build-async-source "kiwix-helm-search-hints"
                                         :candidates-process
                                         `(lambda (input)
                                            (apply 'kiwix-ajax-search-hints
                                                   input `(,kiwix--selected-library))))
                               :input (word-at-point)
                               :buffer "*helm kiwix completion candidates*"))
                        ('ivy
                         (ivy-read "Kiwix related entries: "
                                   `(lambda (input)
                                      (apply 'kiwix-ajax-search-hints
                                             input `(,kiwix--selected-library)))
                                   :predicate nil
                                   :require-match nil
                                   :initial-input (if mark-active
                                                      (buffer-substring
                                                       (region-beginning) (region-end))
                                                    (thing-at-point 'symbol))
                                   :preselect nil
                                   :def nil
                                   :history nil
                                   :keymap nil
                                   :update-fn 'auto
                                   :sort t
                                   :dynamic-collection t
                                   :caller 'ivy-done)))))
          (message (format "library: %s, query: %s" library query))
          (if (or (null library)
                  (string-empty-p library)
                  (null query)
                  (string-empty-p query))
              (error "Your query is invalid")
            (kiwix-query query library))))
    (warn "kiwix-serve is not available, please start it at first."))
  (setq kiwix-server-available? nil))

;;;###autoload
(defun kiwix-at-point-interactive ()
  "Interactively input to query with kiwix."
  (interactive)
  (let ((current-prefix-arg t))
    (call-interactively 'kiwix-at-point)))

;;===============================================================================

(defun kiwix-mode-enable ()
  "Enable kiwix-mode."
  )

(defun kiwix-mode-disable ()
  "Disable kiwix-mode."
  )

(defvar kiwix-mode-map
  (let ((map (make-sparse-keymap)))
    map)
  "kiwix-mode map.")

;;;###autoload
(define-minor-mode kiwix-mode
  "Kiwix global minor mode for searching Kiwix serve."
  :require 'kiwix-mode
  :init-value nil
  :lighter " Kiwix"
  :group 'kiwix-mode
  :keymap kiwix-mode-map
  (if kiwix-mode (kiwix-mode-enable) (kiwix-mode-disable)))

;;;###autoload
(define-global-minor-mode global-kiwix-mode kiwix-mode
  kiwix-mode)


(provide 'kiwix)

;;; kiwix.el ends here
