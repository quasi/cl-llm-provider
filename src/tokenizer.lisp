(in-package :cl-llm-provider)

;;;; Token Counting
;;;;
;;;; Provides pre-request token counting for cost estimation and
;;;; context window overflow prevention.
;;;;
;;;; Uses character-based estimation as a portable fallback.
;;;; More accurate tokenizers can be added for specific models.

(defvar *chars-per-token-estimate* 4
  "Average characters per token for estimation.
Most English text averages 4 characters per token.
This is a conservative estimate for planning purposes.")

(defvar *message-overhead-tokens* 4
  "Token overhead per message for role and formatting.
OpenAI adds ~4 tokens per message for role/formatting.")

(defun estimate-tokens-from-text (text)
  "Estimate token count from text length.
TEXT - String to estimate tokens for

Returns estimated token count (integer).
Uses character-based estimation as a portable fallback."
  (if (or (null text) (string= text ""))
      0
      (ceiling (length text) *chars-per-token-estimate*)))

(defun count-message-tokens (message)
  "Count tokens in a single message plist.
MESSAGE - Plist with :role and :content

Returns estimated token count (integer)."
  (let ((content (getf message :content)))
    (+ *message-overhead-tokens*
       (etypecase content
         (string (estimate-tokens-from-text content))
         (null 0)
         (list
          ;; Multi-part content (e.g., with images)
          (loop for part in content
                sum (if (stringp part)
                        (estimate-tokens-from-text part)
                        (let ((text (getf part :text)))
                          (if text (estimate-tokens-from-text text) 0)))))))))

(defun count-tokens (messages &key model provider)
  "Count tokens in MESSAGES for MODEL/PROVIDER.

MESSAGES - List of message plists
MODEL - Model identifier (string) - used for model-specific tokenizers
PROVIDER - Provider instance - used for provider-specific tokenizers

Returns estimated token count (integer).

Note: This is an estimate. Actual token counts may vary by 5-10%.
Use for cost estimation and context window planning.

Example:
  (count-tokens '((:role \"user\" :content \"What is Common Lisp?\"))
                :model \"gpt-4\")
  => 8"
  (declare (ignore model provider)) ; TODO: Use for accurate tokenizers
  (loop for message in messages
        sum (count-message-tokens message)))

(defun count-tokens-with-system (messages system &key model provider)
  "Count tokens including system prompt.
MESSAGES - List of message plists
SYSTEM - System prompt string
MODEL - Model identifier
PROVIDER - Provider instance

Returns estimated token count (integer)."
  (+ (if system
         (+ *message-overhead-tokens* (estimate-tokens-from-text system))
         0)
     (count-tokens messages :model model :provider provider)))
