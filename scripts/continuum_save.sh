#!/usr/bin/env bash

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

source "$CURRENT_DIR/helpers.sh"
source "$CURRENT_DIR/variables.sh"
source "$CURRENT_DIR/shared.sh"

supported_tmux_version_ok() {
  "$CURRENT_DIR/check_tmux_version.sh" "$SUPPORTED_VERSION"
}

get_interval() {
    # TMUX_CONTINUUM_SAVE_INTERVAL defined in tmux.conf
    if [ $TMUX_CONTINUUM_SAVE_INTERVAL ]; then
        echo $TMUX_CONTINUUM_SAVE_INTERVAL
        return
    fi
    # set-environment -g TMUX_CONTINUUM_SAVE_INTERVAL '30'
    # tmux show-options -g
    get_tmux_option "$auto_save_interval_option" "$auto_save_interval_default"
}

enough_time_since_last_run_passed() {
  local last_saved_timestamp="$(cat ~/.tmux/resurrect/continuum-save-last-timestamp 2>/dev/null)"
  local interval_minutes="$(get_interval)"
  local interval_seconds="$((interval_minutes * 60))"
  local next_run="$((last_saved_timestamp + $interval_seconds))"
  [ "$(current_timestamp)" -ge "$next_run" ]
}

fetch_and_run_tmux_resurrect_save_script() {
  # @resurrect-save-script-path ~/.tmux/plugins/tmux-resurrect/scripts/save.sh
  # tmux show-options -g
  local resurrect_save_script_path="$(get_tmux_option "$resurrect_save_path_option" "")"
  if [ -n "$resurrect_save_script_path" ]; then
    "$resurrect_save_script_path" "quiet" >/dev/null 2>&1 &
    echo "$(date +%s)" > ~/.tmux/resurrect/continuum-save-last-timestamp
    # set_last_save_timestamp
  fi
}

acquire_lock() {
  # Sometimes tmux starts multiple saves in parallel. We want only one
  # save to be running, otherwise we can get corrupted saved state.
  local lockdir_prefix="/tmp/tmux-continuum-$(current_tmux_server_pid)-lock-"
  # The following implements a lock that auto-expires after 100...200s.
  local lock_generation=$((`date +%s` / 100))
  local lockdir1="${lockdir_prefix}${lock_generation}"
  local lockdir2="${lockdir_prefix}$(($lock_generation + 1))"
  if mkdir "$lockdir1"; then
    trap "rmdir "$lockdir1"" EXIT
    if mkdir "$lockdir2"; then
      trap "rmdir "$lockdir1" "$lockdir2"" EXIT
      return 0
    fi
  fi
  return 1  # Someone else has the lock.
}

fix_tab_name() {
    if [ "$TERM_PROGRAM" = tmux ]; then
        # session name (main):
        #       tmux new -A -s main
        # pane name (sync in UI):
        #       tmux list-panes -a -F "#{window_index} #{pane_title}"
        #       tmux display-message -p '#T'
        # window name (not sync in UI, same with tab name editable):
        #       tmux list-windows -F "#{window_index} #{window_name}"
        #       tmux display-message -p '#W'
        # 遍历所有窗格
        tmux list-panes -a -F "#{window_index} #{pane_title}" | while read -r window_index pane_title; do
            # 获取对应的窗口名称
            window_name=$(tmux list-windows -F "#{window_index} #{window_name}" | grep "^$window_index " | awk '{print $2}')
            
            # 检查窗格名称与窗口名称是否不同
            if [[ "$pane_title" != "$window_name" && $pane_name != "" ]]; then
                # 修改窗格名称为窗口名称
                tmux select-pane -T "$window_name" -t "$window_index"
                tmux rename-window "$window_name"
                # echo "Updated pane title from '$pane_title' to '$window_name' for window index $window_index"
            fi  
        done
    fi
}

main() {
  if enough_time_since_last_run_passed && acquire_lock; then
    echo "$(date +'%Y-%m-%d %H:%M:%S') tmux session saved" > /tmp/.tmux.last
    fix_tab_name
    fetch_and_run_tmux_resurrect_save_script
  fi
}
main
