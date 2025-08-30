#!/bin/bash
set -euo pipefail

# Configuration
SESSION="rl_swarm"
RL_SWARM_DIR="/root/rl-swarm"
ERROR_LOG="/root/rl_swarm_error.log"
LOG_FILE="/root/rl_swarm_watchdog.log"
EXPECT_SCRIPT="/tmp/test_rl_swarm.exp"
CHECK_INTERVAL=30  # seconds

# Logging helper
log() {
    echo "[$(date)] $*" | tee -a "$LOG_FILE"
}

# Only restart for these errors or missing tmux
should_restart() {
    if ! tmux has-session -t "$SESSION" 2>/dev/null; then
        log "? Tmux session '$SESSION' not found."
        return 0
    fi

    if grep -qE "ValueError: expected sequence of length 2 at dim 1|Exception occurred during game run|Traceback \(most recent call last\):|An error was detected while running rl-swarm" "$ERROR_LOG"; then
        log "?? Matched fatal error in $ERROR_LOG"
        grep -E "ValueError: expected sequence of length 2 at dim 1|Exception occurred during game run|Traceback \(most recent call last\):|An error was detected while running rl-swarm" "$ERROR_LOG" >> "$LOG_FILE"
        return 0
    fi

    log "? No restart condition met."
    return 1
}



# Create Expect script to auto-answer prompts
write_expect_script() {
    cat > "$EXPECT_SCRIPT" << 'EOF'
#!/usr/bin/expect -f
set timeout -1  ;# Wait indefinitely

cd ~/rl-swarm
spawn ./run_rl_swarm.sh

expect {
    -re "Would you like to push models.*Hub.*" {
        send "n\r"
        exp_continue
    }
    -re "Enter the name of the model.*" {
        send "Gensyn/Qwen2.5-0.5B-Instruct\r"
        exp_continue
    }
    -re "Would you like your model to participate.*" {
        send "y\r"
        exp_continue
    }
    eof {
        exit
    }
}
EOF

chmod +x /tmp/test_rl_swarm.exp
}
# Restart tmux with expect wrapper
restart_rl_swarm() {
    log "?? Restarting RL Swarm..."

    # Kill existing session if any
    tmux kill-session -t "$SESSION" 2>/dev/null || true

    # Clear old error logs
    rm -f "$ERROR_LOG"

    # Start new session
    tmux new-session -d -s "$SESSION" "cd $RL_SWARM_DIR && source .venv/bin/activate && expect $EXPECT_SCRIPT"
}

# Initial startup
log "?? RL-Swarm Watchdog started."
write_expect_script
restart_rl_swarm

# Main loop
while true; do
    sleep "$CHECK_INTERVAL"
    if should_restart; then
        log "?? Restart triggered."
        restart_rl_swarm
    fi
done

