# Pattern: ANSI TUI with Streaming Output

## Context
Building a terminal chat UI in CL that shows streaming LLM tokens in real-time.

## The Pattern

### 1. ANSI color constants as defparameter strings

```lisp
(defparameter +reset+  (format nil "~c[0m" #\Escape))
(defparameter +bold+   (format nil "~c[1m" #\Escape))
(defparameter +fg-bright-green+ (format nil "~c[92m" #\Escape))

(defun colored (color text)
  (concatenate 'string color text +reset+))
```

No dependencies — just strings. Combine with `concatenate` for compound styles:
```lisp
(colored (concatenate 'string +bold+ +fg-bright-green+) "[AI] ")
```

### 2. Streaming tokens with force-output

```lisp
(defun print-token (token &optional (stream *standard-output*))
  (write-string token stream)
  (force-output stream))  ; CRITICAL — without this tokens buffer
```

Pass this as the callback to `cl-llm:chat-stream`:
```lisp
(chat-stream client messages #'print-token :model model)
```

### 3. Main loop — use loop + loop-finish for EOF

```lisp
(loop while (app-running-p app)
      do
      (print-prompt stream)
      (let ((input (read-input)))
        (when (null input)           ; EOF → clean exit
          (app-stop app)
          (loop-finish))
        (unless (string= (string-trim " " input) "")
          (dispatch input))))
```

**Never use `go` inside `loop`** — that requires `tagbody`. Use `loop-finish` or `return`.

### 4. Slash command dispatch

```lisp
(defun parse-command (input)
  "Return (cmd . rest-string)"
  (let* ((trimmed (string-trim " " input))
         (space   (position #\Space trimmed)))
    (if space
        (cons (string-downcase (subseq trimmed 1 space))
              (string-trim " " (subseq trimmed (1+ space))))
        (cons (string-downcase (subseq trimmed 1)) ""))))
```

### 5. App state struct pattern

```lisp
(defstruct (app (:constructor %make-app))
  client messages model system-prompt (running-p t) stream)

(defvar *app* nil)  ; global for command handlers to mutate
```

## Alternatives Considered
- `cl-charms` (ncurses binding) — rejected, too heavy, adds C dependency
- Raw terminal mode with `ioctl` — rejected for now, line input sufficient
- `format` with escape codes inline — messy, prefer named constants

## When to Use
- Any CL terminal UI that needs color output
- Streaming display of LLM responses
- Simple slash-command driven interfaces

## Pitfalls
- `force-output` is mandatory for streaming to appear token-by-token
- UTF-8 box-drawing chars (╔╗╚╝═║) work fine in SBCL strings
- Unicode dashes (─) work; use them instead of ASCII `-` for polish
- Concatenate style strings with `concatenate 'string`, not `format`
