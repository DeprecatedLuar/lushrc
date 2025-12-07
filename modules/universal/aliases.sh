#!/usr/bin/env bash
# == UNIVERSAL aliases ==

reload() {
    source ~/.bashrc
    $LIBDIR/reload.sh "$@"
}

alias deploy-noruelga='$LIBDIR/noruelga.sh'

alias eup='$EDITOR $BASHRC/modules/universal/paths.sh'
alias eua='$EDITOR $BASHRC/modules/universal/aliases.sh'
alias el='$EDITOR $BASHRC/modules/local.sh'

alias ed='$EDITOR $BASHRC/modules/defaults/defaults.sh'

alias tx='. $BASHRC/bin/tx'

alias compose='docker-compose'
alias compose-r='docker-compose down && docker-compose up -d'


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

# Add an "alert" alias for long running commands.  Use like so:
#   sleep 10; alert
alias alert='notify-send --urgency=low -i "$([ $? = 0 ] && echo terminal || echo error)" "$(history|tail -n1|sed -e '\''s/^\s*[0-9]\+\s*//;s/[;&|]\s*alert$//'\'')"'
