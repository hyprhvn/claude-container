# Container Environment & Tooling

You are in an Alpine Linux 3.24 container running under rootless Podman.
You have root privileges inside this container to install any necessary packages (`apk add ...`), and direct access to the mounted workspace directory on the host.

## Available Tools

The following tools and runtimes are pre-installed in the container environment:

### System & Networking Utilities

- **Shell & Core:** `bash`, `coreutils`, `findutils`, `grep`, `sed`, `gawk`, `procps` for POSIX scripting, text manipulation, and process monitoring.
- **Networking & Transfer:** `curl`, `wget`, `openssh-client`, `iproute2`, `socat` for network diagnostics, file retrieval, and SSH connectivity.

### Version Control & Patching

- `git`, `git-lfs`, `patch`, `patchutils` for repository management, handling large files, and creating or applying diffs.

### Compilers & Runtimes

- **C/C++:** `build-base`, `musl-dev`
- **Python:** `python3`, `py3-pip`, `uv`
- **JavaScript & TypeScript:** `nodejs`, `npm`, `typescript`
- **Java:** OpenJDK 25, `maven`, `gradle`
- **Rust:** `rust`, `cargo`

### Language Servers (LSP)

- **Bash:** `bash-language-server`
- **C/C++:** `clangd` (via `clang-extra-tools`)
- **Go:** `gopls`
- **Java:** `jdtls`
- **Python:** `pylsp` (`py3-lsp-server`)
- **Rust:** `rust-analyzer`
- **TypeScript / JavaScript:** `typescript-language-server`

### Linters & Formatters

- **Shell:** `shellcheck`, `shfmt`
- **C/C++:** `clang-format`, `clang-tidy`, `cppcheck`
- **Go:** `golangci-lint`
- **Java:** Typically invoked via `mvn` or `gradle` plugins
- **Markdown:** `markdownlint` (`markdownlint-cli`)
- **Python:** `ruff` (via `uv`)
- **Rust:** `rustfmt`, `cargo-clippy` (`rust-clippy`)
- **Web / TS / JS:** `eslint`, `prettier`
- **YAML:** `yamllint`

### Documentation, Diagramming & Headless Browser

- **LaTeX:** `texlive`, `texlive-latexextra`, `texlive-latexrecommended`, `texlive-fonts-recommended`, `latexmk` for compiling technical documents/PDFs.
- **Diagram Rendering:** `plantuml`, `graphviz`, `@mermaid-js/mermaid-cli` for generating architectural and flow diagrams from text.
- **Browser Automation:** `chromium`, `font-noto`, `font-noto-cjk` with Puppeteer support for headless browser operations and rendering.

### Code Search & Agent Tooling

- **Code Navigation:**
  - `ast-grep`: AST-based search and refactoring
  - `ripgrep` (`rg`): fast text search
  - `fd`: fast file traversal
  - `ctags`: symbol indexing
- **Structured Data Processing:**
  - [`jq`](https://jqlang.org/manual/): JSON parsing and transformations
  - [`mq`](https://raw.githubusercontent.com/harehare/mq/refs/heads/main/docs/books/src/SUMMARY.md): Markdown processing
  - [`yq-go`](https://mikefarah.gitbook.io/yq/llms.txt): YAML/XML/CSV/TOML/HCL/properties manipulation
  - [`htmlq`](https://raw.githubusercontent.com/mgdm/htmlq/refs/heads/master/README.md): HTML extraction via CSS selectors
  - [`xmlstarlet`](https://xmlstar.sourceforge.net/doc/UG/): XML querying and editing
- **Tabular Data & SQL:**
  - `miller` (`mlr`): multi-format data wrangling
  - `csvkit`: CSV manipulation
  - `duckdb`: in-process analytical SQL engine
  - `jc`: converts CLI tool outputs to structured JSON
