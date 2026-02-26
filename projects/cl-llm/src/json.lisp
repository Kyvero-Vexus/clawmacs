;;;; src/json.lisp — JSON utilities (wraps com.inuoe.jzon)

(in-package #:cl-llm/json)

;;; jzon uses hash-tables for objects and vectors for arrays by default.
;;; We expose a thin layer so that the rest of the codebase doesn't need
;;; to know about jzon directly.

(defun encode (value)
  "Encode VALUE to a JSON string."
  (com.inuoe.jzon:stringify value))

(defun decode (string-or-stream)
  "Decode a JSON string or stream to a Lisp value.
Objects become hash-tables, arrays become vectors, null becomes NIL,
true/false become T/NIL."
  (etypecase string-or-stream
    (string (com.inuoe.jzon:parse string-or-stream))
    (stream (com.inuoe.jzon:parse string-or-stream))))

(defun decode-string (string)
  "Decode a JSON string."
  (com.inuoe.jzon:parse string))

;;; ── Key conversion ───────────────────────────────────────────────────────────

(defun to-json-key (keyword-or-string)
  "Convert a CL keyword/symbol to a JSON object key string.
:MY-SLOT → \"my_slot\", \"already-string\" → as-is."
  (etypecase keyword-or-string
    (keyword (string-downcase
              (substitute #\_ #\- (symbol-name keyword-or-string))))
    (string keyword-or-string)
    (symbol (string-downcase
             (substitute #\_ #\- (symbol-name keyword-or-string))))))

(defun from-json-key (string)
  "Convert a JSON object key string to a keyword.
\"my_slot\" → :MY-SLOT"
  (intern (string-upcase (substitute #\- #\_ string)) :keyword))

;;; ── Plist ↔ hash-table ───────────────────────────────────────────────────────

(defun plist->object (plist)
  "Convert a plist to a hash-table suitable for JSON encoding.
Keys may be keywords (converted via TO-JSON-KEY) or strings."
  (let ((ht (make-hash-table :test #'equal)))
    (loop :for (k v) :on plist :by #'cddr
          :do (setf (gethash (to-json-key k) ht) v))
    ht))

(defun object->plist (hash-table)
  "Convert a JSON object (hash-table) to a plist with keyword keys."
  (let ((result '()))
    (maphash (lambda (k v)
               (push v result)
               (push (from-json-key k) result))
             hash-table)
    result))

;;; ── Nested access ────────────────────────────────────────────────────────────

(defun get* (object &rest keys)
  "Navigate nested JSON object (hash-table) by string keys.
Returns NIL if any key is missing."
  (reduce (lambda (obj key)
            (when (hash-table-p obj)
              (gethash key obj)))
          keys
          :initial-value object))
