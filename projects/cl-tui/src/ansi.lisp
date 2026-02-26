;;;; src/ansi.lisp — Raw ANSI escape code helpers

(in-package #:cl-tui/ansi)

;;; ESC character
(defconstant +esc-char+ #\Escape)

(defun esc (&rest codes)
  "Build an ANSI escape sequence: ESC[ code1 ; code2 ; ... m"
  (format nil "~c[~{~a~^;~}m" +esc-char+ codes))

;;; ── Text attributes ──────────────────────────────────────────────────────────

(defparameter +reset+  (esc 0))
(defparameter +bold+   (esc 1))
(defparameter +dim+    (esc 2))

;;; ── Foreground colors (standard) ─────────────────────────────────────────────

(defparameter +fg-black+    (esc 30))
(defparameter +fg-red+      (esc 31))
(defparameter +fg-green+    (esc 32))
(defparameter +fg-yellow+   (esc 33))
(defparameter +fg-blue+     (esc 34))
(defparameter +fg-magenta+  (esc 35))
(defparameter +fg-cyan+     (esc 36))
(defparameter +fg-white+    (esc 37))

;;; ── Foreground colors (bright) ───────────────────────────────────────────────

(defparameter +fg-bright-black+    (esc 90))
(defparameter +fg-bright-red+      (esc 91))
(defparameter +fg-bright-green+    (esc 92))
(defparameter +fg-bright-yellow+   (esc 93))
(defparameter +fg-bright-blue+     (esc 94))
(defparameter +fg-bright-magenta+  (esc 95))
(defparameter +fg-bright-cyan+     (esc 96))
(defparameter +fg-bright-white+    (esc 97))

;;; ── Cursor & screen ──────────────────────────────────────────────────────────

(defparameter +clear-screen+ (format nil "~c[2J" +esc-char+))
(defparameter +clear-line+   (format nil "~c[2K" +esc-char+))
(defparameter +cursor-home+  (format nil "~c[H"  +esc-char+))

(defun cursor-up (n)
  (format nil "~c[~aA" +esc-char+ n))

(defparameter +cursor-up+ (cursor-up 1))

;;; ── Composing helpers ────────────────────────────────────────────────────────

(defun colored (color-code text &optional (reset +reset+))
  "Wrap TEXT in COLOR-CODE ... RESET."
  (concatenate 'string color-code text reset))

(defun strip-ansi (text)
  "Remove ANSI escape sequences from TEXT."
  (cl-ppcre:regex-replace-all "\\e\\[[0-9;]*[mABCDHJKf]" text ""))

;;; ── Output helpers ───────────────────────────────────────────────────────────

(defun write-colored (color-code text &optional (stream *standard-output*))
  "Write TEXT to STREAM wrapped in color codes, then reset."
  (write-string color-code stream)
  (write-string text stream)
  (write-string +reset+ stream))

(defun newline (&optional (stream *standard-output*))
  (terpri stream)
  (force-output stream))
