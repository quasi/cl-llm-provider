;;; ABOUTME: Domain-specific generators for cl-llm-provider property-based testing

(in-package :cl-llm-provider)

;;; Message generators

(th.property:defgenerator gen-role ()
  "Generate a message role string."
  (th.gen:elements "user" "assistant" "system"))

(th.property:defgenerator gen-content ()
  "Generate message content (non-empty string)."
  (th.gen:strings :min-length 1 :max-length 200))

(th.property:defgenerator gen-message ()
  "Generate a message plist with :role and :content."
  (th.gen:fmap (lambda (role content)
                 (list :role role :content content))
               (gen-role)
               (gen-content)))

(th.property:defgenerator gen-conversation (&key (min-length 1) (max-length 10))
  "Generate a list of messages forming a conversation."
  (th.gen:lists (gen-message) :min-length min-length :max-length max-length))

;;; Usage generators

(th.property:defgenerator gen-usage ()
  "Generate a token usage plist with valid invariant: total = prompt + completion."
  (th.gen:fmap (lambda (prompt-tokens completion-tokens)
                 (list :prompt-tokens prompt-tokens
                       :completion-tokens completion-tokens
                       :total-tokens (+ prompt-tokens completion-tokens)))
               (th.gen:integers :min 0 :max 10000)
               (th.gen:integers :min 0 :max 5000)))

;;; Tool generators

(th.property:defgenerator gen-param-type ()
  "Generate a valid tool parameter type keyword."
  (th.gen:elements :string :integer :number :boolean :array :object))

(th.property:defgenerator gen-tool-parameter ()
  "Generate a tool parameter spec plist."
  (th.gen:fmap (lambda (name type)
                 (list :name name
                       :type type
                       :description (format nil "Parameter ~A" name)))
               (th.gen:fmap (lambda (s) (format nil "param_~A" s))
                            (th.gen:strings :min-length 2 :max-length 10
                                            :alphabet "abcdefghijklmnopqrstuvwxyz"))
               (gen-param-type)))

(th.property:defgenerator gen-tool-definition ()
  "Generate a full tool-definition with random parameters."
  (th.gen:fmap (lambda (name params)
                 (make-instance 'tool-definition
                                :name name
                                :description (format nil "Tool ~A" name)
                                :parameters params
                                :safety-level :safe))
               (th.gen:fmap (lambda (s) (format nil "tool_~A" s))
                            (th.gen:strings :min-length 2 :max-length 15
                                            :alphabet "abcdefghijklmnopqrstuvwxyz"))
               (th.gen:lists (gen-tool-parameter) :min-length 0 :max-length 5)))

;;; Provider type generator

(th.property:defgenerator gen-provider-type ()
  "Generate one of the provider type keywords."
  (th.gen:elements :openai :anthropic :ollama :openrouter :gemini))

;;; Safety level generator

(th.property:defgenerator gen-safety-level ()
  "Generate a valid safety level keyword."
  (th.gen:elements :safe :moderate :dangerous))
