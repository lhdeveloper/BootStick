#!/bin/zsh

# Limpa scrollback + tela (remove linha "/path/BootStick.command ; exit;" do Terminal)
[[ -t 1 ]] && printf '\033[3J\033[2J\033[H'

# =========================================================
# BootStick — Hackintosh bootable USB assistant
# =========================================================

setopt NO_NOMATCH 2>/dev/null

APP_NAME="BootStick"
APP_TAGLINE="Assistente de mídia bootável para Hackintosh"
SCRIPT_VERSION=$(git -C "$(dirname "$0")" describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo "1.4.0")
SCRIPT_BUILD=$(date -r "$0" +%Y.%m.%d 2>/dev/null || echo "—")
VOLUME_NAME="Install macOS"
DISK_FORMAT="JHFS+"

SELECTED_DISK=""
SELECTED_DISK_NAME=""
DISK_FORMATTED=0
SELECTED_INSTALLER=""
INSTALLER_CREATED=0
SPINNER_PID=""
PICKER_RESULT=0
MENU_RESULT=""

typeset -a MENU_LETTERS
MENU_LETTERS=( A B C D E F G H I J K L M N O P Q R S T U V W X Y Z )

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

TERM_ROWS=48

clear_screen() {
    printf '\033[3J\033[2J\033[H'
}

init_terminal() {
    [[ -t 1 ]] || return

    local cols
    cols=$(tput cols 2>/dev/null)
    (( cols < 1 )) && cols=80

    # Título da janela
    printf '\e]0;%s v%s\a' "$APP_NAME" "$SCRIPT_VERSION"

    # Só aumenta a altura; largura permanece a do Terminal
    sleep 0.2
    printf '\e[8;%d;%dt' "$TERM_ROWS" "$cols" 2>/dev/null

    if [[ "$TERM_PROGRAM" == "Apple_Terminal" ]]; then
        osascript 2>/dev/null <<EOF
tell application "Terminal"
    if (count of windows) > 0 then
        tell front window
            set b to bounds
            set bounds to {item 1 of b, item 2 of b, item 3 of b, item 2 of b + 680}
        end tell
    end if
end tell
EOF
    fi

    clear_screen
}

term_too_small() {
    local lines
    lines=$(tput lines 2>/dev/null || echo 0)
    (( lines > 0 && lines < 32 ))
}

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

print_banner() {
    local subtitle="${1:-}"

    echo ""
    print_ascii_logo
    echo ""
    print_version_badge

    if [[ -n "$subtitle" ]]; then
        echo ""
        printf "  ${C_DIM}%s${C_RESET}\n" "$subtitle"
    fi

    print_divider
}

print_about_short() {
    printf "  ${C_DIM}Pendrive bootável macOS · OpenCore · Etapas: D → F/I → B → E${C_RESET}\n"
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

  Navegação: ↑↓ mover   Enter selecionar   letra atalho direto

  Fluxo: [D] disco  [F] formatar  [I] instalador  [B] bootável  [E] EFI

  Formato do pendrive: Mac OS Extended (JHFS+) — exigido pelo
  createinstallmedia em versões recentes (não use APFS no USB).
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
# Barra de progresso
# =========================================================

draw_progress_bar() {
    local pct="$1" label="${2:-}"
    local width=36 filled empty bar i
    (( filled = pct * width / 100 ))
    (( empty  = width - filled ))
    bar=""
    for (( i=0; i<filled; i++ )); do bar+="█"; done
    for (( i=0; i<empty;  i++ )); do bar+="░"; done
    printf "\r  ${C_ACCENT}[%s]${C_RESET} ${C_BOLD}%3d%%${C_RESET}  ${C_DIM}%s${C_RESET}  " "$bar" "$pct" "$label"
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
# Atalhos: ↑↓ navegar · Enter confirmar · letra pula+confirma · Q cancela
# =========================================================

interactive_picker() {
    local -a items=("$@")
    local n=${#items[@]} sel=1 key key2 key3 ku i

    printf '\033[?25l'  # oculta cursor
    printf '\0337'      # salva posição do cursor

    while true; do
        printf '\0338'  # restaura posição salva e redesenha
        for (( i=1; i<=n; i++ )); do
            if (( i == sel )); then
                printf "\r\033[K  ${C_ACCENT}▶ [%s]${C_RESET}  ${C_BOLD}%s${C_RESET}\n" \
                    "${MENU_LETTERS[$i]}" "${items[$i]}"
            else
                printf "\r\033[K    ${C_DIM}[%s]  %s${C_RESET}\n" \
                    "${MENU_LETTERS[$i]}" "${items[$i]}"
            fi
        done
        printf "\r\033[K\n"
        printf "\r\033[K  ${C_DIM}↑↓ navegar   Enter selecionar   Q voltar${C_RESET}"

        read -k 1 -s key

        case "$key" in
            $'\033')
                key2=""; read -k 1 -s -t 0.05 key2 2>/dev/null
                if [[ "$key2" == "[" ]]; then
                    key3=""; read -k 1 -s -t 0.05 key3 2>/dev/null
                    [[ "$key3" == "A" ]] && (( sel > 1 )) && (( sel-- ))
                    [[ "$key3" == "B" ]] && (( sel < n )) && (( sel++ ))
                else
                    # ESC puro = cancelar
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
            [a-zA-Z])
                ku="${key:u}"
                for (( i=1; i<=n; i++ )); do
                    if [[ "${MENU_LETTERS[$i]}" == "$ku" ]]; then
                        printf '\0338'; printf "\033[%dB\r\n" $(( n + 2 ))
                        printf '\033[?25h'; PICKER_RESULT=$i; return 0
                    fi
                done
                ;;
        esac
    done
}

# =========================================================
# Seleção interativa do menu principal com setas do teclado
#
# Args: "action|label|style" ... (style: accent | dim)
# Resultado em $MENU_RESULT (action string)
# =========================================================

main_menu_picker() {
    local -a entries=("$@")
    local n=${#entries[@]} sel=1 key key2 key3 i action label style kl

    MENU_RESULT=""
    printf '\033[?25l'
    printf '\0337'

    while true; do
        printf '\0338'
        for (( i=1; i<=n; i++ )); do
            IFS='|' read -r action label style <<< "${entries[$i]}"
            if (( i == sel )); then
                printf "\r\033[K  ${C_ACCENT}▶ [%s]${C_RESET}  ${C_BOLD}%s${C_RESET}\n" \
                    "${action:u}" "$label"
            else
                printf "\r\033[K    ${C_DIM}[%s]  %s${C_RESET}\n" "${action:u}" "$label"
            fi
        done
        printf "\r\033[K\n"
        printf "\r\033[K  ${C_DIM}↑↓ navegar   Enter selecionar${C_RESET}"

        read -k 1 -s key

        case "$key" in
            $'\033')
                key2=""; read -k 1 -s -t 0.05 key2 2>/dev/null
                if [[ "$key2" == "[" ]]; then
                    key3=""; read -k 1 -s -t 0.05 key3 2>/dev/null
                    [[ "$key3" == "A" ]] && (( sel > 1 )) && (( sel-- ))
                    [[ "$key3" == "B" ]] && (( sel < n )) && (( sel++ ))
                fi
                ;;
            $'\n'|$'\r')
                IFS='|' read -r action label style <<< "${entries[$sel]}"
                printf '\0338'; printf "\033[%dB\r\n" $(( n + 2 ))
                printf '\033[?25h'; MENU_RESULT="$action"; return 0
                ;;
            ['!'])
                printf '\0338'; printf "\033[%dB\r\n" $(( n + 2 ))
                printf '\033[?25h'; MENU_RESULT="!"; return 0
                ;;
            [a-zA-Z])
                kl="${key:l}"
                for (( i=1; i<=n; i++ )); do
                    IFS='|' read -r action label style <<< "${entries[$i]}"
                    if [[ "$action" == "$kl" ]]; then
                        printf '\0338'; printf "\033[%dB\r\n" $(( n + 2 ))
                        printf '\033[?25h'; MENU_RESULT="$action"; return 0
                    fi
                done
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

workflow_info() {
    local step desc total=4 num=1

    if [[ -z "$SELECTED_DISK" ]]; then
        num=1; desc="Selecionar disco USB/SSD"
    elif [[ -z "$SELECTED_INSTALLER" ]]; then
        num=2
        if (( DISK_FORMATTED )); then
            desc="Selecionar instalador macOS"
        else
            desc="Formatar disco ou selecionar instalador macOS"
        fi
    elif (( ! INSTALLER_CREATED )); then
        num=3
        if (( DISK_FORMATTED )); then
            desc="Criar instalador bootável no pendrive"
        else
            desc="Criar instalador no pendrive (formate antes se precisar)"
        fi
    else
        num=4; desc="Instalador pronto — copiar OpenCore na EFI"
    fi

    step="Passo ${num}/${total}"
    echo "$step|$desc"
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
    local step desc
    sync_disk_state
    IFS='|' read -r step desc <<< "$(workflow_info)"

    clear_screen

    if term_too_small; then
        init_terminal
    fi

    print_banner "$APP_TAGLINE"
    print_about_short
    echo ""
    printf "  ${C_ACCENT}${C_BOLD}%s${C_RESET}\n" "$step"
    printf "  ${C_DIM}%s${C_RESET}\n" "$desc"
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
    if [[ -z "$SELECTED_DISK" ]]; then
        _items+=("d|Selecionar disco USB/SSD|accent")
    else
        if [[ -z "$SELECTED_INSTALLER" ]]; then
            (( ! DISK_FORMATTED )) && _items+=("f|Formatar disco (apaga tudo)|accent")
            _items+=("i|Selecionar instalador macOS|accent")
        elif (( ! INSTALLER_CREATED )); then
            _items+=("b|Criar instalador bootável no pendrive|accent")
            (( ! DISK_FORMATTED )) && _items+=("f|Formatar disco (necessário antes de criar)|accent")
            _items+=("i|Trocar instalador macOS|dim")
        else
            _items+=("e|Montar e abrir EFI (OpenCore)|accent")
            _items+=("f|Reformatar disco (opcional)|dim")
        fi
        _items+=("d|Trocar disco|dim")
    fi
    _items+=("h|Ajuda / sobre|dim")
    _items+=("q|Sair|dim")

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
            print name "|" size "|" proto
        }'
}

choose_disk() {
    # Confirmação ao trocar disco já selecionado
    if [[ -n "$SELECTED_DISK" ]]; then
        print_subscreen "Trocar disco"
        echo ""
        printf "  %-12s ${C_OK}%s${C_RESET} ${C_DIM}(/dev/%s)${C_RESET}\n" "Atual:" "$SELECTED_DISK_NAME" "$SELECTED_DISK"
        echo ""
        printf "  ${C_DIM}Trocar o disco reinicia todas as etapas.${C_RESET}\n"
        echo ""
        read "CONFIRM?${C_BOLD}Continuar? (s/n):${C_RESET} "
        [[ "${CONFIRM:l}" != "s" ]] && return
    fi

    print_subscreen "Passo 1 — Selecionar disco"

    typeset -a DISKS
    typeset -A seen
    DISKS=()
    seen=()

    local DISK

    add_disk() {
        local d="$1"
        is_whole_disk "$d" || return
        [[ -n "${seen[$d]}" ]] && return
        seen[$d]=1
        DISKS+=("$d")
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

    if (( ${#DISKS[@]} == 0 )); then
        echo ""
        printf "  ${C_WARN}Nenhum disco encontrado.${C_RESET} Conecte um pendrive/SSD USB.\n"
        auto_return 3
        return
    fi

    echo ""
    printf "  ${C_DIM}%-14s %-22s %-10s${C_RESET}\n" "Disco" "Nome" "Tamanho"
    echo ""

    local -a _display
    _display=()
    local _i _d _n _s _p
    for _i in {1..${#DISKS[@]}}; do
        _d="${DISKS[$_i]}"
        IFS='|' read -r _n _s _p <<< "$(disk_details "$_d")"
        _display+=("$(printf '%-14s %-22s %s' "/dev/$_d" "$_n" "$_s")")
    done

    interactive_picker "${_display[@]}" || return

    SELECTED_DISK="${DISKS[$PICKER_RESULT]}"
    SELECTED_DISK_NAME="$(disk_media_name "$SELECTED_DISK")"
    SELECTED_INSTALLER=""
    INSTALLER_CREATED=0
    DISK_FORMATTED=0
    sync_disk_state
}

format_disk() {
    if [[ -z "$SELECTED_DISK" ]]; then
        return
    fi

    print_subscreen "Passo 2 — Formatar disco"
    echo ""

    printf "  %-12s %s\n" "Nome:"    "$SELECTED_DISK_NAME"
    printf "  %-12s /dev/%s\n" "Destino:" "$SELECTED_DISK"
    printf "  %-12s %s\n" "Volume:"  "$VOLUME_NAME"
    printf "  %-12s GPT + Mac OS Extended (Journaled)\n" "Esquema:"
    echo ""

    show_disk_volumes "$SELECTED_DISK"

    printf "  ${C_WARN}⚠  Todo o conteúdo do disco será APAGADO permanentemente.${C_RESET}\n"
    echo ""
    read "CONFIRM?${C_BOLD}Continuar? (s/n):${C_RESET} "
    CONFIRM="${CONFIRM:l}"

    if [[ "$CONFIRM" != "s" ]]; then
        return
    fi

    echo ""
    printf "  ${C_DIM}·${C_RESET} Verificando permissões...\n"
    if ! sudo -v; then
        printf "  ${C_WARN}Senha incorreta ou sudo negado.${C_RESET}\n"
        pause
        return
    fi

    echo ""
    spinner_start "Desmontando disco..."
    diskutil unmountDisk force "/dev/$SELECTED_DISK" > /dev/null 2>&1
    spinner_stop

    spinner_start "Formatando (GPT + Mac OS Extended)..."
    local format_ok=0
    if sudo diskutil eraseDisk "$DISK_FORMAT" "$VOLUME_NAME" GPT "/dev/$SELECTED_DISK" > /dev/null 2>&1; then
        format_ok=1
    fi
    spinner_stop

    if (( ! format_ok )); then
        printf "  ${C_WARN}Erro ao formatar o disco.${C_RESET}\n"
        pause
        return
    fi

    DISK_FORMATTED=1
    SELECTED_INSTALLER=""
    INSTALLER_CREATED=0
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

choose_installer() {
    print_subscreen "Passo 3 — Selecionar instalador macOS"

    typeset -a INSTALLERS
    INSTALLERS=()
    local app

    while IFS= read -r app; do
        [[ -n "$app" ]] && INSTALLERS+=("$app")
    done < <(find_macos_installers)

    if (( ${#INSTALLERS[@]} == 0 )); then
        echo ""
        printf "  ${C_WARN}Nenhum instalador encontrado.${C_RESET}\n"
        printf "  ${C_DIM}Baixe pelo gibMacOS ou coloque em /Applications.${C_RESET}\n"
        printf "  ${C_DIM}Ex.: Instalação do macOS Tahoe / Install macOS Sequoia${C_RESET}\n"
        auto_return 3
        return
    fi

    echo ""

    local -a _display
    _display=()
    local _i
    for _i in {1..${#INSTALLERS[@]}}; do
        _display+=("$(installer_label "${INSTALLERS[$_i]}")")
    done

    interactive_picker "${_display[@]}" || return

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

    local EFI_PART
    EFI_PART=$(efi_partition "$SELECTED_DISK")

    if [[ -z "$EFI_PART" ]]; then
        print_subscreen "EFI"
        echo ""
        printf "  ${C_WARN}Partição EFI não encontrada em /dev/$SELECTED_DISK${C_RESET}\n"
        pause
        return
    fi

    print_subscreen "Montar partição EFI"
    echo ""
    printf "  ${C_DIM}·${C_RESET} Montando /dev/$EFI_PART ...\n"
    if ! sudo diskutil mount "/dev/$EFI_PART"; then
        echo ""
        printf "  ${C_WARN}Erro ao montar EFI.${C_RESET}\n"
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

    print_subscreen "Passo 4 — Criar instalador bootável"
    echo ""

    printf "  %-14s %s\n" "Disco:"      "$SELECTED_DISK_NAME"
    printf "  %-14s %s\n" "Instalador:" "$(installer_label "$SELECTED_INSTALLER")"
    printf "  %-14s %s\n" "Volume:"     "$VOLUME_PATH"
    echo ""
    read "CONFIRM?${C_BOLD}Continuar? (s/n):${C_RESET} "
    CONFIRM="${CONFIRM:l}"

    if [[ "$CONFIRM" != "s" ]]; then
        return
    fi

    echo ""
    printf "  ${C_DIM}·${C_RESET} Verificando permissões...\n"
    if ! sudo -v; then
        printf "  ${C_WARN}Senha incorreta ou sudo negado.${C_RESET}\n"
        pause
        return
    fi

    printf "  ${C_DIM}·${C_RESET} Iniciando createinstallmedia...\n"
    printf "  ${C_DIM}  (pode levar 15–40 minutos — não feche o Terminal)${C_RESET}\n"
    echo ""

    local tmpfile
    tmpfile=$(mktemp /tmp/bootstick_XXXXXX)

    sudo "$CREATE_MEDIA" --volume "$VOLUME_PATH" --nointeraction > "$tmpfile" 2>&1 &
    local create_pid=$!

    local phase="Iniciando" prev_phase="" last_pct=0 latest_line pct

    draw_progress_bar 0 "$phase"

    while kill -0 "$create_pid" 2>/dev/null; do
        latest_line=$(tail -1 "$tmpfile" 2>/dev/null)
        prev_phase="$phase"

        echo "$latest_line" | grep -qiE "erasing"                      && phase="Apagando disco"
        echo "$latest_line" | grep -qiE "copying to disk|copying files" && phase="Copiando arquivos"
        echo "$latest_line" | grep -qiE "making.*bootable"             && phase="Tornando bootável"
        echo "$latest_line" | grep -qiE "copying boot"                 && phase="Copiando boot"
        echo "$latest_line" | grep -qiE "install media now"            && phase="Concluído"

        # Reseta progresso ao entrar numa nova fase
        [[ "$phase" != "$prev_phase" ]] && last_pct=0

        if echo "$latest_line" | grep -qE '[0-9]+%'; then
            pct=$(echo "$latest_line" | grep -oE '[0-9]+' | tail -1)
            if [[ -n "$pct" ]] && (( pct >= last_pct && pct <= 100 )); then
                last_pct=$pct
                draw_progress_bar "$last_pct" "$phase"
            fi
        fi

        sleep 0.5
    done

    wait "$create_pid"
    local exit_status=$?

    (( exit_status == 0 )) && draw_progress_bar 100 "Concluído"
    printf "\n"
    rm -f "$tmpfile"

    if (( exit_status != 0 )); then
        echo ""
        printf "  ${C_WARN}Erro ao criar instalador (código %d).${C_RESET}\n" "$exit_status"
        notify_macos "$APP_NAME" "Erro ao criar o instalador bootável."
        pause
        return
    fi

    # Verifica se o volume foi criado corretamente
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
# Modo dev (oculto — pressione "!" no menu principal)
# =========================================================

_demo_reset_state() {
    SELECTED_DISK=""
    SELECTED_DISK_NAME=""
    DISK_FORMATTED=0
    SELECTED_INSTALLER=""
    INSTALLER_CREATED=0
}

_demo_choose_disk() {
    print_subscreen "Passo 1 — Selecionar disco  ${C_WARN}[DEMO]${C_RESET}"
    echo ""
    printf "  ${C_DIM}%-14s %-22s %-10s${C_RESET}\n" "Disco" "Nome" "Tamanho"
    echo ""

    local -a demo_disks=(
        "$(printf '%-14s %-22s %s' '/dev/disk2' 'Samsung USB 3.1' '32.0 GB')"
        "$(printf '%-14s %-22s %s' '/dev/disk3' 'SanDisk Ultra'   '64.0 GB')"
    )

    interactive_picker "${demo_disks[@]}" || return

    SELECTED_DISK="disk2"
    SELECTED_DISK_NAME="Samsung USB 3.1"
}

_demo_format_disk() {
    print_subscreen "Passo 2 — Formatar disco  ${C_WARN}[DEMO]${C_RESET}"
    echo ""
    printf "  %-12s %s\n"  "Nome:"    "$SELECTED_DISK_NAME"
    printf "  %-12s %s\n"  "Destino:" "/dev/$SELECTED_DISK"
    printf "  %-12s %s\n"  "Volume:"  "$VOLUME_NAME"
    printf "  %-12s %s\n"  "Esquema:" "GPT + Mac OS Extended (Journaled)"
    echo ""
    printf "  ${C_DIM}Conteúdo atual:${C_RESET}\n\n"
    printf "  /dev/disk2 (external, physical):\n"
    printf "     #:  %-28s %-10s %s\n" "TYPE NAME" "SIZE" "IDENTIFIER"
    printf "     0:  %-28s %-10s %s\n" "GUID_partition_scheme" "*32.0 GB" "disk2"
    printf "     1:  %-28s %-10s %s\n" "EFI EFI" "209.7 MB" "disk2s1"
    printf "     2:  %-28s %-10s %s\n" "Microsoft Basic Data" "31.8 GB" "disk2s2"
    echo ""
    printf "  ${C_WARN}⚠  Todo o conteúdo do disco será APAGADO permanentemente.${C_RESET}\n"
    echo ""
    read "CONFIRM?${C_BOLD}Continuar? (s/n):${C_RESET} "
    [[ "${CONFIRM:l}" != "s" ]] && return

    echo ""
    spinner_start "Desmontando disco..."
    sleep 1.2
    spinner_stop

    spinner_start "Formatando (GPT + Mac OS Extended)..."
    sleep 2.0
    spinner_stop

    DISK_FORMATTED=1
    printf "  ${C_OK}✓ Formatação concluída.${C_RESET}\n"
    sleep 1
}

_demo_choose_installer() {
    print_subscreen "Passo 3 — Selecionar instalador macOS  ${C_WARN}[DEMO]${C_RESET}"
    echo ""

    local -a demo_installers=("Install macOS Sequoia" "Install macOS Sonoma")

    interactive_picker "${demo_installers[@]}" || return

    SELECTED_INSTALLER="/Applications/Install macOS Sequoia.app"
}

_demo_create_installer() {
    print_subscreen "Passo 4 — Criar instalador bootável  ${C_WARN}[DEMO]${C_RESET}"
    echo ""
    printf "  %-14s %s\n" "Disco:"      "$SELECTED_DISK_NAME"
    printf "  %-14s %s\n" "Instalador:" "Install macOS Sequoia"
    printf "  %-14s %s\n" "Volume:"     "/Volumes/$VOLUME_NAME"
    echo ""
    read "CONFIRM?${C_BOLD}Continuar? (s/n):${C_RESET} "
    [[ "${CONFIRM:l}" != "s" ]] && return

    echo ""
    printf "  ${C_DIM}·${C_RESET} Verificando permissões...\n"
    sleep 0.4
    printf "  ${C_DIM}·${C_RESET} Iniciando createinstallmedia...\n"
    printf "  ${C_DIM}  (pode levar 15–40 minutos — não feche o Terminal)${C_RESET}\n"
    echo ""

    local phase pct
    phase="Apagando disco"
    for pct in 0 10 20 30 40 50 60 70 80 90 100; do
        draw_progress_bar $pct "$phase"; sleep 0.15
    done

    phase="Copiando arquivos"
    for pct in 0 10 20 30 40 50 60 70 80 90 100; do
        draw_progress_bar $pct "$phase"; sleep 0.25
    done

    phase="Tornando bootável"
    draw_progress_bar 95 "$phase"; sleep 0.4
    draw_progress_bar 100 "Concluído";  sleep 0.3

    printf "\n"
    printf "  ${C_OK}✓ Instalador bootável criado com sucesso.${C_RESET}\n"
    printf "  ${C_DIM}  ↳ Notificação macOS disparada${C_RESET}\n"
    printf "  ${C_DIM}  ↳ Verificação de volume: OK${C_RESET}\n"
    printf "  ${C_DIM}  (simulado — nenhum disco foi modificado)${C_RESET}\n"
    INSTALLER_CREATED=1
    sleep 1
}

_demo_mount_efi() {
    print_subscreen "Montar partição EFI  ${C_WARN}[DEMO]${C_RESET}"
    echo ""
    printf "  ${C_DIM}·${C_RESET} Montando /dev/disk2s1 ...\n"
    sleep 0.8
    printf "  ${C_OK}✓ EFI aberta no Finder — copie sua pasta EFI do OpenCore.${C_RESET}\n"
    printf "  ${C_DIM}  (simulado — Finder não foi aberto)${C_RESET}\n"
    sleep 1
}

run_demo() {
    _demo_reset_state
    clear_screen
    print_banner "Modo dev  ${C_WARN}[DEMO — nenhum disco será modificado]${C_RESET}"
    echo ""
    spinner_start "Carregando modo desenvolvimento..."
    sleep 2
    spinner_stop

    _demo_choose_disk
    _demo_format_disk
    _demo_choose_installer
    _demo_create_installer
    _demo_mount_efi

    echo ""
    printf "  ${C_OK}${C_BOLD}Fluxo completo simulado.${C_RESET}\n"
    pause
    _demo_reset_state
}

if [[ "$(uname)" != "Darwin" ]]; then
    print_banner "Erro"
    echo ""
    printf "  ${C_WARN}Este script só funciona no macOS.${C_RESET}\n"
    exit 1
fi

init_terminal

while true; do
    show_menu  # bloqueia até o usuário selecionar; resultado em MENU_RESULT

    case "$MENU_RESULT" in
        d) choose_disk ;;
        f) [[ -n "$SELECTED_DISK" ]] && format_disk ;;
        i) [[ -n "$SELECTED_DISK" ]] && choose_installer ;;
        b) [[ -n "$SELECTED_DISK" ]] && [[ -n "$SELECTED_INSTALLER" ]] && (( ! INSTALLER_CREATED )) && create_installer ;;
        e) (( INSTALLER_CREATED )) && mount_efi ;;
        '!') run_demo ;;
        h) clear_screen; print_banner "Ajuda e documentação"; print_about_full ;;
        q) print_goodbye ;;
    esac
done
