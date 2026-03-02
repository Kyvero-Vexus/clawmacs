# Installation

Detailed installation instructions for Clawmacs.

## System Requirements

- **SBCL 2.3.0+**
- **Quicklisp**
- **ASDF 3.3+** (bundled with SBCL)
- **libssl** for TLS features (`cl+ssl`)
- **Node.js 18+** only if you use browser automation

## Install SBCL

### Debian / Ubuntu

```bash
sudo apt update && sudo apt install sbcl
```

### macOS (Homebrew)

```bash
brew install sbcl
```

## Install Quicklisp

```bash
curl -O https://beta.quicklisp.org/quicklisp.lisp
sbcl --load quicklisp.lisp \
     --eval '(quicklisp-quickstart:install)' \
     --eval '(ql:add-to-init-file)' \
     --quit
```

Verify:

```bash
sbcl --eval '(ql:system-apropos "dexador")' --quit
```

## Install Clawmacs

```bash
cd ~/projects
git clone https://github.com/chrysolambda-ops/clawmacs.git
cd clawmacs
```

Repository layout currently includes:

```text
projects/
  cl-llm/
  cl-tui/
  clambda-core/
  clambda-gui/
  cl-term/
```

ASDF systems to load are still `:clawmacs-core` and `:clawmacs-gui`.

## Register with ASDF

```bash
mkdir -p ~/.config/common-lisp/source-registry.conf.d/
cat > ~/.config/common-lisp/source-registry.conf.d/clawmacs.conf << 'EOF'
(:tree "/home/YOU/projects/clawmacs/projects/")
EOF
```

## Install Dependencies / Smoke test

```bash
sbcl --eval '(ql:quickload :clawmacs-core)' --quit
```

Optional terminal UI:

```bash
sbcl --eval '(ql:quickload :cl-tui)' --quit
```

## Browser Automation (optional)

```bash
cd projects/clambda-core/browser/
npm install
npx playwright install chromium
```

## Verify Installation

```bash
sbcl --eval '(ql:quickload :clawmacs-core)' \
     --eval '(format t "Clawmacs core loaded OK~%")' \
     --quit
```

## Next Steps

- [Quick Start](README.md)
- [Configuration](../configuration/init-lisp.md)
