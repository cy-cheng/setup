#!/usr/bin/env fish
# Nixie look for fish + the tide prompt: greyscale, amber only for emphasis.
# Run once: fish ~/setup/hosts/expertbook/install/fish-prompt.fish
# (Needs fisher + ilancosman/tide@v6 installed.)

# ── Palette ──
set -l fg e9e6e1
set -l muted 8f8a84
set -l faint 5c5853
set -l amber ffac32
set -l amberDim c97824
set -l green 8fd18b
set -l red ff5c57

# ── Prompt layout ──
# left:  folder · git             (newline)  ❯
# right: exit status · duration · user@host (only over SSH) · jobs · python venv
set -U tide_left_prompt_items pwd git newline character
set -U tide_right_prompt_items status cmd_duration context jobs python
set -U tide_prompt_add_newline_before true
set -U tide_prompt_pad_items false

# Prompt arrow
set -U tide_character_icon ❯
set -U tide_character_color $amber
set -U tide_character_color_failure $red

# Folder: current + repo root in light text, the rest grey
set -U tide_pwd_color_anchors $fg
set -U tide_pwd_color_dirs $muted
set -U tide_pwd_color_truncated_dirs $faint
set -U tide_pwd_icon ""
set -U tide_pwd_icon_home ""
set -U tide_pwd_icon_unwritable ""

# Git: branch grey, changes in colour
set -U tide_git_icon ""
set -U tide_git_color_branch $muted
set -U tide_git_color_staged $green
set -U tide_git_color_dirty $amber
set -U tide_git_color_untracked $muted
set -U tide_git_color_stash $muted
set -U tide_git_color_upstream $muted
set -U tide_git_color_conflicted $red
set -U tide_git_color_operation $amber

# Right side
set -U tide_status_color $faint
set -U tide_status_color_failure $red
set -U tide_cmd_duration_color $muted
set -U tide_cmd_duration_threshold 3000
set -U tide_context_color_ssh $amberDim
set -U tide_context_color_root $red
set -U tide_context_color_default $muted
set -U tide_jobs_color $muted
set -U tide_python_color $muted

# ── Syntax highlighting ──
set -U fish_color_command $fg --bold
set -U fish_color_param $fg
set -U fish_color_option $muted
set -U fish_color_keyword $amber
set -U fish_color_quote $green
set -U fish_color_redirection $amberDim
set -U fish_color_end $amberDim
set -U fish_color_operator $amberDim
set -U fish_color_escape $amberDim
set -U fish_color_error $red
set -U fish_color_comment $faint --italics
set -U fish_color_autosuggestion $faint
set -U fish_color_valid_path --underline
set -U fish_color_search_match --background=2c2a27
set -U fish_color_selection --background=2c2a27
set -U fish_pager_color_prefix $amber --bold
set -U fish_pager_color_completion $fg
set -U fish_pager_color_description $muted
set -U fish_pager_color_progress $faint

tide reload 2>/dev/null
echo "Nixie prompt applied. Open a new terminal to see it."
