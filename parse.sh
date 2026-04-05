#!/usr/bin/env bash

# ==========================
# Konfiguration
# ==========================
VALID_SHORT=( -a -b -c )
VALID_LONG=( --test --name --flag )
FLAGS=( -a --flag )       # Flags ohne Wert
OPTIONS=( --name --test ) # Optionen mit Wert

# ==========================
# Vordefinierte Ergebnisvariablen
# ==========================
MYFLAG=""         # Ergebnis für -a
ANOTHER_FLAG=""   # Ergebnis für --flag
MYVAR=""          # Ergebnis für --name
NAME=""           # automatische Variable für --name, wenn keine eigene zugewiesen
TEST=""           # Ergebnis für --test

# ==========================
# Hilfe
# ==========================
show_help() {
    cat <<EOF
Verwendung:
  $0 [OPTIONEN]

Flags (kein Wert erlaubt):
  -a+, -a++, -a-, -a--
  --flag+, --flag--

Optionen mit Wert:
  --name=value oder --name value
  --test=value oder --test value

Alle Ergebnisvariablen müssen im Code vordefiniert werden.

--help                        Diese Hilfe anzeigen
EOF
    exit 0
}

# ==========================
# Hilfsfunktionen
# ==========================
is_valid_param() {
    local key="$1"
    for v in "${VALID_SHORT[@]}" "${VALID_LONG[@]}"; do
        [[ "$v" == "$key" ]] && return 0
    done
    return 1
}

is_flag() {
    local key="$1"
    for v in "${FLAGS[@]}"; do
        [[ "$v" == "$key" ]] && return 0
    done
    return 1
}

is_option() {
    local key="$1"
    for v in "${OPTIONS[@]}"; do
        [[ "$v" == "$key" ]] && return 0
    done
    return 1
}

# ==========================
# Parser
# ==========================
parse_arg() {
    local arg="$1"
    local next="$2"

    [[ "$arg" == "--help" ]] && show_help

    if [[ "$arg" =~ ^(-[a-z]|--[a-z]+)(\+\+|--|\+|-)?(=(.*))?$ ]]; then
        local key="${BASH_REMATCH[1]}"
        local suffix="${BASH_REMATCH[2]}"
        local eq_value="${BASH_REMATCH[4]}"
        local result_var="$next"
        local shift_flag=0

        # Validierung
        if ! is_valid_param "$key"; then
            echo "Fehler: Ungültiger Parameter: $key"
            exit 1
        fi

        # --------------------------
        # Flags
        # --------------------------
        if is_flag "$key"; then
            if [[ -z "$suffix" ]]; then
                echo "Fehler: Flag $key benötigt Suffix (+/++/-/--)"
                exit 1
            fi
            case "$suffix" in
                +|++) flag=true ;;
                -|--) flag=false ;;
                *) echo "Fehler: Ungültiges Suffix für Flag $key: $suffix"; exit 1 ;;
            esac

            # Wenn Ergebnisvariable nicht vordefiniert, Fehler
            if [[ -z "$result_var" || -z "${!result_var+x}" ]]; then
                echo "Fehler: Ergebnisvariable für Flag $key ist nicht vordefiniert!"
                exit 1
            fi

            [[ -z "${!result_var}" ]] && eval "$result_var=$flag"
            [[ -n "$next" && ! "$next" =~ ^- ]] && shift_flag=1

        # --------------------------
        # Optionen mit Wert
        # --------------------------
        elif is_option "$key"; then
            if [[ -n "$suffix" ]]; then
                echo "Fehler: Option $key darf keine +/++/-/-- Endung haben!"
                exit 1
            fi

            # Freie Ergebnisvariable nach Leerzeichen
            if [[ -z "$result_var" || -z "${!result_var+x}" ]]; then
                # automatische Variable aus Key
                result_var="${key//-/}"
                result_var="${result_var^^}"
                # Prüfen, ob vordefiniert
                if [[ -z "${!result_var+x}" ]]; then
                    echo "Fehler: Ergebnisvariable für Option $key ist nicht vordefiniert!"
                    exit 1
                fi
            fi

            # Wert bestimmen
            local value=""
            if [[ -n "$eq_value" ]]; then
                value="$eq_value"
            elif [[ -n "$next" && ! "$next" =~ ^- ]]; then
                value="$next"
            fi

            if [[ -n "$value" && -z "${!result_var}" ]]; then
                eval "$result_var='$value'"
            fi

            [[ -n "$next" && ! "$next" =~ ^- ]] && shift_flag=1
        fi

        return $shift_flag
    else
        echo "Fehler: Ungültiges Format: $arg"
        exit 1
    fi
}

# ==========================
# Hauptloop
# ==========================
i=0
args=("$@")
while [[ $i -lt $# ]]; do
    arg="${args[$i]}"
    next="${args[$((i+1))]}"

    parse_arg "$arg" "$next"
    shift_flag=$?

    if [[ $shift_flag -eq 1 ]]; then
        ((i++))
    fi
    ((i++))
done

# ==========================
# Ausgabe: nur Variablen, die Werte erhalten haben
# ==========================
for var in MYFLAG ANOTHER_FLAG MYVAR NAME TEST; do
    [[ -n "${!var}" ]] && echo "$var = ${!var}"
done
