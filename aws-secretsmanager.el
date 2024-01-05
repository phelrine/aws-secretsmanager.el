;;; aws-secretsmanager.el --- AWS Secrets Manager interface for Emacs

;;; Commentary:

;; aws-secretsmanager provides an interface to interact with AWS Secrets Manager.
;; It allows users to list secrets and view secret details within Emacs.

;;; Code:

(require 'json)
(require 'tabulated-list)

(defun aws-secretsmanager--parse-json (json-string)
  "Parse a JSON-STRING into an Emacs Lisp structure."
  (let ((json-object-type 'hash-table)
        (json-array-type 'list)
        (json-key-type 'string))
    (json-read-from-string json-string)))

(defun aws-secretsmanager--execute-aws-command (command)
  "Execute an AWS CLI COMMAND and return its output as JSON."
  (let ((command-output (shell-command-to-string command)))
    (unless command-output
      (error "Failed to execute AWS command: %s" command))
    (aws-secretsmanager--parse-json command-output)))

(defun aws-secretsmanager--list-secrets-with-arn ()
  "Return a list of secrets with names and ARNs from AWS Secrets Manager."
  (let* ((json (aws-secretsmanager--execute-aws-command "aws secretsmanager list-secrets"))
         (secrets (gethash "SecretList" json)))
    (mapcar (lambda (secret)
              (list (gethash "Name" secret) (gethash "ARN" secret)))
            secrets)))

(defun aws-secretsmanager--get-secret-value (secret-arn)
  "Get the value of a secret by its SECRET-ARN from AWS Secrets Manager."
  (let ((secret-string (gethash "SecretString"
                                (aws-secretsmanager--execute-aws-command (format "aws secretsmanager get-secret-value --secret-id %s" secret-arn)))))
    (condition-case nil
        (aws-secretsmanager--parse-json secret-string)
      (error secret-string))))

(define-derived-mode aws-secretsmanager-secrets-tabulated-list-mode tabulated-list-mode "AWSSecretsManagerSecretsList"
  "Mode for AWS Secrets Manager secrets list."
  (define-key aws-secretsmanager-secrets-tabulated-list-mode-map (kbd "RET") 'aws-secretsmanager-tabulated-secrets-action)
  (define-key aws-secretsmanager-secrets-tabulated-list-mode-map (kbd "g") 'aws-secretsmanager-refresh-secrets-list))

(define-derived-mode aws-secretsmanager-secrets-detail-tabulated-list-mode tabulated-list-mode "AWSSecretsManagerSecretsDetailList"
  "Mode for AWS Secrets Manager secret details."
  (define-key aws-secretsmanager-secrets-detail-tabulated-list-mode-map (kbd "RET") 'aws-secretsmanager-tabulated-secrets-detail-action)
  (define-key aws-secretsmanager-secrets-detail-tabulated-list-mode-map (kbd "w") 'aws-secretsmanager-tabulated-secrets-detail-copy-action))

(defun aws-secretsmanager-show-secrets-list ()
  "Show the list of secrets in AWS Secrets Manager."
  (interactive)
  (aws-secretsmanager--display-secrets-in-tabulated-list))

(defun aws-secretsmanager-refresh-secrets-list ()
  "Refresh the displayed list of secrets in AWS Secrets Manager."
  (interactive)
  (aws-secretsmanager--update-tabulated-list-entries)
  (tabulated-list-print t))

(defun aws-secretsmanager--update-tabulated-list-entries ()
  "Update the entries for the tabulated list of AWS Secrets Manager secrets."
  (setq tabulated-list-entries
        (mapcar (lambda (secret)
                  (let ((name (car secret))
                        (arn (cdr secret)))
                    (list arn (vector name arn))))
                (aws-secretsmanager--list-secrets-with-arn))))

(defun aws-secretsmanager--display-secrets-in-tabulated-list ()
  "Display AWS Secrets Manager secrets in a tabulated list."
  (let ((buffer (get-buffer-create "*AWS Secrets List*")))
    (with-current-buffer buffer
      (setq tabulated-list-format [("Name" 50 t) ("ARN" 50 t)])
      (aws-secretsmanager-refresh-secrets-list) ; Initialize the list
      (aws-secretsmanager-secrets-tabulated-list-mode)
      (tabulated-list-init-header)
      (tabulated-list-print))
    (display-buffer buffer)
    (pop-to-buffer buffer)))

(defvar aws-secretsmanager--secrets-cache (make-hash-table :test 'equal)
  "Cache storing the retrieved details of AWS Secrets Manager secrets.")

(defvar aws-secretsmanager--selected-secret-arn nil
  "ARN of the currently selected secret.")

(defvar aws-secretsmanager--secrets-display-state (make-hash-table :test 'equal)
  "Hash table to track the display state (shown or hidden) of secret values.")

(defun aws-secretsmanager-tabulated-secrets-action ()
  "Display and cache details of the selected AWS Secrets Manager secret."
  (interactive)
  (let* ((id (car (tabulated-list-get-id)))
         (secret-value (aws-secretsmanager--get-secret-value id)))
    (if (hash-table-p secret-value)
        (aws-secretsmanager--display-secret-details id secret-value)
      (aws-secretsmanager--display-plain-text-secret id secret-value))))

(defun aws-secretsmanager--display-secret-details (id secret-value)
  "Display the details of a secret in a tabulated list.

ID is the ARN of the secret to be displayed.  It is used to identify
the secret within AWS Secrets Manager and to label the buffer in which
the secret's details are displayed.

SECRET-VALUE is a hash table containing the key-value pairs of the secret.
These details are extracted from the AWS Secrets Manager and presented
in a tabulated list format, allowing for easy viewing and interaction."
  (let* ((entries (and secret-value (hash-table-p secret-value)
                       (mapcar (lambda (key)
                                 (list key (vector key (format "%s" (gethash key secret-value)))))
                               (hash-table-keys secret-value))))
         (buffer (get-buffer-create (format "*AWS Secret Details: %s*" id))))
    (puthash id entries aws-secretsmanager--secrets-cache)
    (with-current-buffer buffer
      (setq tabulated-list-format [("Key" 30 t) ("Value" 50 t)])
      (aws-secretsmanager-secrets-detail-tabulated-list-mode)
      (tabulated-list-init-header)
      (setq-local aws-secretsmanager--selected-secret-arn id)
      (setq-local aws-secretsmanager--secrets-display-state (make-hash-table :test 'equal))
      (aws-secretsmanager--refresh-secret-list))
    (display-buffer buffer)
    (pop-to-buffer buffer)))

(defun aws-secretsmanager--display-plain-text-secret (id secret-text)
  "Display a plain text secret in a read-only buffer.

ID is the ARN of the secret, used to label the buffer
where the secret is displayed.  This helps in identifying
the secret when multiple secret buffers are open.

SECRET-TEXT is the string content of the secret as retrieved
from AWS Secrets Manager.  This content is displayed in a read-only buffer."
  (let ((buffer (get-buffer-create (format "*AWS Secret: %s*" id))))
    (with-current-buffer buffer
      (setq buffer-read-only nil)
      (erase-buffer)
      (insert secret-text)
      (setq buffer-read-only t)
      (view-mode 1)) ; Enable view mode for read-only buffer
    (display-buffer buffer)
    (pop-to-buffer buffer)))

(defun aws-secretsmanager--refresh-secret-list ()
  "Refresh the list display of the selected secret's details."
  (setq tabulated-list-entries
        (mapcar (lambda (entry)
                  (let* ((entry-key (car entry))
                         (value (aref (cadr entry) 1))
                         (displayed (gethash entry-key aws-secretsmanager--secrets-display-state)))
                    (list entry-key (vector entry-key (aws-secretsmanager--display-secret-value value displayed)))))
                (aws-secretsmanager--get-secret-details aws-secretsmanager--selected-secret-arn)))
  (tabulated-list-print))

(defun aws-secretsmanager--get-secret-details (secret-arn)
  "Get the details of a secret by its SECRET-ARN, using cache."
  (gethash secret-arn aws-secretsmanager--secrets-cache))

(defun aws-secretsmanager--toggle-secret-display (key)
  "Toggle the display state of a secret identified by KEY."
  (let ((current-state (gethash key aws-secretsmanager--secrets-display-state)))
    (puthash key (not current-state) aws-secretsmanager--secrets-display-state)))

(defun aws-secretsmanager-tabulated-secrets-detail-action ()
  "Toggle the display of the selected secret's details."
  (interactive)
  (let ((current-pos (point)))
    (with-current-buffer (current-buffer)
      (let* ((key (tabulated-list-get-id))
             (current-state (gethash key aws-secretsmanager--secrets-display-state)))
        (unless current-state
          (puthash key nil aws-secretsmanager--secrets-display-state))
        (aws-secretsmanager--toggle-secret-display key)
        (aws-secretsmanager--refresh-secret-list))
      (goto-char current-pos))))

(defun aws-secretsmanager-tabulated-secrets-detail-copy-action ()
  "Copy the value of a secret to the kill ring."
  (interactive)
  (with-current-buffer (current-buffer)
    (let* ((id (tabulated-list-get-id))
           (key id)
           (selected-value (aref (cadr (assoc key (aws-secretsmanager--get-secret-details aws-secretsmanager--selected-secret-arn))) 1)))
      (kill-new selected-value)
      (message "Secret copied to kill ring."))))

(defun aws-secretsmanager--display-secret-value (value displayed)
  "Show secret's VALUE or masked text based on DISPLAYED flag."
  (if displayed value "******"))

(provide 'aws-secretsmanager)

;;; aws-secretsmanager.el ends here
