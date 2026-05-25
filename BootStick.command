#!/bin/zsh

# Entra no alternate screen imediatamente — esconde o echo do Apple Terminal antes de tudo
[[ -t 1 ]] && printf '\033[?1049h\033[H\033[2J\033[3J'

# =========================================================
# BootStick — Hackintosh bootable USB assistant
# =========================================================

setopt NO_NOMATCH 2>/dev/null

APP_NAME="BootStick"
APP_TAGLINE="Assistente de mídia bootável para Hackintosh"
SCRIPT_VERSION=$(git -C "$(dirname "$0")" describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo "1.6.0")
SCRIPT_BUILD=$(date -r "$0" +%Y.%m.%d 2>/dev/null || echo "—")
VOLUME_NAME="Install macOS"
DISK_FORMAT="JHFS+"
LOG_FILE="/tmp/bootstick_last.log"

SELECTED_DISK=""
SELECTED_DISK_NAME=""
DISK_FORMATTED=0
SELECTED_INSTALLER=""
INSTALLER_CREATED=0
SPINNER_PID=""
PICKER_RESULT=0
MENU_RESULT=""
DEMO_MODE=0

if [[ -t 1 ]]; then
    C_RESET=$'\033[0m'
    C_DIM=$'\033[2m'
    C_BOLD=$'\033[1m'
    C_TITLE=$'\033[38;5;45m'
    C_ACCENT=$'\033[38;5;117m'
    C_WARN=$'\033[38;5;214m'
    C_OK=$'\033[38;5;82m'
else
    C_RESET="" C_DIM="" C_BOLD="" C_TITLE="" C_ACCENT="" C_WARN="" C_OK=""
fi

TERM_ROWS=32

clear_screen() {
    # \033[H     — cursor pro topo
    # \033[2J    — limpa a tela visível
    # \033[3J    — remove scrollback (impede rolagem)
    printf '\033[H\033[2J\033[3J'
}

init_terminal() {
    [[ -t 1 ]] || return
    printf '\e]0;%s v%s\a' "$APP_NAME" "$SCRIPT_VERSION"

    # Redimensiona a janela para TERM_ROWS linhas.
    # Usa AppleScript no Apple Terminal (cálculo proporcional, independe do tamanho de fonte).
    # Usa escape xterm em outros terminais (iTerm2, etc.).
    local curr_rows
    curr_rows=$(tput lines 2>/dev/null || echo 24)

    if [[ "$TERM_PROGRAM" == "Apple_Terminal" ]]; then
        osascript 2>/dev/null <<EOF
tell application "Terminal"
    if (count of windows) > 0 then
        tell front window
            set b to bounds
            set newH to ((item 4 of b - item 2 of b) * $TERM_ROWS / $curr_rows) as integer
            set bounds to {item 1 of b, item 2 of b, item 3 of b, (item 2 of b) + newH}
        end tell
    end if
end tell
EOF
    else
        local cols
        cols=$(tput cols 2>/dev/null || echo 80)
        printf '\033[8;%d;%dt' "$TERM_ROWS" "$cols"
    fi

    sleep 0.2
    clear_screen
}

exit_terminal() {
    printf '\033[?1049l'   # restaura o terminal principal com histórico intacto
}

trap 'exit_terminal' EXIT

pause() {
    echo ""
    read "?${C_DIM}Pressione ENTER para continuar...${C_RESET}"
}

auto_return() {
    local secs="${1:-3}"
    echo ""
    spinner_start "Voltando ao menu..."
    sleep "$secs"
    spinner_stop
}

close_terminal() {
    [[ -t 1 ]] || return

    case "$TERM_PROGRAM" in
        Apple_Terminal)
            nohup zsh -c '
                sleep 0.4
                osascript <<EOF
tell application "Terminal"
    if (count of windows) > 0 then
        close front window
    end if
end tell
delay 0.15
tell application "System Events" to tell process "Terminal"
    repeat with w in windows
        if exists sheet of w then
            try
                click button 2 of sheet of w
            end try
            exit repeat
        end if
    end repeat
end tell
EOF
            ' >/dev/null 2>&1 &
            ;;
        iTerm.app)
            nohup zsh -c '
                sleep 0.4
                osascript <<EOF
tell application "iTerm"
    close current window
end tell
EOF
            ' >/dev/null 2>&1 &
            ;;
    esac
}

typeset -a ASCII_LOGO
ASCII_LOGO=(
'  ____              _    _____ _   _      _    '
' |  _ \            | |  / ____| | (_)    | |   '
' | |_) | ___   ___ | |_| (___ | |_ _  ___| | __'
' |  _ < / _ \ / _ \| __|\___ \| __| |/ __| |/ / '
' | |_) | (_) | (_) | |_ ____) | |_| | (__|   <  '
' |____/ \___/ \___/ \__|_____/ \__|_|\___|_|\_\ '
)

print_divider() {
    printf "  ${C_DIM}──────────────────────────────────────────────────${C_RESET}\n"
}

print_ascii_logo() {
    local line
    for line in "${ASCII_LOGO[@]}"; do
        printf "  ${C_TITLE}${C_BOLD}%s${C_RESET}\n" "$line"
    done
}

print_version_badge() {
    printf "  ${C_ACCENT}${C_BOLD} v${SCRIPT_VERSION}${C_RESET}  ${C_DIM}·  build ${SCRIPT_BUILD}  ·  Hackintosh / OpenCore${C_RESET}\n"
}

# Indicador visual de etapas do fluxo
print_step_indicator() {
    local m_l="macOS" d_l="Disco" f_l="Format" b_l="Boot" e_l="EFI"
    local m_c d_c f_c b_c e_c
    m_c="$C_DIM"; d_c="$C_DIM"; f_c="$C_DIM"; b_c="$C_DIM"; e_c="$C_DIM"

    if [[ -n "$SELECTED_INSTALLER" ]]; then m_l="macOS ✓"; m_c="$C_OK"; fi
    if [[ -n "$SELECTED_DISK" ]];      then d_l="Disco ✓"; d_c="$C_OK"; fi
    if (( DISK_FORMATTED ));           then f_l="Format ✓"; f_c="$C_OK"; fi
    if (( INSTALLER_CREATED ));        then b_l="Boot ✓"; b_c="$C_OK"; e_l="EFI →"; e_c="$C_ACCENT"; fi

    printf "  "
    printf "${m_c}%s${C_RESET}" "$m_l"
    printf "${C_DIM} ──▶ ${C_RESET}"
    printf "${d_c}%s${C_RESET}" "$d_l"
    printf "${C_DIM} ──▶ ${C_RESET}"
    printf "${f_c}%s${C_RESET}" "$f_l"
    printf "${C_DIM} ──▶ ${C_RESET}"
    printf "${b_c}%s${C_RESET}" "$b_l"
    printf "${C_DIM} ──▶ ${C_RESET}"
    printf "${e_c}%s${C_RESET}\n" "$e_l"
}

print_banner() {
    local subtitle="${1:-}"

    print_ascii_logo
    echo ""
    print_version_badge

    if [[ -n "$subtitle" ]]; then
        printf "  ${C_DIM}%s${C_RESET}\n" "$subtitle"
    fi

    print_divider
}

print_about_short() {
    printf "  ${C_DIM}Pendrive bootável macOS · OpenCore${C_RESET}\n"
}

print_about_full() {
    echo ""
    printf "  ${C_ACCENT}${C_BOLD}Sobre${C_RESET}\n\n"
    printf "${C_DIM}"
    cat <<EOF
  ${APP_TAGLINE}

  Automatiza o que costuma ser feito à mão no Terminal:
  diskutil, createinstallmedia e montagem da EFI para OpenCore.

  Requisitos: macOS real, app Install macOS* em /Applications,
  pendrive/SSD externo (16 GB+) e senha de administrador.

  Navegação: ↑↓ mover   Enter selecionar   número atalho direto
             Home/End primeiro/último item   Q ou Esc voltar

  Pré-requisitos (qualquer ordem): [M] instalador  [D] disco
  Fluxo após os pré-requisitos:   [F] formatar  [B] bootável  [E] EFI

  Formato do pendrive: Mac OS Extended (JHFS+) — exigido pelo
  createinstallmedia em versões recentes (não use APFS no USB).

  Log de erros: $LOG_FILE
EOF
    printf "${C_RESET}"
    echo ""
    read "?${C_DIM}Pressione ENTER para voltar...${C_RESET}"
}

print_goodbye() {
    clear_screen
    print_banner "Obrigado por usar o BootStick"
    echo ""
    printf "  ${C_OK}${C_BOLD}Até a próxima!${C_RESET}\n"
    printf "  ${C_DIM}Boa sorte com seu Hackintosh.${C_RESET}\n"
    echo ""
    read "?${C_DIM}Pressione ENTER para fechar...${C_RESET}"
    close_terminal
    exit 0
}

# =========================================================
# Log
# =========================================================

log_info() {
    printf "[%s] INFO: %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$LOG_FILE"
}

log_error() {
    printf "[%s] ERROR: %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$LOG_FILE"
}

# =========================================================
# Spinner
# =========================================================

spinner_start() {
    local msg="${1:-Aguarde...}"
    (
        local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
        local i=1
        while true; do
            printf "\r  ${C_ACCENT}%s${C_RESET}  ${C_DIM}%s${C_RESET}" "${frames[$i]}" "$msg"
            (( i = i % ${#frames[@]} + 1 ))
            sleep 0.08
        done
    ) &
    SPINNER_PID=$!
    disown "$SPINNER_PID" 2>/dev/null
}

spinner_stop() {
    [[ -z "$SPINNER_PID" ]] && return
    kill "$SPINNER_PID" 2>/dev/null
    wait "$SPINNER_PID" 2>/dev/null
    SPINNER_PID=""
    printf "\r\033[2K"
}

# =========================================================
# Barra de progresso + tempo decorrido
# =========================================================

draw_progress_bar() {
    local pct="$1" label="${2:-}" elapsed="${3:-}"
    local width=32 filled empty bar i
    (( filled = pct * width / 100 ))
    (( empty  = width - filled ))
    bar=""
    for (( i=0; i<filled; i++ )); do bar+="█"; done
    for (( i=0; i<empty;  i++ )); do bar+="░"; done
    local elapsed_str=""
    [[ -n "$elapsed" ]] && elapsed_str="  ${C_DIM}${elapsed}${C_RESET}"
    printf "\r  ${C_ACCENT}[%s]${C_RESET} ${C_BOLD}%3d%%${C_RESET}  ${C_DIM}%s${C_RESET}%s  " \
        "$bar" "$pct" "$label" "$elapsed_str"
}

format_elapsed() {
    local secs="$1"
    if (( secs < 60 )); then
        printf "%ds" "$secs"
    else
        printf "%dm%02ds" "$(( secs / 60 ))" "$(( secs % 60 ))"
    fi
}

# =========================================================
# Confirmação visual (substitui s/n digitado)
#
# Uso: confirm_visual "Pergunta?"
# Retorna 0 (sim) ou 1 (não/cancelado)
# =========================================================

confirm_visual() {
    local prompt="${1:-Confirmar?}"
    local n=2 sel=2 key key2 key3  # padrão: Não

    echo ""
    printf "  ${C_BOLD}%s${C_RESET}\n" "$prompt"
    echo ""

    printf '\033[?25l'
    printf '\0337'

    while true; do
        printf '\0338'
        if (( sel == 1 )); then
            printf "\r\033[K  ${C_ACCENT}▶ [1]${C_RESET}  ${C_BOLD}Sim${C_RESET}\n"
            printf "\r\033[K    ${C_DIM}[2]  Não${C_RESET}\n"
        else
            printf "\r\033[K    ${C_DIM}[1]  Sim${C_RESET}\n"
            printf "\r\033[K  ${C_ACCENT}▶ [2]${C_RESET}  ${C_BOLD}Não${C_RESET}\n"
        fi
        printf "\r\033[K\n"
        printf "\r\033[K  ${C_DIM}↑↓ navegar   Enter confirmar   Esc cancelar${C_RESET}"

        read -k 1 -s key

        case "$key" in
            $'\033')
                key2=""; read -k 1 -s -t 0.05 key2 2>/dev/null
                if [[ "$key2" == "[" ]]; then
                    key3=""; read -k 1 -s -t 0.05 key3 2>/dev/null
                    [[ "$key3" == "A" ]] && sel=$(( sel > 1 ? sel - 1 : n ))
                    [[ "$key3" == "B" ]] && sel=$(( sel < n ? sel + 1 : 1 ))
                else
                    printf '\0338'; printf "\033[%dB\r\n" $(( n + 2 ))
                    printf '\033[?25h'; return 1
                fi
                ;;
            $'\n'|$'\r')
                printf '\0338'; printf "\033[%dB\r\n" $(( n + 2 ))
                printf '\033[?25h'
                (( sel == 1 )) && return 0 || return 1
                ;;
            1) printf '\0338'; printf "\033[%dB\r\n" $(( n + 2 ))
               printf '\033[?25h'; return 0 ;;
            2) printf '\0338'; printf "\033[%dB\r\n" $(( n + 2 ))
               printf '\033[?25h'; return 1 ;;
            [sS]) printf '\0338'; printf "\033[%dB\r\n" $(( n + 2 ))
               printf '\033[?25h'; return 0 ;;
            [nN]) printf '\0338'; printf "\033[%dB\r\n" $(( n + 2 ))
               printf '\033[?25h'; return 1 ;;
        esac
    done
}

# =========================================================
# Notificação macOS
# =========================================================

notify_macos() {
    local title="$1" msg="$2"
    osascript -e "display notification \"$msg\" with title \"$title\"" 2>/dev/null
}

# =========================================================
# Conteúdo atual do disco
# =========================================================

show_disk_volumes() {
    local disk="$1"
    printf "  ${C_DIM}Conteúdo atual:${C_RESET}\n\n"
    diskutil list "/dev/$disk" 2>/dev/null | sed 's/^/  /'
    echo ""
}

# =========================================================
# Seleção interativa com setas do teclado
#
# Uso:  interactive_picker "item1" "item2" ...
# Resultado em $PICKER_RESULT (índice 1-based)
# Retorna 0 = selecionado, 1 = cancelado
# Atalhos: ↑↓ navegar (com wrap) · Enter confirmar
#          número atalho direto · Home/End · Q/Esc cancela
# =========================================================

interactive_picker() {
    local -a items=("$@")
    local n=${#items[@]} sel=1 key key2 key3 i

    printf '\033[?25l'
    printf '\0337'

    while true; do
        printf '\0338'
        for (( i=1; i<=n; i++ )); do
            if (( i == sel )); then
                printf "\r\033[K  ${C_ACCENT}▶ [%d]${C_RESET}  ${C_BOLD}%s${C_RESET}\n" \
                    "$i" "${items[$i]}"
            else
                printf "\r\033[K    ${C_DIM}[%d]  %s${C_RESET}\n" \
                    "$i" "${items[$i]}"
            fi
        done
        printf "\r\033[K\n"
        printf "\r\033[K  ${C_DIM}↑↓ navegar   Enter selecionar   número atalho   Q voltar${C_RESET}"

        read -k 1 -s key

        case "$key" in
            $'\033')
                key2=""; read -k 1 -s -t 0.05 key2 2>/dev/null
                if [[ "$key2" == "[" ]]; then
                    key3=""; read -k 1 -s -t 0.05 key3 2>/dev/null
                    case "$key3" in
                        A) sel=$(( sel > 1 ? sel - 1 : n )) ;;    # Up — wrap
                        B) sel=$(( sel < n ? sel + 1 : 1 )) ;;    # Down — wrap
                        H) sel=1 ;;                                 # Home
                        F) sel=$n ;;                                # End
                        1)  # Home via \033[1~
                            local k4=""; read -k 1 -s -t 0.05 k4 2>/dev/null
                            [[ "$k4" == "~" ]] && sel=1
                            ;;
                        4)  # End via \033[4~
                            local k4=""; read -k 1 -s -t 0.05 k4 2>/dev/null
                            [[ "$k4" == "~" ]] && sel=$n
                            ;;
                    esac
                else
                    printf '\0338'; printf "\033[%dB\r\n" $(( n + 2 ))
                    printf '\033[?25h'; return 1
                fi
                ;;
            $'\n'|$'\r')
                printf '\0338'; printf "\033[%dB\r\n" $(( n + 2 ))
                printf '\033[?25h'; PICKER_RESULT=$sel; return 0
                ;;
            [qQ])
                printf '\0338'; printf "\033[%dB\r\n" $(( n + 2 ))
                printf '\033[?25h'; return 1
                ;;
            [1-9])
                local num="$key"
                if (( num >= 1 && num <= n )); then
                    printf '\0338'; printf "\033[%dB\r\n" $(( n + 2 ))
                    printf '\033[?25h'; PICKER_RESULT=$num; return 0
                fi
                ;;
        esac
    done
}

# =========================================================
# Seleção interativa do menu principal
#
# Args: "action|label" ...
# Resultado em $MENU_RESULT (action string)
# =========================================================

main_menu_picker() {
    local -a entries=("$@")
    local n=${#entries[@]} sel=1 key key2 key3 i action label

    MENU_RESULT=""
    printf '\033[?25l'
    printf '\0337'

    while true; do
        printf '\0338'
        for (( i=1; i<=n; i++ )); do
            IFS='|' read -r action label <<< "${entries[$i]}"
            if (( i == sel )); then
                printf "\r\033[K  ${C_ACCENT}▶ [%d]${C_RESET}  ${C_BOLD}%s${C_RESET}\n" \
                    "$i" "$label"
            else
                printf "\r\033[K    ${C_DIM}[%d]  %s${C_RESET}\n" "$i" "$label"
            fi
        done
        printf "\r\033[K\n"
        printf "\r\033[K  ${C_DIM}↑↓ navegar   Enter selecionar   número atalho${C_RESET}"

        read -k 1 -s key

        case "$key" in
            $'\033')
                key2=""; read -k 1 -s -t 0.05 key2 2>/dev/null
                if [[ "$key2" == "[" ]]; then
                    key3=""; read -k 1 -s -t 0.05 key3 2>/dev/null
                    case "$key3" in
                        A) sel=$(( sel > 1 ? sel - 1 : n )) ;;
                        B) sel=$(( sel < n ? sel + 1 : 1 )) ;;
                        H) sel=1 ;;
                        F) sel=$n ;;
                    esac
                fi
                ;;
            $'\n'|$'\r')
                IFS='|' read -r action label <<< "${entries[$sel]}"
                printf '\0338'; printf "\033[%dB\r\n" $(( n + 2 ))
                printf '\033[?25h'; MENU_RESULT="$action"; return 0
                ;;
            ['!'])
                printf '\0338'; printf "\033[%dB\r\n" $(( n + 2 ))
                printf '\033[?25h'; MENU_RESULT="!"; return 0
                ;;
            [1-9])
                local num="$key"
                if (( num >= 1 && num <= n )); then
                    IFS='|' read -r action label <<< "${entries[$num]}"
                    printf '\0338'; printf "\033[%dB\r\n" $(( n + 2 ))
                    printf '\033[?25h'; MENU_RESULT="$action"; return 0
                fi
                ;;
        esac
    done
}

volume_on_disk() {
    local disk="$1" whole

    if [[ ! -d "/Volumes/$VOLUME_NAME" ]]; then
        return 1
    fi

    whole=$(diskutil info "/Volumes/$VOLUME_NAME" 2>/dev/null | awk -F': ' '/Part of Whole:/ {
        gsub(/^[[:space:]]+/, "", $2)
        gsub(/^\/dev\//, "", $2)
        print $2
        exit
    }')
    [[ "$whole" == "$disk" ]]
}

volume_is_apfs() {
    [[ -d "/Volumes/$VOLUME_NAME" ]] || return 1
    diskutil info "/Volumes/$VOLUME_NAME" 2>/dev/null | grep -qE '(APFS|File System Personality:[[:space:]]*APFS)'
}

disk_ready_for_installer() {
    local disk="$1"
    volume_on_disk "$disk" && ! volume_is_apfs
}

sync_disk_state() {
    if [[ -z "$SELECTED_DISK" ]]; then
        DISK_FORMATTED=0
        return
    fi

    if disk_ready_for_installer "$SELECTED_DISK"; then
        DISK_FORMATTED=1
    else
        DISK_FORMATTED=0
    fi
}

print_subscreen() {
    local title="$1"
    clear_screen
    echo ""
    printf "  ${C_TITLE}${C_BOLD}▸ %s${C_RESET}  ${C_DIM}%s${C_RESET}\n" "$APP_NAME" "$title"
    print_divider
}

disk_media_name() {
    disk_details "$1" | awk -F'|' '{print $1}'
}

show_menu() {
    sync_disk_state

    clear_screen

    if (( DEMO_MODE )); then
        print_banner "${C_WARN}DEMO — nenhum disco será modificado${C_RESET}"
    else
        print_banner "$APP_TAGLINE"
    fi
    print_about_short
    echo ""
    print_step_indicator
    echo ""

    if [[ -n "$SELECTED_DISK_NAME" ]]; then
        printf "  %-12s ${C_OK}%s${C_RESET} ${C_DIM}(/dev/%s)${C_RESET}\n" "Disco:" "$SELECTED_DISK_NAME" "$SELECTED_DISK"
    else
        printf "  %-12s ${C_DIM}—${C_RESET}\n" "Disco:"
    fi

    if [[ -n "$SELECTED_INSTALLER" ]]; then
        printf "  %-12s ${C_OK}%s${C_RESET}\n" "macOS:" "$(installer_label "$SELECTED_INSTALLER")"
    else
        printf "  %-12s ${C_DIM}—${C_RESET}\n" "macOS:"
    fi

    (( DISK_FORMATTED ))    && printf "  %-12s ${C_OK}✓ Mac OS Extended${C_RESET}\n" "Formato:"
    (( INSTALLER_CREATED )) && printf "  %-12s ${C_OK}✓ criado${C_RESET}\n" "Bootável:"

    echo ""

    local -a _items=()

    if (( INSTALLER_CREATED )); then
        _items+=("e|Montar e abrir EFI (OpenCore)")
        _items+=("f|Reformatar disco (opcional)")
        _items+=("m|Trocar instalador macOS")
        _items+=("d|Trocar disco")
    elif [[ -n "$SELECTED_DISK" && -n "$SELECTED_INSTALLER" && $DISK_FORMATTED -eq 1 ]]; then
        _items+=("b|Criar mídia bootável")
        _items+=("f|Reformatar disco (opcional)")
        _items+=("m|Trocar instalador macOS")
        _items+=("d|Trocar disco")
    elif [[ -n "$SELECTED_DISK" && -n "$SELECTED_INSTALLER" ]]; then
        _items+=("f|Formatar disco (apaga tudo)")
        _items+=("m|Trocar instalador macOS")
        _items+=("d|Trocar disco")
    elif [[ -z "$SELECTED_DISK" && -n "$SELECTED_INSTALLER" ]]; then
        _items+=("d|Selecionar disco USB/SSD")
        _items+=("m|Trocar instalador macOS")
    elif [[ -n "$SELECTED_DISK" && -z "$SELECTED_INSTALLER" ]]; then
        _items+=("m|Obter instalador macOS")
        (( ! DISK_FORMATTED )) && _items+=("f|Formatar disco")
        _items+=("d|Trocar disco")
    else
        _items+=("m|Obter instalador macOS")
        _items+=("d|Selecionar disco USB/SSD")
    fi

    _items+=("h|Ajuda / sobre")
    _items+=("q|Sair")

    main_menu_picker "${_items[@]}"
}

is_whole_disk() {
    [[ "$1" =~ '^disk[0-9]+$' ]]
}

is_external_disk() {
    local info
    info=$(diskutil info "/dev/$1" 2>/dev/null) || return 1
    echo "$info" | grep -qE '(Device Location:[[:space:]]*External|External:[[:space:]]*Yes)'
}

disk_details() {
    local disk="$1"
    diskutil info "/dev/$disk" 2>/dev/null | awk '
        /^   Device \/ Media Name:/ {
            line = $0
            sub(/^   Device \/ Media Name:[[:space:]]*/, "", line)
            name = line
        }
        /^   Disk Size:/ {
            line = $0
            sub(/^   Disk Size:[[:space:]]*/, "", line)
            if (match(line, /^[0-9.]+[[:space:]]+[KMGT]B/))
                size = substr(line, RSTART, RLENGTH)
            # Extrai bytes: remove tudo antes do "(" e depois de " Bytes"
            bytes_line = line
            gsub(/.*\(/, "", bytes_line)
            gsub(/ Bytes.*/, "", bytes_line)
            gsub(/[^0-9]/, "", bytes_line)
            bytes = bytes_line
        }
        /^   Protocol:/ {
            line = $0
            sub(/^   Protocol:[[:space:]]*/, "", line)
            proto = line
        }
        END {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", name)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", proto)
            if (name == "") name = "Sem nome"
            if (size == "") size = "—"
            if (proto == "") proto = "—"
            if (bytes == "") bytes = "0"
            print name "|" size "|" proto "|" bytes
        }'
}

choose_disk() {
    if [[ -n "$SELECTED_DISK" ]]; then
        print_subscreen "Trocar disco"
        echo ""
        printf "  %-12s ${C_OK}%s${C_RESET} ${C_DIM}(/dev/%s)${C_RESET}\n" "Atual:" "$SELECTED_DISK_NAME" "$SELECTED_DISK"
        echo ""
        printf "  ${C_DIM}Trocar o disco reinicia as etapas de formatação e instalação.${C_RESET}\n"
        confirm_visual "Trocar disco?" || return
    fi

    local _refresh=1
    local -a DISKS=() _display=()
    local -A _seen=()

    while (( _refresh )); do
        _refresh=0
        DISKS=()
        _display=()
        _seen=()

        print_subscreen "Selecionar disco"

        if (( DEMO_MODE )); then
            DISKS=("disk2" "disk3")
            _display=(
                "$(printf '%-14s %-22s %s' '/dev/disk2' 'Samsung USB 3.1' '32.0 GB')"
                "$(printf '%-14s %-22s %s' '/dev/disk3' 'SanDisk Ultra'   '64.0 GB')"
            )
        else
            add_disk() {
                local _d="$1"
                is_whole_disk "$_d" || return
                [[ -n "${_seen[$_d]}" ]] && return
                _seen[$_d]=1
                DISKS+=("$_d")
            }

            while IFS= read -r DISK; do
                add_disk "$DISK"
            done < <(diskutil list 2>/dev/null | awk '/^\/dev\/disk[0-9]+ \(external/ {
                gsub("/dev/", "", $1); print $1
            }')

            while IFS= read -r DISK; do
                add_disk "$DISK"
            done < <(diskutil list external physical 2>/dev/null | awk '/^\/dev\/disk[0-9]+ \(/ {
                gsub("/dev/", "", $1); print $1
            }')

            if (( ${#DISKS[@]} == 0 )); then
                while IFS= read -r DISK; do
                    is_whole_disk "$DISK" || continue
                    is_external_disk "$DISK" || continue
                    add_disk "$DISK"
                done < <(diskutil list 2>/dev/null | awk '/^\/dev\/disk[0-9]+ \(.*physical\):/ {
                    gsub("/dev/", "", $1); print $1
                }')
            fi

            local _i _d _n _s _p _b _warn
            for _i in {1..${#DISKS[@]}}; do
                _d="${DISKS[$_i]}"
                IFS='|' read -r _n _s _p _b <<< "$(disk_details "$_d")"
                _warn=""
                (( _b > 0 && _b < 16000000000 )) && _warn=" ${C_WARN}⚠ <16 GB${C_RESET}"
                _display+=("$(printf '%-14s %-22s %-10s' "/dev/$_d" "$_n" "$_s")${_warn}")
            done
        fi

        _display+=("↺  Atualizar lista de discos")

        echo ""
        if (( ${#DISKS[@]} == 0 && ! DEMO_MODE )); then
            printf "  ${C_WARN}Nenhum disco externo encontrado.${C_RESET}\n"
            printf "  ${C_DIM}Conecte um pendrive ou SSD USB e atualize a lista.${C_RESET}\n"
        else
            printf "  ${C_DIM}%-14s %-22s %-10s${C_RESET}\n" "Disco" "Nome" "Tamanho"
        fi
        echo ""

        interactive_picker "${_display[@]}" || return

        # Refresh selecionado
        if (( PICKER_RESULT == ${#_display[@]} )); then
            _refresh=1
            continue
        fi

        # Não deveria chegar aqui sem discos, mas protege
        if (( ${#DISKS[@]} == 0 )); then
            auto_return 2
            return
        fi

        SELECTED_DISK="${DISKS[$PICKER_RESULT]}"
        SELECTED_DISK_NAME=$(
            (( DEMO_MODE )) \
                && echo "Samsung USB 3.1" \
                || disk_media_name "$SELECTED_DISK"
        )
        INSTALLER_CREATED=0
        DISK_FORMATTED=0
        (( ! DEMO_MODE )) && sync_disk_state

        # Aviso se disco < 16 GB
        if (( ! DEMO_MODE )); then
            local _bytes
            IFS='|' read -r _ _ _ _bytes <<< "$(disk_details "$SELECTED_DISK")"
            if (( _bytes > 0 && _bytes < 16000000000 )); then
                echo ""
                printf "  ${C_WARN}⚠  Este disco tem menos de 16 GB.${C_RESET}\n"
                printf "  ${C_DIM}   O instalador exige no mínimo 16 GB (recomendado 32 GB+).${C_RESET}\n"
                if ! confirm_visual "Usar mesmo assim?"; then
                    SELECTED_DISK=""
                    SELECTED_DISK_NAME=""
                    return
                fi
            fi
        fi
    done
}

format_disk() {
    if [[ -z "$SELECTED_DISK" ]]; then
        return
    fi

    print_subscreen "Formatar disco"
    echo ""

    printf "  %-12s %s\n" "Nome:"    "$SELECTED_DISK_NAME"
    printf "  %-12s /dev/%s\n" "Destino:" "$SELECTED_DISK"
    printf "  %-12s %s\n" "Volume:"  "$VOLUME_NAME"
    printf "  %-12s GPT + Mac OS Extended (Journaled)\n" "Esquema:"
    echo ""

    if (( DEMO_MODE )); then
        printf "  ${C_DIM}Conteúdo atual:${C_RESET}\n\n"
        printf "  /dev/disk2 (external, physical):\n"
        printf "  %s  %-28s %-10s %s\n" "#:" "TYPE NAME" "SIZE" "IDENTIFIER"
        printf "  %s  %-28s %-10s %s\n" "0:" "GUID_partition_scheme" "*32.0 GB" "disk2"
        printf "  %s  %-28s %-10s %s\n" "1:" "EFI EFI" "209.7 MB" "disk2s1"
        printf "  %s  %-28s %-10s %s\n" "2:" "Microsoft Basic Data" "31.8 GB" "disk2s2"
        echo ""
    else
        show_disk_volumes "$SELECTED_DISK"
    fi

    printf "  ${C_WARN}⚠  Todo o conteúdo do disco será APAGADO permanentemente.${C_RESET}\n"
    confirm_visual "Formatar /dev/$SELECTED_DISK agora?" || return

    echo ""

    if (( DEMO_MODE )); then
        spinner_start "Desmontando disco..."
        sleep 1.2
        spinner_stop
        spinner_start "Formatando (GPT + Mac OS Extended)..."
        sleep 2.0
        spinner_stop
    else
        printf "  ${C_DIM}·${C_RESET} Verificando permissões...\n"
        if ! sudo -v; then
            printf "  ${C_WARN}Senha incorreta ou sudo negado.${C_RESET}\n"
            log_error "sudo -v falhou em format_disk"
            pause
            return
        fi

        echo ""
        spinner_start "Desmontando disco..."
        diskutil unmountDisk force "/dev/$SELECTED_DISK" > /dev/null 2>&1
        spinner_stop

        spinner_start "Formatando (GPT + Mac OS Extended)..."
        local fmt_out fmt_exit
        fmt_out=$(sudo diskutil eraseDisk "$DISK_FORMAT" "$VOLUME_NAME" GPT "/dev/$SELECTED_DISK" 2>&1)
        fmt_exit=$?
        spinner_stop

        if (( fmt_exit != 0 )); then
            log_error "diskutil eraseDisk falhou (exit $fmt_exit): $fmt_out"
            printf "  ${C_WARN}Erro ao formatar o disco.${C_RESET}\n"
            printf "  ${C_DIM}Log: %s${C_RESET}\n" "$LOG_FILE"
            pause
            return
        fi
    fi

    DISK_FORMATTED=1
    INSTALLER_CREATED=0
    # SELECTED_INSTALLER é preservado — o instalador é independente do disco
    SELECTED_DISK_NAME="$(disk_media_name "$SELECTED_DISK")"
    printf "  ${C_OK}✓ Formatação concluída.${C_RESET}\n"
    sleep 1
}

installer_label() {
    local app="$1" name

    name=$(defaults read "${app}/Contents/Info" CFBundleDisplayName 2>/dev/null) || \
    name=$(defaults read "${app}/Contents/Info" CFBundleName 2>/dev/null) || \
    name=$(basename "$app" .app)

    echo "$name"
}

find_macos_installers() {
    local app
    for app in /Applications/*.app(N); do
        [[ -x "${app}/Contents/Resources/createinstallmedia" ]] && echo "$app"
    done
}

_do_download_macos() {
    print_subscreen "Baixar instalador macOS"
    echo ""

    local -a _titles=() _versions=() _sizes=()
    local -a _display=()

    if (( DEMO_MODE )); then
        _titles=("macOS Sequoia" "macOS Sonoma")
        _versions=("15.5" "14.7")
        _sizes=(14680064 13631488)
    else
        spinner_start "Consultando servidores Apple..."
        local raw
        raw=$(softwareupdate --list-full-installers 2>&1)
        spinner_stop

        if ! echo "$raw" | grep -q '^\* Title:'; then
            printf "  ${C_WARN}Não foi possível obter a lista de instaladores.${C_RESET}\n"
            printf "  ${C_DIM}Verifique sua conexão com a internet.${C_RESET}\n"
            log_error "softwareupdate --list-full-installers falhou: $raw"
            auto_return 4
            return 1
        fi

        while IFS='|' read -r _t _v _s _b; do
            _titles+=("$_t"); _versions+=("$_v"); _sizes+=("$_s")
        done < <(echo "$raw" | awk '/^\* Title:/ {
            line = $0
            sub(/^\* Title: /, "", line)
            n = split(line, p, ", ")
            title   = p[1]
            version = p[2]; sub(/^Version: /, "", version)
            size    = p[3]; sub(/^Size: /,    "", size); sub(/KiB$/, "", size)
            build   = p[4]; sub(/^Build: /,   "", build)
            print title "|" version "|" size "|" build
        }')

        if (( ${#_titles[@]} == 0 )); then
            printf "  ${C_WARN}Nenhuma versão disponível no momento.${C_RESET}\n"
            auto_return 4
            return 1
        fi
    fi

    local _i _gb
    for _i in {1..${#_titles[@]}}; do
        (( _gb = _sizes[$_i] / 1024 / 1024 ))
        _display+=("$(printf '%-28s  v%-10s  ~%d GB' \
            "${_titles[$_i]}" "${_versions[$_i]}" "$_gb")")
    done

    echo ""
    interactive_picker "${_display[@]}" || return 1

    local idx=$PICKER_RESULT
    local sel_title="${_titles[$idx]}"
    local sel_version="${_versions[$idx]}"
    local sel_size_kib="${_sizes[$idx]}"
    local sel_gb sel_bytes
    (( sel_gb    = sel_size_kib / 1024 / 1024 ))
    (( sel_bytes = sel_size_kib * 1024 ))

    echo ""
    printf "  ${C_BOLD}%s %s${C_RESET}\n" "$sel_title" "$sel_version"
    printf "  ${C_DIM}Tamanho aproximado: ~%d GB — pode levar vários minutos.${C_RESET}\n" "$sel_gb"
    printf "  ${C_DIM}Destino: /Applications${C_RESET}\n"

    confirm_visual "Baixar agora?" || return 1

    echo ""

    if (( DEMO_MODE )); then
        local _pct _el=0
        for _pct in 0 5 12 20 29 38 47 56 65 74 82 89 95 100; do
            draw_progress_bar "$_pct" "Baixando $sel_title" "$(format_elapsed $_el)"
            sleep 0.14
            (( _el += 2 ))
        done
        printf "\n"
        printf "  ${C_OK}✓ %s %s disponível em /Applications.${C_RESET}\n" "$sel_title" "$sel_version"
        printf "  ${C_DIM}  (simulado — nenhum download foi realizado)${C_RESET}\n"
        SELECTED_INSTALLER="/Applications/Install macOS Sequoia.app"
        INSTALLER_CREATED=0
        printf "  ${C_DIM}↳ Selecionado: Install macOS Sequoia${C_RESET}\n"
        sleep 1
        return 0
    fi

    # Snapshot dos instaladores antes do download
    local -a _before=()
    local _app
    while IFS= read -r _app; do
        [[ -n "$_app" ]] && _before+=("$_app")
    done < <(find_macos_installers)

    local tmpfile
    tmpfile=$(mktemp /tmp/bootstick_dl_XXXXXX)
    log_info "Iniciando download: $sel_title $sel_version"

    softwareupdate --fetch-full-installer --full-installer-version "$sel_version" \
        > "$tmpfile" 2>&1 &
    local dl_pid=$!

    local start_time=$SECONDS elapsed pct=0 app_path="" app_bytes

    draw_progress_bar 0 "Conectando..." "0s"

    while kill -0 "$dl_pid" 2>/dev/null; do
        elapsed=$(( SECONDS - start_time ))

        # Detectar .app novo em /Applications
        if [[ -z "$app_path" ]]; then
            for _app in /Applications/Install\ macOS*.app(N); do
                local _found=0 _b
                for _b in "${_before[@]}"; do
                    [[ "$_b" == "$_app" ]] && { _found=1; break; }
                done
                (( ! _found )) && { app_path="$_app"; break; }
            done
        fi

        if [[ -n "$app_path" && -d "$app_path" && sel_bytes -gt 0 ]]; then
            app_bytes=$(du -sk -- "$app_path" 2>/dev/null | awk '{print $1 * 1024}')
            if (( app_bytes > 0 )); then
                pct=$(( app_bytes * 100 / sel_bytes ))
                (( pct > 99 )) && pct=99
            fi
        fi

        draw_progress_bar "$pct" "Baixando $sel_title" "$(format_elapsed $elapsed)"
        sleep 1
    done

    wait "$dl_pid"
    local exit_status=$?
    local elapsed_total=$(( SECONDS - start_time ))

    (( exit_status == 0 )) && draw_progress_bar 100 "Concluído" "$(format_elapsed $elapsed_total)"
    printf "\n"

    local dl_output
    dl_output=$(cat "$tmpfile" 2>/dev/null)
    printf "[%s] --- download output ---\n%s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$dl_output" >> "$LOG_FILE"
    rm -f "$tmpfile"

    if (( exit_status != 0 )); then
        printf "  ${C_WARN}Erro ao baixar o instalador (código %d).${C_RESET}\n" "$exit_status"
        printf "  ${C_DIM}Log: %s${C_RESET}\n" "$LOG_FILE"
        log_error "softwareupdate --fetch-full-installer falhou (exit $exit_status)"
        if echo "$dl_output" | grep -qiE "not compatible|incompatível"; then
            printf "  ${C_DIM}Esta versão pode não ser compatível com seu macOS atual.${C_RESET}\n"
        elif echo "$dl_output" | grep -qiE "not available|indisponível|not found"; then
            printf "  ${C_DIM}Versão indisponível para download no momento.${C_RESET}\n"
        fi
        pause
        return 1
    fi

    printf "  ${C_OK}✓ %s %s disponível em /Applications.${C_RESET}\n" "$sel_title" "$sel_version"
    notify_macos "$APP_NAME" "$sel_title $sel_version disponível em /Applications."
    log_info "Download concluído: $sel_title $sel_version em $(format_elapsed $elapsed_total)"

    # Auto-seleciona o instalador recém-baixado
    local _new_app _found _b
    while IFS= read -r _new_app; do
        [[ -n "$_new_app" ]] || continue
        _found=0
        for _b in "${_before[@]}"; do
            [[ "$_b" == "$_new_app" ]] && { _found=1; break; }
        done
        if (( ! _found )); then
            SELECTED_INSTALLER="$_new_app"
            INSTALLER_CREATED=0
            printf "  ${C_DIM}↳ Selecionado automaticamente: %s${C_RESET}\n" "$(installer_label "$_new_app")"
            break
        fi
    done < <(find_macos_installers)

    sleep 1
    return 0
}

_do_select_app_manual() {
    print_subscreen "Selecionar instalador manualmente"
    echo ""
    printf "  ${C_DIM}Abrindo seletor de arquivo — escolha o Install macOS*.app${C_RESET}\n"
    printf "  ${C_DIM}(útil para instaladores baixados via gibMacOS ou outros meios)${C_RESET}\n"
    echo ""

    local chosen
    chosen=$(osascript 2>/dev/null <<'EOF'
try
    set chosen to choose file of type {"com.apple.application-bundle"} \
        with prompt "Selecione o instalador macOS (.app):" \
        default location (path to applications folder)
    POSIX path of chosen
on error
    ""
end try
EOF
    )

    if [[ -z "$chosen" ]]; then
        printf "  ${C_DIM}Nenhum arquivo selecionado.${C_RESET}\n"
        sleep 1
        return 1
    fi

    if [[ ! -x "${chosen}/Contents/Resources/createinstallmedia" ]]; then
        printf "  ${C_WARN}O app selecionado não parece ser um instalador macOS válido.${C_RESET}\n"
        printf "  ${C_DIM}Certifique-se de selecionar um .app com createinstallmedia dentro.${C_RESET}\n"
        pause
        return 1
    fi

    SELECTED_INSTALLER="$chosen"
    INSTALLER_CREATED=0
    printf "  ${C_OK}✓ Selecionado: %s${C_RESET}\n" "$(installer_label "$chosen")"
    sleep 1
    return 0
}

choose_macos() {
    print_subscreen "Obter instalador macOS"

    typeset -a INSTALLERS=()
    local -a _display=()

    if (( DEMO_MODE )); then
        INSTALLERS=(
            "/Applications/Install macOS Sequoia.app"
            "/Applications/Install macOS Sonoma.app"
        )
        _display=("Install macOS Sequoia" "Install macOS Sonoma")
    else
        local app
        while IFS= read -r app; do
            [[ -n "$app" ]] && INSTALLERS+=("$app")
        done < <(find_macos_installers)

        local _i
        for _i in {1..${#INSTALLERS[@]}}; do
            _display+=("$(installer_label "${INSTALLERS[$_i]}")")
        done

        if (( ${#INSTALLERS[@]} == 0 )); then
            echo ""
            printf "  ${C_DIM}Nenhum instalador encontrado em /Applications.${C_RESET}\n"
        fi
    fi

    local _n_installers=${#_display[@]}
    _display+=("↓  Baixar dos servidores Apple...")
    _display+=("📂 Selecionar .app manualmente (gibMacOS etc.)")

    echo ""
    interactive_picker "${_display[@]}" || return

    local _download_idx=$(( _n_installers + 1 ))
    local _manual_idx=$(( _n_installers + 2 ))

    if (( PICKER_RESULT == _download_idx )); then
        _do_download_macos
        return
    fi

    if (( PICKER_RESULT == _manual_idx )); then
        _do_select_app_manual
        return
    fi

    SELECTED_INSTALLER="${INSTALLERS[$PICKER_RESULT]}"
    INSTALLER_CREATED=0
}

efi_partition() {
    local disk="$1"
    local part candidate

    for candidate in "${disk}s1" "${disk}s2"; do
        if diskutil info "/dev/$candidate" 2>/dev/null | grep -q 'EFI'; then
            echo "$candidate"
            return 0
        fi
    done

    part=$(diskutil list "/dev/$disk" 2>/dev/null | awk '/EFI/ {gsub("/dev/","",$NF); print $NF; exit}')
    [[ -n "$part" ]] && echo "$part"
}

mount_efi() {
    if [[ -z "$SELECTED_DISK" ]]; then
        return
    fi

    print_subscreen "Montar partição EFI"
    echo ""

    if (( DEMO_MODE )); then
        printf "  ${C_DIM}·${C_RESET} Montando /dev/disk2s1 ...\n"
        sleep 0.8
        printf "  ${C_OK}✓ EFI aberta no Finder — copie sua pasta EFI do OpenCore.${C_RESET}\n"
        printf "  ${C_DIM}  (simulado — Finder não foi aberto)${C_RESET}\n"
        sleep 1
        return
    fi

    local EFI_PART
    EFI_PART=$(efi_partition "$SELECTED_DISK")

    if [[ -z "$EFI_PART" ]]; then
        printf "  ${C_WARN}Partição EFI não encontrada em /dev/$SELECTED_DISK${C_RESET}\n"
        pause
        return
    fi

    printf "  ${C_DIM}·${C_RESET} Montando /dev/$EFI_PART ...\n"
    local efi_out
    efi_out=$(sudo diskutil mount "/dev/$EFI_PART" 2>&1)
    if (( $? != 0 )); then
        echo ""
        printf "  ${C_WARN}Erro ao montar EFI.${C_RESET}\n"
        printf "  ${C_DIM}Log: %s${C_RESET}\n" "$LOG_FILE"
        log_error "diskutil mount /dev/$EFI_PART falhou: $efi_out"
        pause
        return
    fi

    sleep 1

    if [[ -d /Volumes/EFI ]]; then
        open /Volumes/EFI
        printf "  ${C_OK}✓ EFI aberta no Finder — copie sua pasta EFI do OpenCore.${C_RESET}\n"
    else
        printf "  ${C_OK}✓ EFI montada. Verifique /Volumes.${C_RESET}\n"
    fi

    sleep 1
}

create_installer() {
    if [[ -z "$SELECTED_DISK" || -z "$SELECTED_INSTALLER" ]]; then
        return
    fi

    local CREATE_MEDIA="$SELECTED_INSTALLER/Contents/Resources/createinstallmedia"
    local VOLUME_PATH="/Volumes/$VOLUME_NAME"

    if (( ! DEMO_MODE )); then
        if [[ ! -x "$CREATE_MEDIA" ]]; then
            print_subscreen "Erro"
            echo ""
            printf "  ${C_WARN}createinstallmedia não encontrado:${C_RESET}\n"
            printf "  ${C_DIM}%s${C_RESET}\n" "$CREATE_MEDIA"
            pause
            return
        fi

        if [[ ! -d "$VOLUME_PATH" ]]; then
            print_subscreen "Erro"
            echo ""
            printf "  ${C_WARN}Volume \"%s\" não encontrado.${C_RESET}\n" "$VOLUME_NAME"
            printf "  ${C_DIM}Formate o disco primeiro — opção [F].${C_RESET}\n"
            pause
            return
        fi

        if volume_is_apfs; then
            print_subscreen "Erro"
            echo ""
            printf "  ${C_WARN}O volume está em APFS — não serve para mídia bootável.${C_RESET}\n"
            printf "  ${C_DIM}Use [F] para formatar em Mac OS Extended e tente [B] de novo.${C_RESET}\n"
            DISK_FORMATTED=0
            pause
            return
        fi
    fi

    print_subscreen "Criar instalador bootável"
    echo ""

    printf "  %-14s %s\n" "Disco:"      "$SELECTED_DISK_NAME"
    printf "  %-14s %s\n" "Instalador:" "$(installer_label "$SELECTED_INSTALLER")"
    printf "  %-14s %s\n" "Volume:"     "$VOLUME_PATH"
    echo ""
    printf "  ${C_DIM}Pode levar 15–40 minutos. Não feche o Terminal.${C_RESET}\n"

    confirm_visual "Iniciar criação da mídia bootável?" || return

    echo ""
    printf "  ${C_DIM}·${C_RESET} Iniciando createinstallmedia...\n"
    echo ""

    if (( DEMO_MODE )); then
        local phase pct _el=0
        phase="Apagando disco"
        for pct in 0 10 20 30 40 50 60 70 80 90 100; do
            draw_progress_bar $pct "$phase" "$(format_elapsed $_el)"; sleep 0.12
            (( _el++ ))
        done
        phase="Copiando arquivos"
        for pct in 0 10 20 30 40 50 60 70 80 90 100; do
            draw_progress_bar $pct "$phase" "$(format_elapsed $_el)"; sleep 0.18
            (( _el += 2 ))
        done
        phase="Tornando bootável"
        draw_progress_bar 95 "$phase" "$(format_elapsed $_el)"; sleep 0.4; (( _el++ ))
        draw_progress_bar 100 "Concluído" "$(format_elapsed $_el)"; sleep 0.3
        printf "\n"
        printf "  ${C_OK}✓ Instalador bootável criado com sucesso.${C_RESET}\n"
        printf "  ${C_DIM}  (simulado — nenhum disco foi modificado)${C_RESET}\n"
        INSTALLER_CREATED=1
        sleep 1
        mount_efi
        return
    fi

    printf "  ${C_DIM}·${C_RESET} Verificando permissões...\n"
    if ! sudo -v; then
        printf "  ${C_WARN}Senha incorreta ou sudo negado.${C_RESET}\n"
        log_error "sudo -v falhou em create_installer"
        pause
        return
    fi

    local tmpfile
    tmpfile=$(mktemp /tmp/bootstick_XXXXXX)
    log_info "Iniciando createinstallmedia: $SELECTED_INSTALLER → $VOLUME_PATH"

    local create_pid="" _interrupted=0

    # Ctrl+C cancela com limpeza
    trap '
        _interrupted=1
        [[ -n "$create_pid" ]] && sudo kill "$create_pid" 2>/dev/null
    ' INT

    sudo "$CREATE_MEDIA" --volume "$VOLUME_PATH" --nointeraction > "$tmpfile" 2>&1 &
    create_pid=$!

    local phase="Iniciando" prev_phase="" last_pct=0 latest_line pct
    local start_time=$SECONDS elapsed

    draw_progress_bar 0 "$phase" "0s"

    while kill -0 "$create_pid" 2>/dev/null; do
        elapsed=$(( SECONDS - start_time ))
        latest_line=$(tail -1 "$tmpfile" 2>/dev/null)
        prev_phase="$phase"

        echo "$latest_line" | grep -qiE "erasing"                      && phase="Apagando disco"
        echo "$latest_line" | grep -qiE "copying to disk|copying files" && phase="Copiando arquivos"
        echo "$latest_line" | grep -qiE "making.*bootable"             && phase="Tornando bootável"
        echo "$latest_line" | grep -qiE "copying boot"                 && phase="Copiando boot"
        echo "$latest_line" | grep -qiE "install media now"            && phase="Concluído"

        [[ "$phase" != "$prev_phase" ]] && last_pct=0

        if echo "$latest_line" | grep -qE '[0-9]+%'; then
            pct=$(echo "$latest_line" | grep -oE '[0-9]+' | tail -1)
            if [[ -n "$pct" ]] && (( pct >= last_pct && pct <= 100 )); then
                last_pct=$pct
            fi
        fi

        draw_progress_bar "$last_pct" "$phase" "$(format_elapsed $elapsed)"
        sleep 0.5
    done

    wait "$create_pid"
    local exit_status=$?
    trap - INT

    local elapsed_total=$(( SECONDS - start_time ))

    if (( _interrupted )); then
        printf "\n"
        printf "  ${C_WARN}⚠  Operação cancelada pelo usuário.${C_RESET}\n"
        log_info "createinstallmedia cancelado após $(format_elapsed $elapsed_total)"
        cat "$tmpfile" >> "$LOG_FILE"
        rm -f "$tmpfile"
        pause
        return
    fi

    (( exit_status == 0 )) && draw_progress_bar 100 "Concluído" "$(format_elapsed $elapsed_total)"
    printf "\n"
    cat "$tmpfile" >> "$LOG_FILE"
    rm -f "$tmpfile"

    if (( exit_status != 0 )); then
        echo ""
        printf "  ${C_WARN}Erro ao criar instalador (código %d).${C_RESET}\n" "$exit_status"
        printf "  ${C_DIM}Log: %s${C_RESET}\n" "$LOG_FILE"
        notify_macos "$APP_NAME" "Erro ao criar o instalador bootável."
        log_error "createinstallmedia falhou (exit $exit_status) após $(format_elapsed $elapsed_total)"
        pause
        return
    fi

    log_info "createinstallmedia concluído em $(format_elapsed $elapsed_total)"

    local verified=0 vol
    for vol in "/Volumes/Install macOS"*(N); do
        [[ -d "$vol" ]] && { verified=1; break; }
    done

    if (( ! verified )); then
        printf "  ${C_WARN}⚠  Processo concluiu mas o volume não foi localizado em /Volumes.${C_RESET}\n"
        printf "  ${C_DIM}Verifique manualmente antes de continuar.${C_RESET}\n"
        notify_macos "$APP_NAME" "Instalador criado — verifique o volume manualmente."
    else
        printf "  ${C_OK}✓ Instalador bootável criado com sucesso.${C_RESET}\n"
        notify_macos "$APP_NAME" "Instalador bootável pronto! Copie a pasta EFI do OpenCore."
    fi

    INSTALLER_CREATED=1
    mount_efi
}

# =========================================================
# Modo demo (oculto — pressione "!" no menu principal)
# =========================================================

run_demo() {
    DEMO_MODE=1
    SELECTED_DISK=""
    SELECTED_DISK_NAME=""
    DISK_FORMATTED=0
    SELECTED_INSTALLER=""
    INSTALLER_CREATED=0

    clear_screen
    print_banner "Modo dev  ${C_WARN}[DEMO — nenhum disco será modificado]${C_RESET}"
    echo ""
    spinner_start "Carregando modo desenvolvimento..."
    sleep 2
    spinner_stop

    while true; do
        show_menu
        case "$MENU_RESULT" in
            d) choose_disk ;;
            f) [[ -n "$SELECTED_DISK" ]] && format_disk ;;
            m) choose_macos ;;
            b) [[ -n "$SELECTED_DISK" ]] && [[ -n "$SELECTED_INSTALLER" ]] && (( ! INSTALLER_CREATED )) && create_installer ;;
            e) (( INSTALLER_CREATED )) && mount_efi ;;
            h) clear_screen; print_banner "Ajuda e documentação"; print_about_full ;;
            q) break ;;
        esac
    done

    DEMO_MODE=0
    SELECTED_DISK=""
    SELECTED_DISK_NAME=""
    DISK_FORMATTED=0
    SELECTED_INSTALLER=""
    INSTALLER_CREATED=0
}

if [[ "$(uname)" != "Darwin" ]]; then
    print_banner "Erro"
    echo ""
    printf "  ${C_WARN}Este script só funciona no macOS.${C_RESET}\n"
    exit 1
fi

init_terminal

while true; do
    show_menu

    case "$MENU_RESULT" in
        d) choose_disk ;;
        f) [[ -n "$SELECTED_DISK" ]] && format_disk ;;
        m) choose_macos ;;
        b) [[ -n "$SELECTED_DISK" ]] && [[ -n "$SELECTED_INSTALLER" ]] && (( ! INSTALLER_CREATED )) && create_installer ;;
        e) (( INSTALLER_CREATED )) && mount_efi ;;
        '!') run_demo ;;
        h) clear_screen; print_banner "Ajuda e documentação"; print_about_full ;;
        q) print_goodbye ;;
    esac
done
