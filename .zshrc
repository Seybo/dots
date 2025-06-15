# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:$HOME/.local/bin:/usr/local/bin:$PATH
eval "$(brew shellenv)"
# Path to your Oh My Zsh installation.
export ZSH="$HOME/.oh-my-zsh"
# this is the defalut way to set autosuggetions but it doesn't work for example with git stash pop/apply<tab>
# autoload -Uz compinit
# compinit
#
# while this works
remove_conflicting_git_completions() {
    local git_completion_bash="$HOMEBREW_PREFIX/share/zsh/site-functions/git-completion.bash"
    local git_completion_zsh="$HOMEBREW_PREFIX/share/zsh/site-functions/_git"

    [ -e "$git_completion_bash" ] && rm "$git_completion_bash"
    [ -e "$git_completion_zsh" ] && rm "$git_completion_zsh"
}
# Delete the brew version of `git` completions because the built in ZSH
# ones are objectively better (and work with aliases)
# The reason this runs every time is because brew re-adds these files
# on `brew upgrade` (and other events)
remove_conflicting_git_completions
# Add Homebrew's site functions to fpath (minus git, because that causes conflicts)
# https://github.com/orgs/Homebrew/discussions/2797
# https://github.com/ohmyzsh/ohmyzsh/issues/8037
# https://github.com/ohmyzsh/ohmyzsh/issues/7062
fpath=($HOMEBREW_PREFIX/share/zsh/site-functions $fpath)

# Include hidden files in autocompletion
setopt globdots

# Set name of the theme to load --- if set to "random", it will
# load a random theme each time Oh My Zsh is loaded, in which case,
# to know which specific one was loaded, run: echo $RANDOM_THEME
# See https://github.com/ohmyzsh/ohmyzsh/wiki/Themes
ZSH_THEME="robbyrussell"

# Set list of themes to pick from when loading at random
# Setting this variable when ZSH_THEME=random will cause zsh to load
# a theme from this variable instead of looking in $ZSH/themes/
# If set to an empty array, this variable will have no effect.
# ZSH_THEME_RANDOM_CANDIDATES=( "robbyrussell" "agnoster" )

# Uncomment the following line to use case-sensitive completion.
# CASE_SENSITIVE="true"

# Uncomment the following line to use hyphen-insensitive completion.
# Case-sensitive completion must be off. _ and - will be interchangeable.
HYPHEN_INSENSITIVE="true"

# Uncomment one of the following lines to change the auto-update behavior
# zstyle ':omz:update' mode disabled  # disable automatic updates
# zstyle ':omz:update' mode auto      # update automatically without asking
# zstyle ':omz:update' mode reminder  # just remind me to update when it's time

# Uncomment the following line to change how often to auto-update (in days).
# zstyle ':omz:update' frequency 13

# Uncomment the following line if pasting URLs and other text is messed up.
# DISABLE_MAGIC_FUNCTIONS="true"

# Uncomment the following line to disable colors in ls.
DISABLE_LS_COLORS="true"

# Uncomment the following line to disable auto-setting terminal title.
# DISABLE_AUTO_TITLE="true"

# Uncomment the following line to enable command auto-correction.
# ENABLE_CORRECTION="true"

# Uncomment the following line to display red dots whilst waiting for completion.
# You can also set it to another string to have that shown instead of the default red dots.
# e.g. COMPLETION_WAITING_DOTS="%F{yellow}waiting...%f"
# Caution: this setting can cause issues with multiline prompts in zsh < 5.7.1 (see #5765)
# COMPLETION_WAITING_DOTS="true"

# Uncomment the following line if you want to disable marking untracked files
# under VCS as dirty. This makes repository status check for large repositories
# much, much faster.
# DISABLE_UNTRACKED_FILES_DIRTY="true"

# Uncomment the following line if you want to change the command execution time
# stamp shown in the history command output.
# You can set one of the optional three formats:
# "mm/dd/yyyy"|"dd.mm.yyyy"|"yyyy-mm-dd"
# or set a custom format using the strftime function format specifications,
# see 'man strftime' for details.
# HIST_STAMPS="mm/dd/yyyy"

# Would you like to use another custom folder than $ZSH/custom?
# ZSH_CUSTOM=/path/to/new-custom-folder

# Which plugins would you like to load?
# Standard plugins can be found in $ZSH/plugins/
# Custom plugins may be added to $ZSH_CUSTOM/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
plugins=(
  asdf
  git
  heroku
  rails
  tmuxinator
  vi-mode
  zsh-autosuggestions
)
source $ZSH/oh-my-zsh.sh

# User configuration

# fancy ctrl-z
fancy-ctrl-z() {
  # 1) if INPUT BUFFER is empty, queue up an "fg"  
  if [[ -z $BUFFER ]]; then
    BUFFER="fg"
    zle accept-line       # execute the fg
  else
    # 2) otherwise push current line into history & clear screen
    zle push-input
    zle clear-screen
  fi
}
# register it as a ZLE widget and bind Ctrl-Z
zle -N fancy-ctrl-z fancy-ctrl-z
bindkey '^Z' fancy-ctrl-z

# stow
export STOW_DIR="$HOME/.dots"
source "$STOW_DIR/no_stow/.zsh_aliases_public"
source "$STOW_DIR/no_stow/bash_utils.sh"
source "$STOW_DIR/no_stow/rage_utils.sh"
source "$STOW_DIR/private/.zsh_aliases_private"
source "$STOW_DIR/private/.env"
# the whole env theme is managed by the theme script: themes/theme_switcher.rb and its zsh alias 'theme'
source "$STOW_DIR/no_stow/themes/active/fzf.zsh"

# export MANPATH="/usr/local/man:$MANPATH"

# You may need to manually set your language environment
# export LANG=en_US.UTF-8

export EDITOR='nvim'
eval "$(jump shell)"
eval "$(gdircolors -b ~/.dircolors)"
eval "$(thefuck --alias)"

export PATH="${ASDF_DATA_DIR:-$HOME/.asdf}/shims:$PATH"


# PostgreSQL
export PATH="/opt/homebrew/opt/postgresql@13/bin:$PATH"
# Optional: Set compiler flags for PostgreSQL 13
export LDFLAGS="-L/opt/homebrew/opt/postgresql@13/lib"
export CPPFLAGS="-I/opt/homebrew/opt/postgresql@13/include"
export PKG_CONFIG_PATH="/opt/homebrew/opt/postgresql@13/lib/pkgconfig"


# show with catalogs content with alt-c
# export FZF_ALT_C_OPTS="--preview 'tree -C {} | head -200'"
export FZF_DEFAULT_COMMAND='fd --type f --strip-cwd-prefix --hidden --follow --exclude .git --color=always'
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
# setup key bindings and fuzzy completion
source <(fzf --zsh)

# dev
export BROWSER_PATH="/Applications/Google Chrome Dev.app/Contents/MacOS/Google Chrome Dev"

eval "$(starship init zsh)"

# Start tmux automatically if not already inside a tmux session
if command -v tmux >/dev/null 2>&1; then
  if [ -z "$TMUX" ]; then
    tmux
  fi
fi
