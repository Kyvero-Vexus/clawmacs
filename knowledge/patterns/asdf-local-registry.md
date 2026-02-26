# Pattern: ASDF Local Source Registry

## Problem
You have local CL projects (not in Quicklisp) that other local projects depend on.
`(asdf:load-system :my-lib)` fails with "System not found".

## Solution

Create `~/.config/common-lisp/source-registry.conf`:

```lisp
(:source-registry
  (:tree "/path/to/your/projects/")
  :inherit-configuration)
```

The `:tree` directive recursively scans the directory for `.asd` files.
`:inherit-configuration` preserves Quicklisp's own source registry.

After creating/editing:
```lisp
(asdf:clear-source-registry)
(asdf:initialize-source-registry)
```

Or from the shell, reinitialize with each SBCL invocation using:
```
sbcl --eval '(asdf:clear-source-registry)' --eval '(asdf:initialize-source-registry)' ...
```

## On This Machine

`~/.config/common-lisp/source-registry.conf` points to:
```
/home/slime/.openclaw/workspace-gensym/projects/
```

This covers: `cl-llm`, `cl-tui`, and any future projects under `projects/`.

## Pitfall

If you forget `(asdf:clear-source-registry)` before `(asdf:initialize-source-registry)`,
the new config may not take effect in a long-running image. Always clear first.
