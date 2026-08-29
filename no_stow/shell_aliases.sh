if [ "$(uname -s)" = "Darwin" ]; then
  alias ll='ls -al -G'
else
  alias ll='ls -al --color=auto'
fi

alias lg='lazygit'
alias v='nvim'
alias vim='nvim'

theme_ssh() {
  ruby "$HOME/.dots/themes/theme_ssh.rb" "$@"
}

alias tksv='tmux kill-server'
alias tkss='tmux kill-session -t'
mux() {
  local workspace_launcher="$HOME/.dots/no_stow/bin/tmux/start-workspace"
  local target="${1:-}"

  if [[ $# -eq 1 ]] && [[ -x "$workspace_launcher" ]] && "$workspace_launcher" --check "$target"; then
    if ! tmux has-session -t "$target" 2>/dev/null; then
      "$workspace_launcher" "$target" || return
    fi

    if [[ -n "${TMUX:-}" ]]; then
      tmux switch-client -t "$target"
    else
      tmux attach-session -t "$target"
    fi
    return
  fi

  command tmuxinator "$@"
}

alias gca='git commit -n --amend'
alias gca!='git commit -n --amend --no-edit'
alias gitc='git commit -n -v -m'
alias gstt='git stash save temp'
alias gc-='git checkout -'
alias gro='git rebase --onto'
alias grs1='git reset --soft HEAD~1'
alias grsa='git reset --soft HEAD@{1}'
alias gitct='gitc "temp"'
alias gsta='git stash save'

alias ber='bundle exec rspec'
alias rdr='rails db:rollback:primary'

lf() {
  local dir ans
  dir="$(command lf -print-last-dir "$@")" || return
  [ -n "$dir" ] || return
  [ "$dir" = "$PWD" ] && return

  printf 'cd to %s? [y/N] ' "$dir"
  read -r ans
  case "$ans" in
    y|Y) cd "$dir" ;;
  esac
}
