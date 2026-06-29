#!/bin/bash
# Toggle themes for Vim, Zsh, and Hyper (macOS)

HYPER="$HOME/.hyper.js"
GHOSTTY="$HOME/.config/ghostty/config"
TMUX_CONF="$HOME/.tmux.conf"
NOM="$HOME/Library/Application Support/nom/config.yml"

# Resolve symlinks
REAL_HYPER="$(readlink "$HYPER" || echo "$HYPER")"
REAL_GHOSTTY="$(readlink "$GHOSTTY" || echo "$GHOSTTY")"
REAL_TMUX="$(readlink "$TMUX_CONF" || echo "$TMUX_CONF")"
REAL_NOM="$(readlink "$NOM" || echo "$NOM")"
# config is itself in a symlinked dir; resolve fully
[ -L "$REAL_GHOSTTY" ] || REAL_GHOSTTY="$(cd "$(dirname "$GHOSTTY")" && pwd -P)/$(basename "$GHOSTTY")"

STATUS=""

# --- Source of truth: flip the mode file ---
# Everything derives from this one untracked file. zsh (-> bat/less/ls), ghostty,
# vim and nvim all READ it at startup, so toggling rewrites no tracked file for
# them. Apps further down that lack a read path are still set from $MODE.
THEME_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/isg/theme"
cur="$(cat "$THEME_FILE" 2>/dev/null || echo light)"
[ "$cur" = dark ] && MODE=light || MODE=dark
mkdir -p "$(dirname "$THEME_FILE")"
echo "$MODE" > "$THEME_FILE"
STATUS+="mode: $cur -> $MODE\n"
STATUS+="Vim/Neovim: vs_$MODE (on next start)\n"
STATUS+="Zsh/bat: $MODE (new shells; 'exec zsh' to refresh open ones)\n"

# --- Hyper: toggle comment on localPlugins ---
if grep -q '^[[:space:]]*localPlugins:[[:space:]]*\["light"\],' "$REAL_HYPER"; then
    sed -i '' 's/^[[:space:]]*localPlugins:[[:space:]]*\["light"\],/   \/\/ localPlugins: ["light"],/' "$REAL_HYPER"
    STATUS+="Hyper: dark\n"
elif grep -q '^[[:space:]]*\/\/ localPlugins:[[:space:]]*\["light"\],' "$REAL_HYPER"; then
    sed -i '' 's/^[[:space:]]*\/\/ localPlugins:[[:space:]]*\["light"\],/   localPlugins: ["light"],/' "$REAL_HYPER"
    STATUS+="Hyper: light\n"
else
    STATUS+="Hyper: localPlugins not found\n"
fi

# --- Ghostty: select theme via the theme-active.conf include symlink ---
# One symlink swap replaces five seds on the tracked config; theme-active.conf
# is gitignored, so toggling never dirties the repo.
if [ -f "$REAL_GHOSTTY" ]; then
    GHOSTTY_DIR="$(dirname "$REAL_GHOSTTY")"
    ln -sf "theme-$MODE.conf" "$GHOSTTY_DIR/theme-active.conf"
    STATUS+="Ghostty: $MODE (reload open windows with cmd+shift+,)\n"
else
    STATUS+="Ghostty: config not found\n"
fi

# --- Tmux: toggle theme ---
if [ -f "$REAL_TMUX" ]; then
    if grep -q "^# theme=light" "$REAL_TMUX"; then
        # Light -> Dark
        sed -i '' 's/^# theme=light/# theme=dark/' "$REAL_TMUX"
        sed -i '' 's/status-style "bg=default,fg=#555555"/status-style "bg=default,fg=#999999"/' "$REAL_TMUX"
        sed -i '' 's/window-status-style "bg=default,fg=#777777"/window-status-style "bg=default,fg=#888888"/' "$REAL_TMUX"
        sed -i '' 's/window-status-current-style "bg=default,fg=#000000,bold"/window-status-current-style "bg=default,fg=#cccccc,bold"/' "$REAL_TMUX"
        sed -i '' 's/status-left-style "bg=default,fg=#555555"/status-left-style "bg=default,fg=#999999"/' "$REAL_TMUX"
        sed -i '' 's/status-right-style "bg=default,fg=#555555"/status-right-style "bg=default,fg=#999999"/' "$REAL_TMUX"
        sed -i '' 's/message-style "bg=default,fg=#333333"/message-style "bg=default,fg=#bbbbbb"/' "$REAL_TMUX"
        sed -i '' 's/pane-border-style "fg=#cccccc"/pane-border-style "fg=#444444"/' "$REAL_TMUX"
        sed -i '' 's/pane-active-border-style "fg=#888888"/pane-active-border-style "fg=#666666"/' "$REAL_TMUX"
        STATUS+="Tmux: dark\n"
    elif grep -q "^# theme=dark" "$REAL_TMUX"; then
        # Dark -> Light
        sed -i '' 's/^# theme=dark/# theme=light/' "$REAL_TMUX"
        sed -i '' 's/status-style "bg=default,fg=#999999"/status-style "bg=default,fg=#555555"/' "$REAL_TMUX"
        sed -i '' 's/window-status-style "bg=default,fg=#888888"/window-status-style "bg=default,fg=#777777"/' "$REAL_TMUX"
        sed -i '' 's/window-status-current-style "bg=default,fg=#cccccc,bold"/window-status-current-style "bg=default,fg=#000000,bold"/' "$REAL_TMUX"
        sed -i '' 's/status-left-style "bg=default,fg=#999999"/status-left-style "bg=default,fg=#555555"/' "$REAL_TMUX"
        sed -i '' 's/status-right-style "bg=default,fg=#999999"/status-right-style "bg=default,fg=#555555"/' "$REAL_TMUX"
        sed -i '' 's/message-style "bg=default,fg=#bbbbbb"/message-style "bg=default,fg=#333333"/' "$REAL_TMUX"
        sed -i '' 's/pane-border-style "fg=#444444"/pane-border-style "fg=#cccccc"/' "$REAL_TMUX"
        sed -i '' 's/pane-active-border-style "fg=#666666"/pane-active-border-style "fg=#888888"/' "$REAL_TMUX"
        STATUS+="Tmux: light\n"
    else
        STATUS+="Tmux: theme marker not found\n"
    fi
    # Reload tmux config if tmux is running
    tmux source-file "$TMUX_CONF" 2>/dev/null && STATUS+="Tmux: config reloaded\n"
else
    STATUS+="Tmux: config not found\n"
fi

# --- nom (RSS reader): toggle glamour theme (article rendering) ---
if [ -f "$REAL_NOM" ]; then
    if grep -q "^  glamour: light" "$REAL_NOM"; then
        sed -i '' 's/^  glamour: light/  glamour: dark/' "$REAL_NOM"
        STATUS+="nom: dark\n"
    elif grep -q "^  glamour: dark" "$REAL_NOM"; then
        sed -i '' 's/^  glamour: dark/  glamour: light/' "$REAL_NOM"
        STATUS+="nom: light\n"
    else
        STATUS+="nom: glamour line not found\n"
    fi
else
    STATUS+="nom: config not found\n"
fi

# --- Splash: mascot + status, banner-style (mascots.sh) ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/mascots.sh"
clear
splash_render "$MODE" "$STATUS"
