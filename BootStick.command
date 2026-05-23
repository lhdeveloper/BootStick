#!/bin/zsh

# Limpa scrollback + tela (remove linha "/path/BootStick.command ; exit;" do Terminal)
[[ -t 1 ]] && printf '\033[3J\033[2J\033[H'

# =========================================================
# BootStick — Hackintosh bootable USB assistant
# =========================================================

setopt NO_NOMATCH 2>/dev/null

APP_NAME="BootStick"
APP_TAGLINE="Assistente de mídia bootável para Hackintosh"
SCRIPT_VERSION="1.4.0"
SCRIPT_BUILD="2026.05.21"
VOLUME_NAME="Install macOS"
DISK_FORMAT="JHFS+"

SELECTED_DISK=""
SELECTED_DISK_NAME=""
DISK_FORMATTED=0
SELECTED_INSTALLER=""
INSTALLER_CREATED=0

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

disk_has_install_volume() {
    local disk="$1"
    volume_on_disk "$disk"
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

    (( DISK_FORMATTED )) && printf "  %-12s ${C_OK}✓ Mac OS Extended${C_RESET}\n" "Formato:"
    (( INSTALLER_CREATED )) && printf "  %-12s ${C_OK}✓ criado${C_RESET}\n" "Bootável:"

    echo ""
    if [[ -z "$SELECTED_DISK" ]]; then
        printf "  ${C_ACCENT}[D]${C_RESET}  Selecionar disco USB/SSD\n"
    elif [[ -z "$SELECTED_INSTALLER" ]]; then
        (( ! DISK_FORMATTED )) && printf "  ${C_ACCENT}[F]${C_RESET}  Formatar disco (apaga tudo)\n"
        printf "  ${C_ACCENT}[I]${C_RESET}  Selecionar instalador macOS\n"
    elif (( ! INSTALLER_CREATED )); then
        printf "  ${C_ACCENT}[B]${C_RESET}  Criar instalador bootável no pendrive\n"
        (( ! DISK_FORMATTED )) && printf "  ${C_ACCENT}[F]${C_RESET}  Formatar disco (necessário antes de criar)\n"
        printf "  ${C_DIM}[I]${C_RESET}  Trocar instalador macOS\n"
    else
        printf "  ${C_ACCENT}[E]${C_RESET}  Montar e abrir EFI (OpenCore)\n"
        printf "  ${C_DIM}[F]${C_RESET}  Reformatar disco (opcional)\n"
    fi

    printf "  ${C_DIM}[H]${C_RESET}  Ajuda / sobre\n"
    printf "  ${C_DIM}[Q]${C_RESET}  Sair\n"
    echo ""
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

print_disk_table() {
    local i DISK NAME SIZE PROTOCOL LETTER
    local -a rows

    rows=()

    for i in {1..${#DISKS[@]}}; do
        DISK="${DISKS[$i]}"
        IFS='|' read -r NAME SIZE PROTOCOL <<< "$(disk_details "$DISK")"
        LETTER="${MENU_LETTERS[$i]}"
        rows+=("$LETTER|$DISK|$NAME|$SIZE|$PROTOCOL")
    done

    printf "  ${C_DIM}%-14s %-22s %-10s${C_RESET}\n" "Disco" "Nome" "Tamanho"
    echo ""

    for row in "${rows[@]}"; do
        IFS='|' read -r LETTER DISK NAME SIZE PROTOCOL <<< "$row"
        printf "  ${C_ACCENT}[%-1s]${C_RESET}  %-14s %-22s ${C_DIM}%s${C_RESET}\n" "$LETTER" "/dev/$DISK" "$NAME" "$SIZE"
    done

    echo ""
    printf "  ${C_DIM}[Q]${C_RESET}  Voltar\n"
}

disk_index_from_letter() {
    local letter="${1:l}"
    local i

    for i in {1..${#DISKS[@]}}; do
        [[ "${MENU_LETTERS[$i]:l}" == "$letter" ]] && echo "$i" && return 0
    done
    return 1
}

choose_disk() {
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
        pause
        return
    fi

    echo ""
    print_disk_table
    echo ""
    read "OPTION?${C_BOLD}Escolha uma letra:${C_RESET} "
    OPTION="${OPTION:l}"

    if [[ "$OPTION" == "q" ]]; then
        return
    fi

    local IDX
    IDX=$(disk_index_from_letter "$OPTION") || {
        echo ""
        echo "Opção inválida."
        sleep 1
        return
    }

    SELECTED_DISK="${DISKS[$IDX]}"
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

    printf "  %-12s %s\n" "Nome:" "$SELECTED_DISK_NAME"
    printf "  %-12s /dev/%s\n" "Destino:" "$SELECTED_DISK"
    printf "  %-12s %s\n" "Volume:" "$VOLUME_NAME"
    printf "  %-12s GPT + Mac OS Extended (Journaled)\n" "Esquema:"
    echo ""
    printf "  ${C_WARN}⚠  Todo o conteúdo do disco será APAGADO permanentemente.${C_RESET}\n"
    echo ""
    read "CONFIRM?${C_BOLD}Continuar? (s/n):${C_RESET} "
    CONFIRM="${CONFIRM:l}"

    if [[ "$CONFIRM" != "s" ]]; then
        return
    fi

    echo ""
    printf "  ${C_DIM}·${C_RESET} Desmontando disco...\n"
    diskutil unmountDisk force "/dev/$SELECTED_DISK" 2>/dev/null

    printf "  ${C_DIM}·${C_RESET} Formatando (GPT + Mac OS Extended)...\n"
    echo ""

    if ! sudo diskutil eraseDisk "$DISK_FORMAT" "$VOLUME_NAME" GPT "/dev/$SELECTED_DISK"; then
        echo ""
        printf "  ${C_WARN}Erro ao formatar o disco.${C_RESET}\n"
        pause
        return
    fi

    DISK_FORMATTED=1
    SELECTED_INSTALLER=""
    INSTALLER_CREATED=0
    SELECTED_DISK_NAME="$(disk_media_name "$SELECTED_DISK")"
    echo ""
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

print_installer_table() {
    local i app LETTER label
    local -a rows

    rows=()

    for i in {1..${#INSTALLERS[@]}}; do
        app="${INSTALLERS[$i]}"
        LETTER="${MENU_LETTERS[$i]}"
        label="$(installer_label "$app")"
        rows+=("$LETTER|$label")
    done

    for row in "${rows[@]}"; do
        IFS='|' read -r LETTER app <<< "$row"
        printf "  ${C_ACCENT}[%-1s]${C_RESET}  %s\n" "$LETTER" "$app"
    done

    echo ""
    printf "  ${C_DIM}[Q]${C_RESET}  Voltar\n"
}

installer_index_from_letter() {
    local letter="${1:l}"
    local i

    for i in {1..${#INSTALLERS[@]}}; do
        [[ "${MENU_LETTERS[$i]:l}" == "$letter" ]] && echo "$i" && return 0
    done
    return 1
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
        pause
        return
    fi

    echo ""
    print_installer_table
    echo ""
    read "OPTION?${C_BOLD}Escolha uma letra:${C_RESET} "
    OPTION="${OPTION:l}"

    if [[ "$OPTION" == "q" ]]; then
        return
    fi

    local IDX
    IDX=$(installer_index_from_letter "$OPTION") || {
        echo ""
        echo "Opção inválida."
        sleep 1
        return
    }

    SELECTED_INSTALLER="${INSTALLERS[$IDX]}"
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

    printf "  %-14s %s\n" "Disco:" "$SELECTED_DISK_NAME"
    printf "  %-14s %s\n" "Instalador:" "$(installer_label "$SELECTED_INSTALLER")"
    printf "  %-14s %s\n" "Volume:" "$VOLUME_PATH"
    echo ""
    read "CONFIRM?${C_BOLD}Continuar? (s/n):${C_RESET} "
    CONFIRM="${CONFIRM:l}"

    if [[ "$CONFIRM" != "s" ]]; then
        return
    fi

    echo ""
    printf "  ${C_DIM}·${C_RESET} Executando createinstallmedia...\n"
    printf "  ${C_DIM}  (pode levar 15–40 minutos, não feche o Terminal)${C_RESET}\n"
    echo ""

    if ! sudo "$CREATE_MEDIA" --volume "$VOLUME_PATH" --nointeraction; then
        echo ""
        printf "  ${C_WARN}Erro ao criar instalador.${C_RESET}\n"
        pause
        return
    fi

    INSTALLER_CREATED=1
    echo ""
    printf "  ${C_OK}✓ Instalador bootável criado com sucesso.${C_RESET}\n"
    mount_efi
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
    read "MENU_OPTION?${C_BOLD}Escolha:${C_RESET} "
    MENU_OPTION="${MENU_OPTION:l}"

    case "$MENU_OPTION" in
        d)
            [[ -z "$SELECTED_DISK" ]] && choose_disk
            ;;
        f)
            [[ -n "$SELECTED_DISK" ]] && format_disk
            ;;
        i)
            [[ -n "$SELECTED_DISK" ]] && choose_installer
            ;;
        b)
            [[ -n "$SELECTED_DISK" ]] && [[ -n "$SELECTED_INSTALLER" ]] && (( ! INSTALLER_CREATED )) && create_installer
            ;;
        e)
            (( INSTALLER_CREATED )) && mount_efi
            ;;
        h)
            clear_screen
            print_banner "Ajuda e documentação"
            print_about_full
            ;;
        q)
            print_goodbye
            ;;
        *)
            ;;
    esac
done
