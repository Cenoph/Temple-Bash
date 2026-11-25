#!/usr/bin/env bash

# Temple Run in Bash

# Require Bash 5.0+ for $EPOCHREALTIME
if [[ -z "$EPOCHREALTIME" ]]; then
    echo "Bash 5.0 or newer is required for $EPOCHREALTIME."
    exit 1
fi

LEADERBOARD_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/temple_run_bash"
mkdir -p "$LEADERBOARD_DIR"

init_leaderboards() {
    for diff in easy medium hard expert; do
        file="$LEADERBOARD_DIR/temple_run_leaderboard_${diff}.txt"
        if [[ ! -f "$file" ]]; then
            printf "500 TMPL\n400 RUNR\n300 BASH\n200 DASH\n100 NOOB\n" > "$file"
        fi
    done
}
init_leaderboards

orig_stty=$(stty -g)

restore_terminal() {
    printf "\e[?25h" # Show cursor via ANSI (no tput fork)
    stty "$orig_stty"
}

set_raw_mode() {
    stty -echo -icanon time 0 min 0
    printf "\e[?25l" # Hide cursor via ANSI
}

cleanup() {
    restore_terminal
    printf "\e[2J\e[H"
    exit 0
}
trap cleanup EXIT INT TERM

print_leaderboard() {
    local diff_key="$1"
    local diff_label="$2"
    local file="$LEADERBOARD_DIR/temple_run_leaderboard_${diff_key}.txt"
    printf "\e[1;36m--- TOP 5 LEADERBOARD (%s) ---\e[0m\n" "$diff_label"
    awk '{printf "  #%d  %-6s  %s pts\n", NR, $2, $1}' "$file"
    printf "\e[1;36m---------------------------------------\e[0m\n"
}

# Pre-rendered cell graphics lookup table (avoids nested case statements every frame)
CELL_EMPTY="   "
CELL_WALL="\e[41m###\e[0m"
CELL_LOG="\e[33m===\e[0m"
CELL_BRANCH="\e[36m^^^\e[0m"
CELL_COIN=" \e[1;33m$\e[0m "
CELL_POWER=" \e[1;36m*\e[0m "
CELL_HEAL=" \e[1;32m+\e[0m "

PLAYER_RUN=" \e[1;32m@\e[0m "
PLAYER_JUMP=" \e[1;35m^\e[0m "
PLAYER_SLIDE=" \e[1;34m_\e[0m "
PLAYER_HIT=" \e[1;31m!\e[0m "
PLAYER_HEAL=" \e[1;32m+\e[0m "

# Convert $EPOCHREALTIME ("1732511234.567890") to integer milliseconds in pure Bash
now_ms() {
    local t="$EPOCHREALTIME"
    local sec="${t%.*}"
    local frac="${t#*.}"
    # Pad fractional part to 3 digits and strip leading zeros safely (10#)
    frac="${frac}000"
    echo $(( 10#$sec * 1000 + 10#${frac:0:3} ))
}

selected_diff=1 # 0=easy, 1=medium, 2=hard, 3=expert

# --- MAIN OUTER GAME LOOP ---
while true; do
    set_raw_mode

    # --- DIFFICULTY SELECT & START SCREEN ---
    while true; do
        case $selected_diff in
            0) diff_key="easy";   diff_label="EASY";   diff_color="\e[1;32m" ;;
            1) diff_key="medium"; diff_label="MEDIUM"; diff_color="\e[1;33m" ;;
            2) diff_key="hard";   diff_label="HARD";   diff_color="\e[1;31m" ;;
            3) diff_key="expert"; diff_label="EXPERT"; diff_color="\e[1;35m" ;;
        esac

        menu="\e[H\e[J"
        menu+="\e[1;33m=======================================\e[0m\n"
        menu+="\e[1;33m            TEMPLE RUN BASH            \e[0m\n"
        menu+="\e[1;33m=======================================\e[0m\n\n"
        menu+="Select Difficulty (\e[1;37m1-4\e[0m or \e[1;37mLeft/Right\e[0m):\n"

        tabs="  "
        names=("1:EASY" "2:MEDIUM" "3:HARD" "4:EXPERT")
        colors=("\e[1;32m" "\e[1;33m" "\e[1;31m" "\e[1;35m")
        for i in 0 1 2 3; do
            if ((i == selected_diff)); then
                tabs+="${colors[$i]}[${names[$i]}]\e[0m  "
            else
                tabs+="\e[2;37m ${names[$i]} \e[0m  "
            fi
        done
        menu+="${tabs}\n\n"

        lb_file="$LEADERBOARD_DIR/temple_run_leaderboard_${diff_key}.txt"
        menu+="\e[1;36m--- TOP 5 LEADERBOARD (${diff_label}) ---\e[0m\n"
        while IFS= read -r line; do
            menu+="$line\n"
        done < <(awk '{printf "  #%d  %-6s  %s pts", NR, $2, $1}' "$lb_file")
        menu+="\e[1;36m---------------------------------------\e[0m\n\n"

        menu+="Controls: \e[1;37m[A/D]\e[0m Move  \e[1;37m[W]\e[0m Jump  \e[1;37m[S]\e[0m Slide  \e[1;37m[P]\e[0m Pause  \e[1;37m[Q]\e[0m Quit\n\n"
        menu+="\e[1;32mPress ENTER or SPACE to start (Q to quit)...\e[0m"

        printf "%b" "$menu"

        key=""
        read -rsn1 key
        if [[ "$key" == $'\x1b' ]]; then
            read -rsn2 -t 0.01 seq
            case "$seq" in
                '[D') key="left" ;;
                '[C') key="right" ;;
            esac
        fi

        case "$key" in
            1) selected_diff=0 ;;
            2) selected_diff=1 ;;
            3) selected_diff=2 ;;
            4) selected_diff=3 ;;
            left|a|A)  ((selected_diff > 0)) && ((selected_diff--)) ;;
            right|d|D) ((selected_diff < 3)) && ((selected_diff++)) ;;
            ""|$'\n'|$'\r'|" ") break ;;
            q|Q) exit 0 ;;
        esac
    done

    # Set Difficulty Parameters (speeds in integer milliseconds—zero awk needed!)
    case $selected_diff in
        0) # EASY
            diff_key="easy"; diff_label="EASY"; diff_color="\e[1;32m"
            speed_ms=160; min_speed_ms=85; speed_step_ms=6
            spawn_gap=5; turn_interval=85; score_mult=1; wall_bias=25
            ;;
        1) # MEDIUM
            diff_key="medium"; diff_label="MEDIUM"; diff_color="\e[1;33m"
            speed_ms=130; min_speed_ms=65; speed_step_ms=8
            spawn_gap=4; turn_interval=65; score_mult=1; wall_bias=33
            ;;
        2) # HARD
            diff_key="hard"; diff_label="HARD"; diff_color="\e[1;31m"
            speed_ms=100; min_speed_ms=50; speed_step_ms=9
            spawn_gap=3; turn_interval=50; score_mult=2; wall_bias=40
            ;;
        3) # EXPERT
            diff_key="expert"; diff_label="EXPERT"; diff_color="\e[1;35m"
            speed_ms=80; min_speed_ms=40; speed_step_ms=10
            spawn_gap=3; turn_interval=35; score_mult=3; wall_bias=50
            ;;
    esac

    LEADERBOARD_FILE="$LEADERBOARD_DIR/temple_run_leaderboard_${diff_key}.txt"
    read -r high_score _ < "$LEADERBOARD_FILE"
    [[ -z "$high_score" ]] && high_score=0

    # --- COUNTDOWN ---
    printf "\n\n"
    for count in 3 2 1; do
        printf "\rStarting ${diff_color}${diff_label}\e[0m in \e[1;32m%d...\e[0m   " "$count"
        sleep 0.65
    done
    printf "\r\e[1;33mGO!                          \e[0m"
    sleep 0.25

    # --- INITIALIZE RUN STATE ---
    lane=1
    action="run"
    action_timer=0
    last_action="none"
    grace_timer=0
    score=0
    ticks=0
    height=16
    p_row=$((height - 2))
    paused=0
    game_over=0
    dirty=1 # Flag to redraw only when game state changes

    stumbles=0
    stumble_flash=0
    heal_flash=0
    heal_msg=""
    shield=0
    magnet_timer=0

    obs_lane=(-1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1)
    obs_type=(0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0)

    # Pre-built static legend array (eliminates case branching on every row every frame)
    LEGEND=(
        " \e[1;37mCONTROLS:\e[0m"
        "  [A / Left]  Move / Turn Left"
        "  [D / Right] Move / Turn Right"
        "  [W / Up]    Jump"
        "  [S / Down]  Slide"
        "  [P] Pause   [Q] Quit"
        ""
        " \e[1;37mOBSTACLES:\e[0m"
        "  \e[41m###\e[0m  Wall: Instant Game Over!"
        "  \e[33m===\e[0m  Log: Jump [W] (3 hits=Out)"
        "  \e[36m^^^\e[0m  Branch: Slide [S] (3 hits=Out)"
        "  \e[43;30m<<<\e[0m  Turn: Press Left/Right early"
        " \e[1;37mITEMS (${score_mult}x PTS):\e[0m"
        "  \e[1;33m$\e[0m    Coin (+$((10 * score_mult)) pts)"
        "  \e[1;36m*\e[0m    Rare Power-up (Shield/Magnet)"
        "  \e[1;32m+\e[0m    Ultra-Rare Full Heal (+$((50 * score_mult)))"
    )

    check_collision() {
        local t=${obs_type[$p_row]}
        if ((t >= 1 && t <= 9 && obs_lane[$p_row] == lane)); then
            case $t in
                4)
                    ((score += 10 * score_mult))
                    obs_type[$p_row]=0
                    ;;
                5)
                    if ((RANDOM & 1)); then
                        shield=1
                    else
                        magnet_timer=25
                    fi
                    obs_type[$p_row]=0
                    ;;
                9)
                    if ((stumbles > 0)); then
                        stumbles=0
                        heal_msg="FULL HEAL! (0/3)"
                    else
                        local bonus=$((50 * score_mult))
                        ((score += bonus))
                        heal_msg="MAX HP BONUS (+${bonus})"
                    fi
                    heal_flash=6
                    obs_type[$p_row]=0
                    ;;
                1)
                    if ((shield > 0)); then
                        shield=0
                        obs_type[$p_row]=0
                    else
                        game_over=1
                    fi
                    ;;
                2)
                    if [[ "$action" == "jump" ]] || ((grace_timer > 0 && "$last_action" == "jump")); then
                        :
                    elif ((shield > 0)); then
                        shield=0
                        obs_type[$p_row]=0
                    else
                        ((stumbles++))
                        stumble_flash=4
                        obs_type[$p_row]=0
                        ((stumbles >= 3)) && game_over=1
                    fi
                    ;;
                3)
                    if [[ "$action" == "slide" ]] || ((grace_timer > 0 && "$last_action" == "slide")); then
                        :
                    elif ((shield > 0)); then
                        shield=0
                        obs_type[$p_row]=0
                    else
                        ((stumbles++))
                        stumble_flash=4
                        obs_type[$p_row]=0
                        ((stumbles >= 3)) && game_over=1
                    fi
                    ;;
            esac
            dirty=1
        fi
    }

    printf "\e[2J\e[H"
    last_tick_ms=$(now_ms)

    # --- HIGH-FPS decoupled GAME LOOP ---
    while true; do
        # 1. Render ONLY when dirty (prevents redundant terminal writes)
        if ((dirty == 1)); then
display_best=$high_score
((score > display_best)) && display_best=$score
case $stumbles in
0) stumble_str="\e[1;32m0/3\e[0m" ;;
1) stumble_str="\e[1;33m1/3\e[0m" ;;
2) stumble_str="\e[1;31m2/3!\e[0m" ;;
*) stumble_str="\e[1;31m3/3\e[0m" ;;
esac
if ((paused == 1)); then
status="\e[1;33mPAUSED (Press P to resume)\e[0m"
elif ((stumble_flash > 0)); then
status="\e[1;31mSTUMBLED! (${stumbles}/3 Hits)\e[0m"
elif ((heal_flash > 0)); then
status="\e[1;32m${heal_msg}\e[0m"
else
status="\e[1;32mRUNNING\e[0m"
((shield > 0)) && status="\e[1;36mSHIELD ACTIVE\e[0m"
((magnet_timer > 0)) && status="\e[1;35mMAGNET (${magnet_timer})\e[0m"
((shield > 0 && magnet_timer > 0)) && status="\e[1;36mSHIELD\e[0m + \e[1;35mMAGNET (${magnet_timer})\e[0m"
fi
# Determine player sprite once per frame
if ((stumble_flash > 0)); then
p_sprite="$PLAYER_HIT"
elif ((heal_flash > 0)); then
p_sprite="$PLAYER_HEAL"
else
case "$action" in
run)   p_sprite="$PLAYER_RUN" ;;
jump)  p_sprite="$PLAYER_JUMP" ;;
slide) p_sprite="$PLAYER_SLIDE" ;;
esac
fi
frame="\e[H"
frame+="\e[1;33mTEMPLE RUN\e[0m [${diff_color}${diff_label}\e[0m] | Score: \e[1;32m${score}\e[0m | Best: \e[1;33m${display_best}\e[0m    \n"
frame+="Status: ${status} | Hits: ${stumble_str}\e[K\n"
frame+="+---+---+---+   \e[1;37mHOW TO PLAY & OBSTACLES\e[0m\n"
for ((r=0; r<height; r++)); do
t=${obs_type[$r]}
if ((t == 6)); then
if ((r >= p_row - 2 && r <= p_row)); then
line="|\e[1;43;30m<<< TURN <<<\e[0m|"
else
line="|\e[43;30m<<< TURN <<<\e[0m|"
fi
elif ((t == 7)); then
if ((r >= p_row - 2 && r <= p_row)); then
line="|\e[1;43;30m>>> TURN >>>\e[0m|"
else
line="|\e[43;30m>>> TURN >>>\e[0m|"
fi
elif ((t == 8)); then
line="|\e[1;42;30m  TURN OK!  \e[0m|"
else
c0="$CELL_EMPTY"; c1="$CELL_EMPTY"; c2="$CELL_EMPTY"
if ((t > 0)); then
case $t in
1) obj="$CELL_WALL" ;;
2) obj="$CELL_LOG" ;;
3) obj="$CELL_BRANCH" ;;
4) obj="$CELL_COIN" ;;
5) obj="$CELL_POWER" ;;
9) obj="$CELL_HEAL" ;;
esac
case ${obs_lane[$r]} in
0) c0="$obj" ;;
1) c1="$obj" ;;
2) c2="$obj" ;;
esac
fi
if ((r == p_row)); then
case $lane in
0) c0="$p_sprite" ;;
1) c1="$p_sprite" ;;
2) c2="$p_sprite" ;;
esac
fi
line="|${c0}|${c1}|${c2}|"
fi
frame+="${line}  ${LEGEND[$r]}\e[K\n"
done
frame+="+---+---+---+\n"
printf "%b" "$frame"
dirty=0
fi
# 2. High-Frequency Non-Blocking Input Poll (10ms slices = 100Hz responsiveness)
key=""
read -rsn1 -t 0.01 key
if [[ -n "$key" ]]; then
if [[ "$key" == $'\x1b' ]]; then
read -rsn2 -t 0.002 seq
case "$seq" in
'[D') key="a" ;;
'[C') key="d" ;;
'[A') key="w" ;;
'[B') key="s" ;;
esac
fi
if [[ "$key" == "q" || "$key" == "Q" ]]; then
break
elif [[ "$key" == "p" || "$key" == "P" ]]; then
paused=$((1 - paused))
last_tick_ms=$(now_ms)
dirty=1
continue
fi
if ((paused == 0)); then
turn_handled=0
if [[ "$key" == "a" || "$key" == "A" || "$key" == "d" || "$key" == "D" ]]; then
for ((tr = p_row; tr >= p_row - 2; tr--)); do
if ((tr >= 0)); then
if ((obs_type[$tr] == 6)) && [[ "$key" == "a" || "$key" == "A" ]]; then
obs_type[$tr]=8
((score += 15 * score_mult))
turn_handled=1
dirty=1
break
elif ((obs_type[$tr] == 7)) && [[ "$key" == "d" || "$key" == "D" ]]; then
obs_type[$tr]=8
((score += 15 * score_mult))
turn_handled=1
dirty=1
break
fi
fi
done
fi
if ((turn_handled == 0)); then
case "$key" in
a|A) ((lane > 0)) && { ((lane--)); dirty=1; } ;;
d|D) ((lane < 2)) && { ((lane++)); dirty=1; } ;;
w|W) action="jump"; action_timer=7; last_action="jump"; dirty=1 ;;
s|S) action="slide"; action_timer=7; last_action="slide"; dirty=1 ;;
esac
fi
check_collision
((game_over == 1)) && break
fi
fi
((paused == 1)) && continue
# 3. Fixed-Timestep World Scroll Check (decoupled from keypresses!)
cur_ms=$(now_ms)
if (( cur_ms - last_tick_ms >= speed_ms )); then
last_tick_ms=$cur_ms
dirty=1
# Check if an uncleared turn reached the player row
if ((obs_type[$p_row] == 6 || obs_type[$p_row] == 7)); then
if ((shield > 0)); then
shield=0
obs_type[$p_row]=8
else
break
fi
fi
# Update Timers & Magnet Effect
((stumble_flash > 0)) && ((stumble_flash--))
((heal_flash > 0)) && ((heal_flash--))
((grace_timer > 0)) && ((grace_timer--))
if ((action_timer > 0)); then
((action_timer--))
if ((action_timer == 0)); then
action="run"
grace_timer=1
fi
fi
if ((magnet_timer > 0)); then
((magnet_timer--))
for ((i=0; i<height; i++)); do
if ((obs_type[$i] == 4)); then
obs_type[$i]=0
((score += 10 * score_mult))
fi
done
fi
# Fast O(1) Array Slicing Shift (replaces 16-iteration shift loop)
((ticks++))
new_lane=-1
new_type=0
if ((ticks % turn_interval == 0)); then
new_lane=0
new_type=$(( (RANDOM & 1) + 6 ))
elif ((ticks % spawn_gap == 0)); then
new_lane=$((RANDOM % 3))
roll=$((RANDOM % 1000))
if ((roll < 5)); then
new_type=9
elif ((roll < 25)); then
new_type=5
elif ((roll < 305)); then
new_type=4
else
obs_roll=$((RANDOM % 100))
if ((obs_roll < wall_bias)); then
new_type=1
elif ((obs_roll < wall_bias + (100 - wall_bias) / 2)); then
new_type=2
else
new_type=3
fi
fi
fi
obs_lane=( "$new_lane" "${obs_lane[@]:0:15}" )
obs_type=( "$new_type" "${obs_type[@]:0:15}" )
check_collision
((game_over == 1)) && break
((score += score_mult))
if ((ticks % 60 == 0 && speed_ms > min_speed_ms)); then
((speed_ms -= speed_step_ms))
((speed_ms < min_speed_ms)) && speed_ms=$min_speed_ms
fi
fi
done
# --- GAME OVER & LEADERBOARD UPDATE ---
restore_terminal
printf "\e[2J\e[H"
printf "\e[1;31m=======================================\e[0m\n"
printf "\e[1;31m               GAME OVER!              \e[0m\n"
printf "\e[1;31m=======================================\e[0m\n"
printf "Difficulty:  ${diff_color}${diff_label}\e[0m\n"
printf "Final Score: \e[1;32m%d\e[0m\n\n" "$score"
fifth_score=$(awk 'NR==5 {print $1}' "$LEADERBOARD_FILE" 2>/dev/null || echo 0)
line_count=$(wc -l < "$LEADERBOARD_FILE" | tr -d ' ')
if ((score > fifth_score || line_count < 5)); then
printf "\e[1;33mNEW TOP 5 (%s) HIGH SCORE!\e[0m\n" "$diff_label"
read -rp "Enter your initials (max 4 chars): " initials
initials=$(echo "$initials" | tr '[:lower:]' '[:upper:]' | tr -cd '[:alnum:]' | cut -c1-4)
[[ -z "$initials" ]] && initials="ANON"
echo "$score $initials" >> "$LEADERBOARD_FILE"
sort -rn -k1,1 "$LEADERBOARD_FILE" | head -n 5 > "${LEADERBOARD_FILE}.tmp"
mv "${LEADERBOARD_FILE}.tmp" "$LEADERBOARD_FILE"
printf "\n"
fi
print_leaderboard "$diff_key" "$diff_label"
printf "\n"
# --- PLAY AGAIN PROMPT ---
while true; do
read -rp "Play again? [Y/N]: " replay
case "$replay" in
y|Y) break ;;
n|N) exit 0 ;;
*) printf "Please enter Y or N.\n" ;;
esac
done
done
