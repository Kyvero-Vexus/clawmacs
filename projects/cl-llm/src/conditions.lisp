;;;; src/conditions.lisp — Condition hierarchy for cl-llm

(in-package #:cl-llm/conditions)

;;; ── Base ─────────────────────────────────────────────────────────────────────

(define-condition llm-error (error)
  ()
  (:documentation "Root condition for all cl-llm errors."))

;;; ── HTTP layer ───────────────────────────────────────────────────────────────

(define-condition http-error (llm-error)
  ((status :initarg :status :reader http-error-status)
   (body   :initarg :body   :reader http-error-body))
  (:report (lambda (c s)
             (format s "HTTP error ~a: ~a"
                     (http-error-status c)
                     (http-error-body c))))
  (:documentation "Raised when the HTTP layer returns a non-2xx response."))

;;; ── API layer ────────────────────────────────────────────────────────────────

(define-condition api-error (llm-error)
  ((type    :initarg :type    :reader api-error-type    :initform nil)
   (code    :initarg :code    :reader api-error-code    :initform nil)
   (message :initarg :message :reader api-error-message :initform nil))
  (:report (lambda (c s)
             (format s "API error~@[ [~a]~]~@[ (~a)~]: ~a"
                     (api-error-type c)
                     (api-error-code c)
                     (api-error-message c))))
  (:documentation "Raised when the API returns an error object in the response body."))

;;; ── Parse layer ──────────────────────────────────────────────────────────────

(define-condition parse-error* (llm-error)
  ((raw :initarg :raw :reader parse-error-raw :initform nil))
  (:report (lambda (c s)
             (format s "Failed to parse LLM response. Raw: ~s"
                     (parse-error-raw c))))
  (:documentation "Raised when we can't parse a response from the API."))

;;; ── Stream layer ─────────────────────────────────────────────────────────────

(define-condition stream-error* (llm-error)
  ((chunk :initarg :chunk :reader stream-error-chunk :initform nil))
  (:report (lambda (c s)
             (format s "Error in SSE stream. Chunk: ~s"
                     (stream-error-chunk c))))
  (:documentation "Raised when there's an error parsing an SSE stream."))

;;; ── Retryable errors ─────────────────────────────────────────────────────────

(define-condition retryable-error (http-error)
  ((attempt :initarg :attempt :reader retryable-error-attempt :initform 1))
  (:report (lambda (c s)
             (format s "Retryable HTTP error ~a (attempt ~a): ~a"
                     (http-error-status c)
                     (retryable-error-attempt c)
                     (http-error-body c))))
  (:documentation
   "A transient HTTP error that may succeed on retry.
Signalled for status codes: 429, 500, 502, 503, 504.
The RETRY restart is established by the retry loop."))

;;; ── Restarts ─────────────────────────────────────────────────────────────────
;;
;; We define no global restarts here — callers establish their own.
;; Common patterns:
;;
;;   (restart-case (cl-llm:chat ...)
;;     (retry ()
;;       :report "Retry the request"
;;       (cl-llm:chat ...))
;;     (use-value (v)
;;       :report "Supply a fallback response"
;;       v))
;;
;; The library itself uses INVOKE-RESTART where appropriate (e.g., skip-chunk
;; during streaming).
