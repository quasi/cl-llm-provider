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
Uses character-based estimation as a portable fallback.

Note: Optimized for English/Latin text (~4 chars/token). Non-ASCII text
(CJK, Arabic, etc.) typically has different token density and this estimate
may be less accurate. Use for planning/budgeting, not precise accounting."
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

(defun estimate-cost (messages &key provider model system max-tokens)
  "Estimate cost for a completion request.

MESSAGES - List of message plists
PROVIDER - Provider instance (required for pricing lookup)
MODEL - Model identifier
SYSTEM - System prompt (string)
MAX-TOKENS - Expected output tokens (defaults to 1000)

Returns (values input-cost output-cost-estimate total-estimate).
All costs in USD.

Returns NIL values if pricing unavailable for model.

Example:
  (multiple-value-bind (in out total)
      (estimate-cost messages :provider *openai* :model \"gpt-4\" :max-tokens 500)
    (format t \"Estimated cost: $~,4F~%\" total))"
  (let* ((effective-model (or model
                             (when provider (provider-default-model provider))))
         (metadata (when (and provider effective-model)
                    (model-metadata provider effective-model)))
         (input-cost-per-1m (getf metadata :input-cost-per-1m-tokens))
         (output-cost-per-1m (getf metadata :output-cost-per-1m-tokens)))

    (if (and input-cost-per-1m output-cost-per-1m)
        (let* ((input-tokens (count-tokens-with-system messages system
                                                       :model effective-model
                                                       :provider provider))
               (output-tokens (or max-tokens 1000))
               (input-cost (* input-tokens (/ input-cost-per-1m 1000000.0)))
               (output-cost (* output-tokens (/ output-cost-per-1m 1000000.0))))
          (values input-cost output-cost (+ input-cost output-cost)))
        (values nil nil nil))))

(defun format-cost (cost &optional (stream t))
  "Format cost in USD for display.
COST - Cost in USD (float)
STREAM - Output stream

Example: (format-cost 0.0025) => \"$0.0025\""
  (if cost
      (format stream "$~,4F" cost)
      (format stream "N/A")))
