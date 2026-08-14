#!/usr/bin/env bash
# == UNIVERSAL aliases ==

reload() {
    source ~/.bashrc
    $SYSDIR/reload/reload.sh "$@"
}

logout() {
    if ! command -v loginctl &>/dev/null; then
        echo "logout: loginctl is unavailable" >&2
        return 1
    fi

    command loginctl terminate-session ""
}

alias deploy-noruelga='$BASHRC/bin/noruelga.sh'

alias launcher='$LAUNCHER'
alias lc='$LAUNCHER'
alias files='$FILEMANAGER'
alias browser='$BROWSER'
alias eup='$EDITOR $BASHRC/modules/universal/paths.sh'
alias eua='$EDITOR $BASHRC/modules/universal/aliases.sh'
alias el='$EDITOR $BASHRC/modules/local.sh'
alias ed='$EDITOR $BASHRC/modules/defaults/defaults.sh'
alias tx='. $BASHRC/bin/tx'

alias compose='docker-compose'
alias compose-r='docker-compose down && docker-compose up -d'

alias gpush='git add -A && git commit && git push'
alias venv='source ./venv/bin/activate'

# Print install one-liner (for spreading the config)
alias mitosis='echo "curl -fsSL https://raw.githubusercontent.com/DeprecatedLuar/lushrc/main/install.sh | bash"'




#------------------------------------------------------

# Basic ls aliases (use exa if available)
if command -v exa &>/dev/null; then
    alias ls='exa'
    alias ll='exa -alF'
    alias la='exa -a'
    alias l='exa -F'
else
    alias ll='ls -alF --color=auto'
    alias la='ls -a --color=auto'
    alias l='ls -F --color=auto'
fi

# Kitty SSH (better terminal integration)
alias ksh='kitty +kitten ssh'
alias fj='$TERMINAL'
alias offload='nvidia-offload'

# Mark connections typed in an interactive lushrc shell. The lsh binary still
# shadows ssh for scripts, but smart tmux/Mosh routing is opt-in at this shell
# boundary so PTY-based automation keeps normal SSH semantics.
if [[ $- == *i* ]]; then
    lsh() {
        LSH_INTERACTIVE_SHELL=1 command "$BASHRC/bin/lsh" "$@"
    }

    ssh() {
        LSH_INTERACTIVE_SHELL=1 command "$BASHRC/bin/lsh" "$@"
    }
fi

# Add an "alert" alias for long running commands.  Use like so:
#   sleep 10; alert
alias alert='notify-send --urgency=low -i "$([ $? = 0 ] && echo terminal || echo error)" "$(history|tail -n1|sed -e '\''s/^\s*[0-9]\+\s*//;s/[;&|]\s*alert$//'\'')"'
