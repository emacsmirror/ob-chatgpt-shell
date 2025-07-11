;;; ob-chatgpt-shell.el --- Org babel functions for ChatGPT evaluation -*- lexical-binding: t; -*-

;; Copyright (C) Alvaro Ramirez

;; Author: Alvaro Ramirez
;; URL: https://github.com/xenodium/ob-chatgpt-shell
;; Version: 2.0.1
;; Package-Requires: ((emacs "27.1") (chatgpt-shell "2.24.1"))

;;; License:

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;;; Commentary:

;; Run and get responses from ChatGPT blocks using org babel.
;;
;; Install with:
;;
;;   (require 'ob-chatgpt-shell)
;;   (ob-chatgpt-shell-setup)
;;
;; Usage:
;;
;;     #+begin_src chatgpt-shell
;;       Hello
;;     #+end_src

;;; Requirements:

;;; Code:
(require 'chatgpt-shell)
(require 'map)
(require 'ob)
(require 'org-element)

(defvar org-babel-default-header-args:chatgpt-shell '((:results . "output")
                                                      (:version . nil)
                                                      (:system . nil)
                                                      (:context . nil)
                                                      (:temperature . nil)
                                                      (:preflight . nil)
                                                      (:assistant-id . nil)
                                                      (:file-id . nil)
                                                      (:file . nil)
                                                      (:thread-id . nil)))

(cl-defun ob-chatgpt-shell--post-assistant (&key body params)
  "Post assistant query with BODY and PARAMS.

Assistant queries leverage cloud context using :assistant-id, :file-id,
and :thread-id."
  (unless body
    (error "Missing mandatory :body param"))
  (unless params
    (error "Missing mandatory :params param"))
  (when (map-elt params :version)
    (message "Can't use :version with either :assistant-id, :file-id, or :thread-id"))
  (when (map-elt params :system)
    (message "Can't use :system with either :assistant-id, :file-id, or :thread-id"))
  (when (map-elt params :context)
    (message "Can't use :context with either :assistant-id, :file-id, or :thread-id"))
  (when (map-elt params :temperature)
    (message "Can't use :temperature with either :assistant-id, :file-id, or :thread-id"))
  (when (map-elt params :preflight)
    (message "Can't use :preflight with either :assistant-id, :file-id, or :thread-id"))
  (ob-chatgpt-shell--query-file :prompt body
                                :file-id (map-elt params :file-id)
                                :file (map-elt params :file)
                                :assistant-id (map-elt params :assistant-id)
                                :thread-id (map-elt params :thread-id)))

(defun org-babel-execute:chatgpt-shell (body params)
  "Execute a block of ChatGPT prompt in BODY with org-babel header PARAMS.
This function is called by `org-babel-execute-src-block'"
  (message "executing ChatGPT source code block")
  (when (equal (map-elt params :version) "nil")
    (map-put! params :version nil))
  (when (equal (map-elt params :system) "nil")
    (map-put! params :system nil))
  (when (equal (map-elt params :context) "nil")
    (map-put! params :context nil))
  (when (equal (map-elt params :temperature) "nil")
    (map-put! params :temperature nil))
  (when (equal (map-elt params :preflight) "nil")
    (map-put! params :preflight nil))
  (when (equal (map-elt params :assistant-id) "nil")
    (map-put! params :assistant-id nil))
  (when (equal (map-elt params :file-id) "nil")
    (map-put! params :file-id nil))
  (when (equal (map-elt params :file) "nil")
    (map-put! params :file nil))
  (when (equal (map-elt params :thread-id) "nil")
    (map-put! params :thread-id nil))
  (if (ob-chatgpt-shell--assistant-post-p params)
      (ob-chatgpt-shell--post-assistant :body body
                                        :params params)
    (let* ((context (ob-chatgpt-shell--context :context-name (map-elt params :context)
                                               :prompt body))
           (system-prompt (when (and (map-elt params :system)
                                     (not (map-elt params :context)))
                            (map-elt params :system))))
      (if (map-elt params :preflight)
          (pp (chatgpt-shell--make-payload
               :context (map-elt context :context)
               :system-prompt (or system-prompt (map-elt context :system-prompt))
               :version (or (map-elt params :version)
                            (chatgpt-shell-model-version))
               :temperature (map-elt params :temperature)))
        (chatgpt-shell-post
         :context (if chatgpt-shell-include-local-file-link-content
                      (mapcar (lambda (item)
                                (cons (markdown-overlays-expand-local-links
                                       (car item))
                                      (cdr item)))
                              (map-elt context :context))
                    (map-elt context :context))
         :system-prompt (or system-prompt (map-elt context :system-prompt))
         :version (or (map-elt params :version)
                      (chatgpt-shell-model-version))
         :temperature (map-elt params :temperature))))))

(defun ob-chatgpt-shell--assistant-post-p (params)
  "Return non-nil if assistant usage is detected in PARAMS.

Assistant usage leverages cloud context."
  (or (map-elt params :assistant-id)
      (map-elt params :file-id)
      (map-elt params :file)
      (map-elt params :thread-id)))

(cl-defun ob-chatgpt-shell--context (&key context-name prompt)
  "Return the context (what was asked and responded).

This is used for matching previous src blocks.  If CONTEXT-NAME is provided
each src block have a :context arg with a value matching the CONTEXT-NAME.

PROMPT is acutomatically appended to the returned context."
  (let ((context '())
        (system-prompt))
    (when context-name
      (mapc
       (lambda (src-block)
         (when-let ((system (and (seq-empty-p context) ;; Add system only if first item.
                                 (or (map-elt (map-elt src-block 'parameters '()) :system)
                                     (map-elt org-babel-default-header-args:chatgpt-shell :system)))))
           (setq system-prompt system))
         (push
          (cons (map-elt src-block 'body)
                (map-elt src-block 'result))
          context))
       (ob-chatgpt-shell--relevant-source-blocks-before-current
        (if (equal context-name "t")
            nil ;; mean all blocks before
          context-name))))
    (list
     (cons :context (append
                     (nreverse context)
                     (when prompt
                       (list (cons prompt nil)))))
     (cons :system-prompt system-prompt))))

(defun ob-chatgpt-shell-setup ()
  "Set up babel ChatGPT support."
  (org-babel-do-load-languages 'org-babel-load-languages
                               (append org-babel-load-languages
                                       '((chatgpt-shell . t))))
  (add-to-list 'org-src-lang-modes '("chatgpt-shell" . text)))

(defun ob-chatgpt-shell--relevant-source-blocks-before-current (context-name)
  "Return all previous source blocks relative to the current block.

Including only those with a :context arg with a value matching CONTEXT-NAME.
If CONTEXT-NAME is nil then return all previous source blocks."
  (when-let ((current-block-pos (let ((element (org-element-context)))
                                  (when (eq (org-element-type element) 'src-block)
                                    (org-element-property :begin element)))))
    (seq-filter (lambda (src)
                  (and (string-equal (map-elt src 'language)
                                     "chatgpt-shell")
                       (or (not context-name)
                           (string-equal (map-elt (map-elt src 'parameters '()) :context)
                                         context-name))
                       (< (map-elt src 'start) current-block-pos)))
                (ob-chatgpt-shell--all-source-blocks))))

(defun ob-chatgpt-shell--all-source-blocks ()
  "Return all source blocks in buffer."
  (org-element-map (org-element-parse-buffer) '(src-block fixed-width)
    (lambda (element)
      (cond ((eq (org-element-type element) 'src-block)
             (list 'start (org-element-property :begin element)
                   'body (when (org-element-property :value element)
                           (string-trim (org-element-property :value element)))
                   'language (when (org-element-property :language element)
                               (string-trim (org-element-property :language element)))
                   'parameters (when (org-element-property :parameters element)
                                 (org-babel-parse-header-arguments
                                  (string-trim (org-element-property :parameters element))))
                   'result (save-restriction
                             (goto-char (org-element-property :begin element))
                             (when (org-babel-where-is-src-block-result)
                               (goto-char (org-babel-where-is-src-block-result))
                               (org-babel-read-result)))))))))

(cl-defun ob-chatgpt-shell--upload-file (&key purpose path)
  "Upload file at PATH and describe PURPOSE."
  (unless purpose
    (error "Missing mandatory :purpose param"))
  (unless path
    (error "Missing mandatory :path param"))
  (unless (file-exists-p path)
    (error "Path does not exist: %s" path))
  (unless (file-regular-p path)
    (error "Path is not a file: %s" path))
  (when-let ((result
              (shell-maker-make-http-request :async nil
                                             :url "https://api.openai.com/v1/files"
                                             :headers (chatgpt-shell-openai--make-headers)
                                             :fields `(,(format "purpose=%s" purpose)
                                                       ,(format "file=@%s" path))
                                             :filter (lambda (raw-response)
                                                       (if-let* ((parsed (shell-maker--json-parse-string raw-response))
                                                                 (response (or (let-alist parsed
                                                                                 .error.message)
                                                                               (let-alist parsed
                                                                                 .id))))
                                                           response
                                                         (error "Couldn't parse %s" raw-response)))))
             (success (map-elt result :success)))
    (map-elt result :output)))

(cl-defun ob-chatgpt-shell--make-thread ()
  "Create an OpenAI thread."
  (interactive)
  (let* ((result (shell-maker-make-http-request
                  :url "https://api.openai.com/v1/threads"
                  :data "" ;; force POST
                  :headers (append (chatgpt-shell-openai--make-headers)
                                   '("OpenAI-Beta: assistants=v2"))
                  :filter (lambda (raw-response)
                            (if-let* ((parsed (shell-maker--json-parse-string raw-response))
                                      (response (let-alist parsed
                                                  (or .error.message
                                                      .id))))
                                response
                              (error "Couldn't parse %s" raw-response)))))
         (success (map-elt result :success))
         (output (map-elt result :output)))
    (unless success
      (error  "error: %s" output))
    (unless output
      (error "No thread ID found"))
    output))

(cl-defun ob-chatgpt-shell--add-thread-message (&key thread-id file-id prompt)
  "Add a prompt and file message to an OpenAI assistant thread.

Requires message PROMPT, THREAD-ID, and FILE-ID."
  (interactive)
  (unless thread-id
    (error "Missing mandatory :thread-id param"))
  (unless file-id
    (error "Missing mandatory :file-id param"))
  (unless prompt
    (error "Missing mandatory :prompt param"))
  (let* ((result (shell-maker-make-http-request
                  :url (format "https://api.openai.com/v1/threads/%s/messages" thread-id)
                  :data `((role . "user")
                          (content . ,prompt)
                          (attachments . [((file_id . ,file-id)
                                           (tools .  [((type . "file_search"))]))]))
                  :headers (append (chatgpt-shell-openai--make-headers)
                                   '("OpenAI-Beta: assistants=v2"))
                  :filter (lambda (raw-response)
                            (if-let* ((parsed (shell-maker--json-parse-string raw-response))
                                      (response (let-alist parsed
                                                  (or .error.message
                                                      .id))))
                                response
                              (error "Couldn't parse %s" raw-response)))))
         (success (map-elt result :success))
         (output (map-elt result :output)))
    (unless success
      (error  "error: %s" output))
    (unless output
      (error "No message ID found"))
    output))

(cl-defun ob-chatgpt-shell--query-file (&key prompt file-id file assistant-id thread-id)
  "Query a file via assistant using PROMPT.

Must provide either a FILE path or FILE-ID.

Optionally provide an ASSISTANT-ID, THREAD-ID to reuse existing thread.

If they are not provided, new ones will be created on cloud (along with
associated costs)."
  (unless prompt
    (error "Missing mandatory :prompt param"))
  (unless (or file file-id)
    (error "Missing mandatory :file or :file-id params"))
  (let ((missing)
        (created)
        (message-id)
        (run-id)
        (assistant-instructions)
        (assistant-name)
        (response))
    (unless assistant-id
      (setq missing (append missing '("assistant-id"))))
    (unless thread-id
      (setq missing (append missing '("thread-id"))))
    (when (and missing
               (y-or-n-p (format "Missing (%s).  Request? " (string-join missing " "))))
      (unless assistant-id
        (setq assistant-name (read-string "Assistant name: "))
        (when (string-empty-p (string-trim assistant-name))
          (error "Invalid assistant name"))
        (setq assistant-instructions (read-string "Assistant instructions: "))
        (when (string-empty-p (string-trim assistant-instructions))
          (error "Invalid assistant instructions")))
      (unless file-id
        (message "Uploading file...")
        (setq file-id (ob-chatgpt-shell--upload-file
                       :purpose "assistants"
                       :path (or file
                                 (read-file-name "Select file: " nil nil t)
                                 (error "No file selected"))))
        (setq created (append created (list (concat "file-id: "
                                                    file-id)))))
      (unless assistant-id
        (message "Creating assistant...")
        (setq assistant-id (ob-chatgpt-shell--make-assistant
                            :name assistant-name
                            :instructions assistant-instructions))
        (setq created (append created (list (concat "assistant-id: "
                                                    assistant-id)))))
      (unless thread-id
        (message "Creating thread...")
        (setq thread-id (ob-chatgpt-shell--make-thread))
        (setq created (append created (list (concat "thread-id: "
                                                    thread-id)))))
      (kill-new (string-join created " ")))
    (when (and file-id assistant-id thread-id)
      (message "Adding prompt...")
      (setq message-id (ob-chatgpt-shell--add-thread-message :thread-id thread-id
                                                             :file-id file-id
                                                             :prompt prompt))
      (setq created (append created (list (concat "message-id: "
                                                  message-id))))
      (setq run-id (ob-chatgpt-shell--run-thread :thread-id thread-id
                                                 :assistant-id assistant-id))
      (message "Waiting for response...")
      (if (string= (ob-chatgpt-shell--wait-for-run-completion :thread-id thread-id :run-id run-id)
                   "completed")
          (let-alist (ob-chatgpt-shell--fetch-thread :thread-id thread-id)
            (let-alist (seq-first .data)
              (let-alist (seq-find (lambda (elt)
                                     (string= (alist-get 'type elt) "text"))
                                   .content)
                (setq response .text.value)
                (if created
                    (message "Copied (%s)" (string-join created " "))
                  (message "Done"))
                response)))
        (error "Couldn't run chat")))))

(cl-defun ob-chatgpt-shell--fetch-thread (&key thread-id)
  "Fetch OpenAI assistant thread with THREAD-ID."
  (interactive)
  (let* ((result (shell-maker-make-http-request
                  :url (format "https://api.openai.com/v1/threads/%s/messages" thread-id)
                  :headers (append (chatgpt-shell-openai--make-headers)
                                   '("OpenAI-Beta: assistants=v2"))))
         (success (map-elt result :success))
         (parsed (shell-maker--json-parse-string (map-elt result :output)))
         (thread (let-alist parsed
                   (when .error.message
                     (error "%s" .error.message))
                   parsed)))
    (if success
        thread
      (error "Couldn't fetch thread"))))

(cl-defun ob-chatgpt-shell--wait-for-run-completion (&key thread-id run-id)
  "Wait for OpenAI assistant thread run with THREAD-ID and RUN-ID."
  (interactive)
  (let ((status "queued"))
    (while (or (string= status "queued")
               (string= status "in_progress")
               (string= status "cancelling"))
      (let-alist (ob-chatgpt-shell--fetch-run :thread-id thread-id :run-id run-id)
        (setq status .status)))
    status))

(cl-defun ob-chatgpt-shell--fetch-run (&key thread-id run-id)
  "Fetch OpenAI assistant thread run with THREAD-ID and RUN-ID."
  (interactive)
  (let* ((result (shell-maker-make-http-request
                  :url (format "https://api.openai.com/v1/threads/%s/runs/%s" thread-id run-id)
                  :headers (append (chatgpt-shell-openai--make-headers)
                                   '("OpenAI-Beta: assistants=v2"))))
         (success (map-elt result :success))
         (parsed (shell-maker--json-parse-string (map-elt result :output)))
         (run (let-alist parsed
                (when .error.message
                  (error "%s" .error.message))
                parsed)))
    (if success
        run
      (error "Couldn't fetch run"))))

(cl-defun ob-chatgpt-shell--run-thread (&key thread-id assistant-id temperature)
  "Run OpenAI assistant thread with THREAD-ID, ASSISTANT-ID, and TEMPERATURE."
  (interactive)
  (unless thread-id
    (error "Missing mandatory :thread-id param"))
  (unless assistant-id
    (error "Missing mandatory :assistant-id param"))
  (let* ((result (shell-maker-make-http-request
                  :url (format "https://api.openai.com/v1/threads/%s/runs" thread-id)
                  :data (append
                         `((assistant_id . ,assistant-id)
                           (model . "gpt-4o"))
                         (when temperature
                           `((temperature . ,temperature))))
                  :headers (append (chatgpt-shell-openai--make-headers)
                                   '("OpenAI-Beta: assistants=v2"))
                  :filter (lambda (raw-response)
                            (if-let* ((parsed (shell-maker--json-parse-string raw-response))
                                      (response (let-alist parsed
                                                  (or .error.message
                                                      .id))))
                                response
                              (error "Couldn't parse %s" raw-response)))))
         (success (map-elt result :success))
         (output (map-elt result :output)))
    (unless success
      (error  "error: %s" output))
    (unless output
      (error "No run ID found"))
    output))

(cl-defun ob-chatgpt-shell--make-assistant (&key name instructions)
  "Create an OpenAI assistant with NAME and INSTRUCTIONS."
  (interactive)
  (unless name
    (error "Missing mandatory :name param"))
  (unless instructions
    (error "Missing mandatory :instructions param"))
  (let* ((result (shell-maker-make-http-request
                  :url "https://api.openai.com/v1/assistants"
                  :data `((name . ,name)
                          (instructions . ,instructions)
                          (tools .  [((type . "file_search"))])
                          (model . "gpt-4o"))
                  :headers (append (chatgpt-shell-openai--make-headers)
                                   '("OpenAI-Beta: assistants=v2"))
                  :filter (lambda (raw-response)
                            (if-let* ((parsed (shell-maker--json-parse-string raw-response))
                                      (response (let-alist parsed
                                                  (or .error.message
                                                      .id))))
                                response
                              (error "Couldn't parse %s" raw-response)))))
         (success (map-elt result :success))
         (output (map-elt result :output)))
    (unless success
      (error  "error: %s" output))
    (unless output
      (error "No assistant ID found"))
    output))

(provide 'ob-chatgpt-shell)

;;; ob-chatgpt-shell.el ends here
