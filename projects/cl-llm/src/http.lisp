;;;; src/http.lisp — HTTP transport layer

(in-package #:cl-llm/http)

;;; We rely on dexador for HTTP. For streaming we use dexador's :want-stream t
;;; option which gives us the raw response stream.

(defun make-headers (api-key &optional extra)
  "Build the Authorization + Content-Type headers."
  (append
   (list (cons "Content-Type"  "application/json")
         (cons "Authorization" (format nil "Bearer ~a" api-key)))
   extra))

(defun post-json (url api-key body-string)
  "POST body-string as JSON to URL, return response body string.
Signals HTTP-ERROR on non-2xx."
  (handler-case
      (dexador:post url
                    :headers (make-headers api-key)
                    :content body-string)
    (dexador:http-request-failed (e)
      (error 'http-error
             :status (dexador:response-status e)
             :body   (dexador:response-body e)))))

(defun post-json-stream (url api-key body-string callback)
  "POST body-string as JSON to URL with stream:true.
Calls CALLBACK with each SSE line as it arrives.
CALLBACK receives a string line; returns when the stream ends."
  (handler-case
      ;; With :want-stream t, dexador returns the response body as a stream
      ;; in the first return value (body), NOT the 5th.
      (let ((stream (dexador:post url
                                  :headers (make-headers api-key)
                                  :content body-string
                                  :want-stream t)))
        (unwind-protect
             (loop :for line := (read-line stream nil nil)
                   :while line
                   :do (funcall callback line))
          (close stream)))
    (dexador:http-request-failed (e)
      (error 'http-error
             :status (dexador:response-status e)
             :body   (dexador:response-body e)))))
