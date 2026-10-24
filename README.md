# ripgrep-edit - Razor Coding Tool

ripgrep-edit enables *razor coding* by allowing LLM workflows to operate with razor-thin context, input and output.

## How it works

- 🔍 Search using `ripgrep` with configurable context lines  
- 📄 Present matches in a clean, linear, easy-to-read format  
- ✏️ Edit all matched code snippets in a single temporary file  
- 💾 Apply changes back to the original files  
- 🛠️ Work with any editor via a shell command  

If the temporary file is not saved by the editor, no changes are applied.

## Demo

> ![ripgrep-edit `"kernel arg_lock from spinlock to mutex"` commit](https://gitlab.com/aarcange/ripgrep-edit-assets/-/raw/main/demo-kernel-arg_lock.webm)
> ![ripgrep-edit `"quote_char_in_Range"` commit](https://gitlab.com/aarcange/ripgrep-edit-assets/-/raw/main/demo-quote_char_in_range.webm)
> ![ripgrep-edit `"follow symlinks"` commit](https://gitlab.com/aarcange/ripgrep-edit-assets/-/raw/main/demo-follow_symlinks.webm)
> ![ripgrep-edit `"deduplicate the dedup_by"` commit](https://gitlab.com/aarcange/ripgrep-edit-assets/-/raw/main/demo-dedup_slashes.webm)

## Build

```bash
git clone https://gitlab.com/aarcange/ripgrep-edit.git
cd ripgrep-edit
cargo build --release
```

## Distro Packages

### Fedora Copr

A Fedora Copr package is available:

```bash
sudo dnf copr enable vittyvk/ripgrep-edit
sudo dnf install ripgrep-edit
```

The Copr is built for Fedora rawhide / 43 / 42.

## Options

- `-e, --regexp <REGEXP>`: Regex pattern to search for  
- `-E, --editor <EDITOR>`: Editor command (e.g., `vim`, `emacsclient`)  
- `-C, --context <N>`: Number of context lines (default: 5, minimum: 1)  
- `-A, --after-context <N>`: Lines of context to show after each match (the larger of `-A` and `-C` is used)  
- `-B, --before-context <N>`: Lines of context to show before each match (the larger of `-B` and `-C` is used)  
- `--require-all-files`: Require all files in the ripgrep output to be present in the edited file (by default, files removed from the edited file are left unchanged)  
- `--context-separator <SEPARATOR>`: Separator string between snippets (default: `-- DO NOT DELETE THIS SEPARATOR`)  
- `--filename-prefix <PREFIX>`: Prefix for filename lines (default: `-- `)  
- `-S, --smart-case`: Enable smart case search  
- `-i, --ignore-case`: Ignore case distinctions  
- `-w, --word-regexp`: Force the pattern to match only whole words  
- `-U, --multiline`: Enable multiline matching  
- `--multiline-dotall`: Enable dotall mode for multiline matching  
- `--sort <SORT>`: Sort results by `path`, `modified`, `accessed`, or `created` time  
- `--sortr <SORT>`: Sort results in reverse order by `path`, `modified`, `accessed`, or `created` time (cannot be combined with `--sort`)  
- `-L, --follow`: Follow symlinks  
- `-j, --threads <NUM>`: Number of threads to use (default: 0, automatic)  
- `--dump-on-error`: Dump the processed temporary file to stderr on error  
- `--output-size-limit <SIZE>`: Limit the total ripgrep output size (e.g., `1024`, `1k`, `1m`, `1g`). If the limit is exceeded, the tool exits with code 3.  
- `--gbnf`: Generate a dynamic GBNF grammar file  
- `-G, --gbnf-control-lines <N>`: Maximum number of GBNF control lines added as extra context (default: 10)  
- `--`: End of options; all following arguments are treated as paths. Use this when a path starts with `-` so it is not interpreted as an option.  

## Examples

```bash
rg-edit [OPTIONS] --regexp <REGEXP> --editor <EDITOR> [--] [PATHS...]
rg-edit -e "function\s*\(" -E vim src/
rg-edit -e "function\s*\(" -E emacsclient -C 8 src/
rg-edit -E vim -C10 -U -e '(?s)^<<<<<<<+ .*?^\|\|\|\|\|\|\|+ .*?^>>>>>>>+ ' # resolve git conflicts
rg-edit -E emacsclient -C10 -U -e '(?s)^<<<<<<<+ .*?^\|\|\|\|\|\|\|+ .*?^>>>>>>>+ '
rg-edit -e '.*' -E vim src/ --output-size-limit 1m # fail if the output exceeds 1 megabyte (exits with code 3)
rg-edit -e "TODO" -E vim -- -weird-dir/ # use -- when a path starts with -
```

## Why It Was Built

Large codebases challenge LLMs due to context limits. Traditional vibe coding tools require the LLM agentic workflow to read snippets of multiple large files.

`ripgrep-edit` solves this by:
- 🔄 **Linearizing** code snippets from multiple files
- 📌 **Preserving context** around each match
- 🧠 **Enabling precise edits** via LLMs or editors
- 💾 **Reapplying changes** to the original files

`ripgrep-edit` lets the programmer define the exact context needed, presenting it in a structured, linear format optimized for the LLM's key-value input. The resulting gain in efficiency provides real-time visibility into what the LLM is generating, making it possible to interrupt, refine the input, adjust directives, and eliminate unnecessary context, computation, and cost.

The goal is to optimize the LLM's most demanding task — writing code — by minimizing perplexity and maximizing efficiency.

## How to use

This works best with tools like [`gptel-rewrite`](https://github.com/karthink/gptel), where extra context can be included for more complex refactorings.

To be effective, `ripgrep-edit` requires a well-crafted prompt:

```
You are a careful programmer. Rewrite cross-file snippets.
Rewrite everything exactly the same except: the required change.
Keep the filenames at the start of the files.
Keep the separators at the end of the snippets.
Do not delete the filenames and the separators.
Do not add markdown fences.
Do not ask clarification.
```

Every file kept in the edited output must retain all of its snippets and separators; otherwise the changes are rejected.

## rg-edit.el

- Provides the `rg-edit`, `rg-edit-buffer`, `rg-edit-git` and `rg-edit-git-conflicts` commands
- Requires a running Emacs server (`M-x server-start`), since `emacsclient` is used as the editor
- Enabling `global-auto-revert-mode` is recommended so modified files are reloaded automatically
- Automatically passes `--gbnf` when a configured gptel backend supports the `gbnf` or `ebnf` capability
- Keybindings:
  - `rg-edit-git` **C-c r**
  - `rg-edit` **C-0 C-c r**
  - `rg-edit-buffer` **C-- C-c r**
  - `rg-edit-git-conflicts` **C-u C-c r**
  - `rg-edit--commit` **C-c C-c** (in the rg-edit buffer, via `rg-edit-mode-map`)
  - `rg-edit--abort` **C-c C-k** (in the rg-edit buffer, via `rg-edit-mode-map`)
  - `rg-edit--terminate` **C-c C-k** (in the `*rg-edit*` buffer, terminates any outstanding session)
- Customization variables:
  - `rg-edit-executable`: path to the `rg-edit` executable
  - `rg-edit-auto-mark-whole-buffer`: mark the whole buffer when entering `rg-edit-mode`
  - `rg-edit-prefill-extra-args`: default extra arguments (default: `-U --multiline-dotall --smart-case`)
  - `rg-edit-gptel-system-message`: gptel directive used in rg-edit buffers
  - `rg-edit-mode-hook`: hook run when entering the `rg-edit-mode` major mode (derived from `prog-mode`)

```elisp
(add-to-list 'load-path "~/.../ripgrep-edit/emacs/")
(use-package rg-edit
  :ensure nil
  :config
  (setq-default rg-edit-auto-mark-whole-buffer t)
  (setq-default rg-edit-executable "~/.../ripgrep-edit/target/release/rg-edit"))
```

## GBNF/EBNF Grammar Support

ripgrep-edit integrates with [GBNF](https://github.com/ggml-org/llama.cpp/blob/master/grammars/README.md) to constrain LLM outputs when using llama.cpp or vLLM. When the `--gbnf` flag is used, a `.gbnf` grammar file is generated next to the temporary `.rg-edit` file. The `rg-edit.el` plugin automatically detects this file and injects its contents into the JSON request: as the `grammar` field when the gptel model supports the `gbnf` capability, or as `structured_outputs.grammar` when it supports the `ebnf` capability.

```elisp
;; Example: llama.cpp backend with GBNF support
(setq-default
 gptel-model 'test
 gptel-backend (gptel-make-openai "test"
		 :stream t
		 :protocol "http"
		 :host "localhost:8811"
		 :models '((test :capabilities (gbnf)))))

;; Example: vLLM backend with EBNF support
(setq-default
 gptel-model 'vllm
 gptel-backend (gptel-make-openai "vllm"
		 :stream t
		 :protocol "https"
		 :host "localhost:443"
		 :models '((vllm :capabilities (ebnf)))))
```

The GBNF grammar enforces a deterministic structure around the metadata markers of the rg-edit format. The LLM retains the ability to drop irrelevant files or reorder the file sequence, but the filename and its prefix are enforced verbatim, preventing typos. Inside each snippet, the grammar emits the "before context" control line (if available) and then grants the LLM free rein to modify the snippet content until it emits the "after context" control line or the separator. At that point, the grammar regains control, emits the separator (if not already emitted), and advances to the next snippet.

When the grammar is enabled, a notification appears in the `*rg-edit*` buffer.

> ![ripgrep-edit `"max_line_1 with GBNF"` commit](https://gitlab.com/aarcange/ripgrep-edit-assets/-/raw/main/demo-max_line_1-GBNF.webm)
> ![ripgrep-edit `"usage limit with GBNF"` commit](https://gitlab.com/aarcange/ripgrep-edit-assets/-/raw/main/demo-usage_limit-GBNF.webm)

## Why Not wgrep?

- Emacs' [`wgrep`](https://github.com/mhayashi1120/Emacs-wgrep) offers similar functionality but relies on interactive edits, such as `C-c C-d` to delete a line, which are incompatible with the full rewrites required by LLM-driven workflows.

- Unlike wgrep, `ripgrep-edit` is editor-agnostic and LLM-agnostic: any editor can be used, making it ideal for diverse environments, or simply to avoid opening multiple files in vim.

## License

[![License: GPL-3.0-or-later](https://img.shields.io/badge/License-GPL--3.0--or--later-blue.svg)](https://www.gnu.org/licenses/gpl-3.0.html) ![OR](https://img.shields.io/badge/OR-lightgrey.svg) [![License: AGPL-3.0-or-later](https://img.shields.io/badge/License-AGPL--3.0--or--later-blue.svg)](https://www.gnu.org/licenses/agpl-3.0.html)
