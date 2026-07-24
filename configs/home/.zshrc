# ==============================================================================
# Native zsh setup without Oh My Zsh.
#
# Backups:
#   ~/.zshrc.backup
#   ~/.zshrc.backup.<YYYYMMDD-HHMMSS>
#   ~/.oh-my-zsh.backup
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Shell Environment
# ------------------------------------------------------------------------------

# Terminal
export TERM="xterm-256color"

# Keep PATH tidy and deduplicated.
typeset -U path PATH

# Core autoloads
autoload -Uz add-zsh-hook colors compinit
colors
setopt prompt_subst

# Allow comments in interactive shells.
setopt interactivecomments

# ------------------------------------------------------------------------------
# 2. Completion System
# ------------------------------------------------------------------------------

# z plugin fpath
if [[ -d "$HOME/.zsh/plugins/z" ]]; then
  fpath=("$HOME/.zsh/plugins/z" $fpath)
fi

# Initialize completion.
compinit -d "$HOME/.zcompdump"

# Keep native zsh completion, but allow case-insensitive directory prefix matching.
# Example: `cd down<Tab>` can complete to `cd Downloads`.
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'
zmodload zsh/complist
zstyle ':completion:*' menu select
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
setopt auto_menu
setopt complete_in_word

# ------------------------------------------------------------------------------
# 3. History
# ------------------------------------------------------------------------------

HISTFILE="$HOME/.zsh_history"
HISTSIZE=100000
SAVEHIST=100000

# Keep a large shared history without polluting it with low-value duplicates.
setopt APPEND_HISTORY
setopt EXTENDED_HISTORY
setopt HIST_EXPIRE_DUPS_FIRST
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE
setopt HIST_REDUCE_BLANKS
setopt HIST_SAVE_NO_DUPS
setopt SHARE_HISTORY

# SHARE_HISTORY already appends/imports incrementally across sessions, so keep the
# history-write behavior unambiguous by disabling overlapping modes.
unsetopt INC_APPEND_HISTORY
unsetopt INC_APPEND_HISTORY_TIME

# Keep standard Ctrl-R search and make Up/Down search by the current prefix.
if autoload -Uz up-line-or-beginning-search down-line-or-beginning-search \
  && autoload +X up-line-or-beginning-search down-line-or-beginning-search 2>/dev/null; then
  zle -N up-line-or-beginning-search
  zle -N down-line-or-beginning-search
  history_search_up_widget=up-line-or-beginning-search
  history_search_down_widget=down-line-or-beginning-search
else
  history_search_up_widget=history-beginning-search-backward
  history_search_down_widget=history-beginning-search-forward
fi

bindkey '^R' history-incremental-search-backward
bindkey '^[[A' "$history_search_up_widget"
bindkey '^[[B' "$history_search_down_widget"
bindkey '^[OA' "$history_search_up_widget"
bindkey '^[OB' "$history_search_down_widget"
[[ -n "${terminfo[kcuu1]-}" ]] && bindkey "${terminfo[kcuu1]}" "$history_search_up_widget"
[[ -n "${terminfo[kcud1]-}" ]] && bindkey "${terminfo[kcud1]}" "$history_search_down_widget"
unset history_search_up_widget history_search_down_widget

# ------------------------------------------------------------------------------
# 4. Plugins
# ------------------------------------------------------------------------------

ZSH_PLUGIN_HOME="${ZSH_PLUGIN_HOME:-$HOME/.oh-my-zsh/custom/plugins}"
ZSH_ARCH_PLUGIN_HOME="/usr/share/zsh/plugins"
ZSH_LEGACY_PLUGIN_HOME="$HOME/.zsh/plugins"

# git
if [[ -r "$ZSH_LEGACY_PLUGIN_HOME/git/git.plugin.zsh" ]]; then
  source "$ZSH_LEGACY_PLUGIN_HOME/git/git.plugin.zsh"
fi

# sudo
if [[ -r "$ZSH_LEGACY_PLUGIN_HOME/sudo/sudo.plugin.zsh" ]]; then
  source "$ZSH_LEGACY_PLUGIN_HOME/sudo/sudo.plugin.zsh"
fi

# z (directory jumper)
if [[ -r "$ZSH_LEGACY_PLUGIN_HOME/z/z.plugin.zsh" ]]; then
  source "$ZSH_LEGACY_PLUGIN_HOME/z/z.plugin.zsh"
fi

# autosuggestions
if [[ -r "$ZSH_PLUGIN_HOME/zsh-autosuggestions/zsh-autosuggestions.zsh" ]]; then
  source "$ZSH_PLUGIN_HOME/zsh-autosuggestions/zsh-autosuggestions.zsh"
  bindkey '^\' autosuggest-accept
elif [[ -r "$ZSH_ARCH_PLUGIN_HOME/zsh-autosuggestions/zsh-autosuggestions.zsh" ]]; then
  source "$ZSH_ARCH_PLUGIN_HOME/zsh-autosuggestions/zsh-autosuggestions.zsh"
  bindkey '^\' autosuggest-accept
fi

# syntax highlighting (load last)
if [[ -r "$ZSH_PLUGIN_HOME/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]]; then
  source "$ZSH_PLUGIN_HOME/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
elif [[ -r "$ZSH_ARCH_PLUGIN_HOME/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]]; then
  source "$ZSH_ARCH_PLUGIN_HOME/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
fi

unset ZSH_PLUGIN_HOME ZSH_ARCH_PLUGIN_HOME ZSH_LEGACY_PLUGIN_HOME

# ------------------------------------------------------------------------------
# 5. PATH
# ------------------------------------------------------------------------------

# Remove stray node_modules home entries.
path=(${path:#/usr/lib/node_modules/bin/home/*})

# Prepend core user directories.
path=(
  /usr/lib/node_modules/bin
  "$HOME/.npm-global/bin"
  "$HOME/.local/bin"
  $path
)
export PATH

# Prepend ~/bin for user scripts.
path=("$HOME/bin" $path)
export PATH

# Prepend npm global (re-prioritize).
export PATH="$HOME/.npm-global/bin:$PATH"

# Prepend ~/.local/bin (cursor / general user tools).
export PATH="$HOME/.local/bin:$PATH"

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

# ------------------------------------------------------------------------------
# 6. Aliases
# ------------------------------------------------------------------------------

# General
alias cfast='nvim ~/.config/fastfetch/'
alias ckitty='nvim ~/.config/kitty'
alias cl='clear'
alias down='sudo pacman -S'
alias l="ls -a"
alias ll='lsd -l'
alias lla='lsd -la'
alias ls='lsd'
alias n='nvim'
alias open="xdg-open"
alias upd='sudo pacman -Syu'
alias y='yazi'
alias zshrc='nvim ~/.zshrc'

# Directory navigation
alias cd..='cd ..'

# Git
alias gita='git add .'
alias gitc='git commit -m '
alias gitp='git push'

# Keep a few core git shortcuts available even without Oh My Zsh plugin loading.
alias gl='git pull'
alias gp='git push'
alias gst='git status'

# Conda environments
alias condaa='conda activate'
alias condac='conda create -n'
alias condad='conda deactivate'
alias cs485='conda activate cs485'
alias torch-cu128='conda activate torch-cu128'
alias transformers='conda activate transformers'

# Python venv
alias uva='source .venv/bin/activate'

# Fastfetch random
if [[ -x "$HOME/bin/fastfetch-random" ]]; then
  alias fastfetch="$HOME/bin/fastfetch-random"
fi

# ------------------------------------------------------------------------------
# 7. Conda (Lazy Loading)
# ------------------------------------------------------------------------------

__load_conda() {
  unset -f conda __load_conda

  local conda_root="$HOME/miniconda3"
  local conda_setup

  if [[ -x "$conda_root/bin/conda" ]]; then
    conda_setup="$("$conda_root/bin/conda" shell.zsh hook 2>/dev/null)"
    if [[ $? -eq 0 && -n "$conda_setup" ]]; then
      eval "$conda_setup"
    elif [[ -r "$conda_root/etc/profile.d/conda.sh" ]]; then
      source "$conda_root/etc/profile.d/conda.sh"
    else
      path=("$conda_root/bin" $path)
      export PATH
    fi
  fi
}

conda() {
  __load_conda
  conda "$@"
}

# ------------------------------------------------------------------------------
# 8. Prompt (Agnoster-like, without Oh My Zsh)
# ------------------------------------------------------------------------------

AGNOSTER_SEGMENT_SEPARATOR=''
AGNOSTER_BRANCH_ICON=''
AGNOSTER_DETACHED_ICON='➦'
AGNOSTER_TAG_ICON='◈'

agnoster_prompt_segment() {
  local bg="$1"
  local fg="$2"
  local text="$3"

  if [[ -n "$AGNOSTER_CURRENT_BG" && "$AGNOSTER_CURRENT_BG" != "$bg" ]]; then
    print -n " %{%K{$bg}%F{$AGNOSTER_CURRENT_BG}%}${AGNOSTER_SEGMENT_SEPARATOR}%{%F{$fg}%} "
  else
    print -n "%{%K{$bg}%F{$fg}%} "
  fi

  AGNOSTER_CURRENT_BG="$bg"
  print -n -- "$text"
}

agnoster_prompt_end() {
  if [[ -n "$AGNOSTER_CURRENT_BG" ]]; then
    print -n " %{%k%F{$AGNOSTER_CURRENT_BG}%}${AGNOSTER_SEGMENT_SEPARATOR}%{%f%}"
  fi
}

agnoster_prompt_context() {
  if [[ $EUID -eq 0 || -n "$SSH_CONNECTION" || "$USER" != "${DEFAULT_USER:-$LOGNAME}" ]]; then
    agnoster_prompt_segment black white "$(print -P '%n@%m')"
  fi
}

agnoster_prompt_env() {
  local env_name=""

  if [[ -n "$CONDA_DEFAULT_ENV" ]]; then
    env_name="$CONDA_DEFAULT_ENV"
  elif [[ -n "$VIRTUAL_ENV" ]]; then
    env_name="${VIRTUAL_ENV:t}"
  fi

  if [[ -n "$env_name" ]]; then
    agnoster_prompt_segment blue black "$env_name"
  fi
}

agnoster_git_segment() {
  command -v git >/dev/null || return
  command git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return

  local ref repo_path git_bg git_fg dirty_state git_marks mode branch_icon
  local ahead behind counts
  local -a count_parts

  repo_path="$(command git rev-parse --git-dir 2>/dev/null)"
  ref="$(command git symbolic-ref --quiet --short HEAD 2>/dev/null)" || \
    ref="${AGNOSTER_TAG_ICON} $(command git describe --exact-match --tags HEAD 2>/dev/null)" || \
    ref="${AGNOSTER_DETACHED_ICON} $(command git rev-parse --short HEAD 2>/dev/null)"

  dirty_state="$(command git status --porcelain --ignore-submodules=dirty 2>/dev/null)"
  if [[ -n "$dirty_state" ]]; then
    git_bg="yellow"
    git_fg="black"
  else
    git_bg="green"
    git_fg="black"
  fi

  branch_icon="$AGNOSTER_BRANCH_ICON"
  counts="$(command git rev-list --left-right --count @{upstream}...HEAD 2>/dev/null)"
  if [[ -n "$counts" ]]; then
    count_parts=(${(z)counts})
    behind="${count_parts[1]:-0}"
    ahead="${count_parts[2]:-0}"
    if (( ahead > 0 && behind > 0 )); then
      branch_icon='⇅'
    elif (( ahead > 0 )); then
      branch_icon='↱'
    elif (( behind > 0 )); then
      branch_icon='↰'
    fi
  fi

  git_marks=""
  if [[ -n "$dirty_state" ]]; then
    if print -r -- "$dirty_state" | command grep -q '^[AMDRCU]'; then
      git_marks+='✚'
    fi
    if print -r -- "$dirty_state" | command grep -q '^.[MTD]'; then
      git_marks+='±'
    fi
    if print -r -- "$dirty_state" | command grep -q '??'; then
      git_marks+='?'
    fi
  fi

  mode=""
  if [[ -e "${repo_path}/BISECT_LOG" ]]; then
    mode=' <B>'
  elif [[ -e "${repo_path}/MERGE_HEAD" ]]; then
    mode=' >M<'
  elif [[ -e "${repo_path}/rebase" || -e "${repo_path}/rebase-apply" || -e "${repo_path}/rebase-merge" || -e "${repo_path}/../.dotest" ]]; then
    mode=' >R>'
  fi

  agnoster_prompt_segment "$git_bg" "$git_fg" "${branch_icon} ${ref}${git_marks:+ ${git_marks}}${mode}"
}

agnoster_status_segment() {
  local last_status="$1"
  local status_text=""

  if (( last_status != 0 )); then
    status_text+="✘ ${last_status}"
  fi

  if (( EUID == 0 )); then
    [[ -n "$status_text" ]] && status_text+=" "
    status_text+="⚡"
  fi

  if (( ${#jobstates} > 0 )); then
    [[ -n "$status_text" ]] && status_text+=" "
    status_text+="⚙"
  fi

  if [[ -n "$status_text" ]]; then
    agnoster_prompt_segment black white "$status_text"
  fi
}

agnoster_build_prompt() {
  local last_status="$?"
  AGNOSTER_CURRENT_BG=""

  agnoster_status_segment "$last_status"
  agnoster_prompt_context
  agnoster_prompt_env
  agnoster_prompt_segment blue black "$(print -P '%~')"
  agnoster_git_segment
  agnoster_prompt_end

  print
  if (( last_status == 0 )); then
    print -n '%{%F{green}%}❯%{%f%} '
  else
    print -n '%{%F{red}%}❯%{%f%} '
  fi
}

PROMPT='$(agnoster_build_prompt)'

# ------------------------------------------------------------------------------
# 9. Startup
# ------------------------------------------------------------------------------

# Run random fastfetch once for each new interactive zsh.
run_random_fastfetch() {
  emulate -L zsh
  setopt null_glob

  command -v fastfetch >/dev/null || return 0

  local logo_dir="$HOME/.config/fastfetch/logo"
  local -a logos
  logos=("$logo_dir"/braille-logo_*.txt(N-.))

  if (( ${#logos} > 0 )); then
    local logo="${logos[$(( RANDOM % ${#logos} + 1 ))]}"
    command fastfetch --logo-type file --logo "$logo" || true
  else
    command fastfetch --logo none || true
  fi
}

if [[ -o interactive && -z "${__RUN_RANDOM_FASTFETCH_DONE-}" ]]; then
  typeset -g __RUN_RANDOM_FASTFETCH_DONE=1
  run_random_fastfetch
fi

# (disabled) Fastfetch resize hook.
# source /home/chakew/Downloads/project/fastfetch/scripts/fastfetch-resize.zsh

# ------------------------------------------------------------------------------
# 10. Proxy (Clash)
# ------------------------------------------------------------------------------

export http_proxy="http://127.0.0.1:7890"
export https_proxy="http://127.0.0.1:7890"
export all_proxy="socks5://127.0.0.1:7891"

export HTTP_PROXY="$http_proxy"
export HTTPS_PROXY="$https_proxy"
export ALL_PROXY="$all_proxy"

# ------------------------------------------------------------------------------
# 11. Tools & CLI Integrations
# ------------------------------------------------------------------------------

# --- jj (Jujutsu) ---
autoload -U compinit
compinit
source <(COMPLETE=zsh jj)

# --- codex ---
codex1() {
    CODEX_HOME="$HOME/.codex-plus1" command codex "$@"
}

codex2() {
    CODEX_HOME="$HOME/.codex-plus2" command codex "$@"
}
# --- cursor ---
export CURSOR_API_KEY='crsr_ba850e8ecf85a3d920c79f8136c6b1793284225b298d12bb1bdeaae14814f769'

# --- bun ---
[ -s "/home/chakew/.bun/_bun" ] && source "/home/chakew/.bun/_bun"

# --- grok ---
# >>> grok installer >>>
export PATH="$HOME/.grok/bin:$PATH"
fpath=(~/.grok/completions/zsh $fpath)
autoload -Uz compinit && compinit -C
# <<< grok installer <<<

# --- deepseek ---
export ANTHROPIC_BASE_URL=https://api.deepseek.com/anthropic
export ANTHROPIC_AUTH_TOKEN=sk-7c7536e23fb641dbacd96ffae8d43e39
export ANTHROPIC_MODEL=deepseek-v4-pro[1m]
export ANTHROPIC_DEFAULT_OPUS_MODEL=deepseek-v4-pro[1m]
export ANTHROPIC_DEFAULT_SONNET_MODEL=deepseek-v4-pro[1m]
export ANTHROPIC_DEFAULT_HAIKU_MODEL=deepseek-v4-flash
export CLAUDE_CODE_SUBAGENT_MODEL=deepseek-v4-flash
export CLAUDE_CODE_EFFORT_LEVEL=max

# ------------------------------------------------------------------------------
# 12. Local Overrides
# ------------------------------------------------------------------------------

# Machine-local/private overrides. Keep this last so install.sh can manage
# ~/.zshrc while preserving local values in ~/.zshrc.local.
if [[ -r "$HOME/.zshrc.local" ]]; then
  source "$HOME/.zshrc.local"
fi

# kimi-code
export PATH="/home/chakew/.kimi-code/bin:$PATH"
