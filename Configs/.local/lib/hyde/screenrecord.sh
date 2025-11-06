#!/usr/bin/env bash

set -eo pipefail

[[ "${HYDE_SHELL_INIT}" -ne 1 ]] && eval "$(hyde-shell init)"

RECORDER="wl-screenrec"
command -v "$RECORDER" &>/dev/null || RECORDER="wf-recorder"
if ! command -v "$RECORDER" &>/dev/null; then
    notify-send -a "HyDE Alert" "No screen recorder found. Try installing wl-screenrec or wf-recorder."
    echo "No screen recorder found. Try installing wl-screenrec or wf-recorder."
    exit 1
fi

LOCK_FILE="$HOME/.hypr_screenrecord_lock"

# Check for existing script instance
if [ -f "$LOCK_FILE" ]; then
    lock_pid=$(cat "$LOCK_FILE")
    if ps -p "$lock_pid" > /dev/null 2>&1; then
        # Kill the existing process and remove lock file
        kill "$lock_pid" 2>/dev/null || true
        # Find slupr process and kill it if exists
        if pgrep -x "slurp" > /dev/null; then
            pkill -x "slurp"
        fi
        rm -f "$LOCK_FILE"
        exit 1
    else
        rm -f "$LOCK_FILE"
    fi
fi

# Create lock file with current PID
echo $$ > "$LOCK_FILE"
# Ensure lock file is removed on exit
trap 'rm -f "$LOCK_FILE"' EXIT

USAGE() {
    cat <<USAGE

    Usage: 'hyde-shell screenrecord' [option]

        Using ${RECORDER} to record the screen.

    Options:

        --start         Start screen recording (stops any existing recording first)
        --toggle        Toggle screen recording (start if stopped, stop if running)
        --backend       Use 'wl-screenrec' or 'wf-recorder' as the backend
        --file          Specify the output file
        --quit          Stop the recording
        --help          Show this help message
        --              Pass additional arguments to '${RECORDER}'

    Note:

        Click and drag on the screen to select a region to record.
        To record the whole screen, simply click without dragging.

        Additional arguments are passed to '${RECORDER}'.

    Example:
        'hyde-shell screenrecord' --start -- --audio --codec libx264

        To see all available options for '${RECORDER}', run:
            ${RECORDER} --help

USAGE
}

handle_recording() {
    # Stop any existing recording
    if pgrep -x "$RECORDER" > /dev/null; then
        pkill -INT "$RECORDER"
        sleep 1
        notify-send -a "HyDE Alert" "Stopped existing recording" -i video
    fi

    save_dir="${XDG_VIDEOS_DIR:-$HOME/Videos}/Recordings"
    save_file=$(date +'%y%m%d_%Hh%Mm%Ss_recording.mp4')
    save_file_path="${FILE_PATH:-"${save_dir}/${save_file}"}"
    mkdir -p "$save_dir"

    parameters=()

    # Process additional arguments after --
    while [[ $# -gt 0 ]]; do
        if [[ "$1" == "--" ]]; then
            shift
            while [[ $# -gt 0 ]]; do
                parameters+=("$1")
                shift
            done
            break
        fi
        shift
    done

    OUTPUT="$(hyprctl -j monitors | jq -r '.[] | select(.focused==true) | .name')"
    GEOM="$(
        slurp -w 0 -b "#00000000" -c "#FFFFFF" -s "#00000055" -B "#00000000" -o | awk '{
            split($1, pos, ",");
            x = pos[1];
            y = pos[2];
            split($2, size, "x");
            width = size[1];
            height = size[2];
            if (width >= 16 && height >= 16) {
                print x","y" "width"x"height;
            }
        }'
    )"

    if [[ -z "$GEOM" ]]; then
        echo "Using whole screen for recording"
        [[ -n "$OUTPUT" ]] && parameters+=(--output "$OUTPUT")
    else
        parameters+=("--geometry" "$GEOM")
    fi

    tmp_thumbnail=$(mktemp -t thumbnail_XXXXXX.png)
    if [[ -z "$GEOM" ]]; then
        "$LIB_DIR/hyde/grimblast" save active "$tmp_thumbnail"
    else
        grim -g "$GEOM" "$tmp_thumbnail"
    fi

    # Start recording in the background
    "${RECORDER}" "${parameters[@]}" -f "${save_file_path}" &
    notify-send -a "HyDE Alert" "${RECORDER}: Recording started" -i "${tmp_thumbnail}"
}

# Process arguments with while loop
while [[ $# -gt 0 ]]; do
    case "$1" in
    --file)
        shift
        FILE_PATH="$1"
        ;;
    --backend)
        shift
        RECORDER="$1"
        ;;
    --start)
        handle_recording "$@"
        exit 0
        ;;
    --toggle)
        # Check if recording is already running
        if pgrep -x "$RECORDER" > /dev/null; then
            # Recording is active, stop it
            pkill -INT "$RECORDER"
            notify-send -a "HyDE Alert" "Recording stopped" -i video
        else
            # No recording active, start one
            handle_recording "$@"
        fi
        exit 0
        ;;
    --quit)
        if pgrep -x "$RECORDER" > /dev/null; then
            pkill -INT "$RECORDER"
            notify-send -a "HyDE Alert" "Recording stopped" -i video
        else
            notify-send -a "HyDE Alert" "No recording in progress" -i video
        fi
        exit 0
        ;;
    --help)
        USAGE
        exit 0
        ;;
    *)
        USAGE
        exit 1
        ;;
    esac
    shift
done

# If no arguments provided, show usage
if [[ $# -eq 0 ]]; then
    USAGE
fi
