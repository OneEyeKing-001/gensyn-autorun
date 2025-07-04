#!/bin/bash

SESSION="rl_swarm"
LOG_FILE="/root/rl_watchdog.log"
ERROR_LOG="/root/rl_swarm_error.log"
CHECK_LOG="/root/rl-swarm/console.log"  # Output log of run_rl_swarm.sh

# Properly quoted and escaped restart command using a here-doc
RESTART_COMMAND=$(cat << 'EOF'
sed -i 's/startup_timeout: float = *15/startup_timeout: float = 120/' ~/rl-swarm/.venv/lib/python3.12/site-packages/hivemind/p2p/p2p_daemon.py
tmux new-session -d -s rl_swarm bash -c '
cd ~/rl-swarm
python3 -m venv .venv
source .venv/bin/activate
chmod +x run_rl_swarm.sh
expect << EOD
spawn ./run_rl_swarm.sh
expect {
    "Would you like to push models you train in the RL swarm to the Hugging Face Hub?" {
        send "n\r"
        exp_continue
    }
    "Enter the name of the model you want to use" {
        send "Gensyn/Qwen2.5-0.5B-Instruct\r"
    }
    eof
}
EOD
'
EOF
)

# Known fatal error patterns
declare -a FATAL_ERRORS=(
    "ValueError: expected sequence of length 2 at dim 1"
    "Exception occurred during game run"
    "Traceback (most recent call last):"
    "RuntimeError:"
)

echo "🔁 RL-Swarm Watchdog started at $(date)" >> "$LOG_FILE"

while true; do
    should_restart=false

    # Check if tmux session exists
    if tmux has-session -t $SESSION 2>/dev/null; then
        # Check if main process inside tmux is alive
        PID=$(tmux list-panes -t $SESSION -F "#{pane_pid}")
        if ! ps -p $PID > /dev/null; then
            echo "[$(date)] ⚠️ Process $PID is dead. Will restart." >> "$LOG_FILE"
            should_restart=true
        fi
    else
        echo "[$(date)] ❌ No tmux session. Will restart." >> "$LOG_FILE"
        should_restart=true
    fi

    # Scan log for fatal errors
    if [ -f "$CHECK_LOG" ]; then
        for err in "${FATAL_ERRORS[@]}"; do
            if grep -q "$err" "$CHECK_LOG"; then
                echo "[$(date)] 🚨 Fatal error detected: $err" >> "$LOG_FILE"
                grep "$err" "$CHECK_LOG" >> "$ERROR_LOG"
                should_restart=true
                break
            fi
        done
    fi

    # Restart if needed
    if [ "$should_restart" = true ]; then
        tmux kill-session -t $SESSION 2>/dev/null
        eval "$RESTART_COMMAND"
        echo "[$(date)] 🔁 RL Swarm restarted." >> "$LOG_FILE"
        sleep 30  # Allow startup time
    fi

    sleep 60  # Check every 60 seconds
done
