#!/bin/sh

# Author: WüSpace e. V. 2023 (c)

# Based on: https://github.com/npryce/adr-tools
#
# ADR Tools - command line tools to maintain a project's architecture decision records
#
# Copyright (C) 2016 Nat Pryce
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# Content that this tool adds to your project is under the
# [Creative Commons Attribution 4.0 (CC BY 4.0)](https://creativecommons.org/licenses/by/4.0/) licence.

##
## variables
##

version="0.1.0"
script_dir="$(dirname "$(realpath "$0")")"
script_name="$(basename "$(realpath "$0")")"

docs_dir="${script_dir}/docs"
adrs_dir="${docs_dir}/adrs"
readme_path="${docs_dir}/README.md"
template_path="${adrs_dir}/__template__.md"

help_general="
Usage: ${script_name} <command> [options]

Commands:
    new       creates a new ADR
    accept    accepts an existing ADR
    link      creates a link between two ADRs

Options:
    --help, -h      shows this help
    --version, -V   shows the current version of the tool

Run '${script_name} <command> --help' to show command specific help.
"

help_new="
Creates a new ADR with the specified title.
This ADR can optionally supersede an existing ADR by specifing the ADR number.

Usage: ${script_name} new [options] <title...>

Options:
    --supersedes, -s <adr-number>    Specifies the ADR number that gets superseded by the new ADR.
                                     Additionally, a link to the new ADR gets added.
    --help, -h                       shows this help
    --version, -V                    shows the current version of the tool

Run '${script_name} --help' to show the general help.
"

help_accept="
Accepts an existing ADR.

Usage: ${script_name} accept [options] <adr-number>

Options:
    --help, -h      shows this help
    --version, -V   shows the current version of the tool

Run '${script_name} --help' to show the general help.
"

help_link="
Creates a link between two ADRs.
Each link contains a prefix and a target link to the other ADR.
In the following schema:
    - ADR1 <adr1-prefix> ADR2 (e.g. ADR1 Amends ADR2)
    - ADR2 <adr2-prefix> ADR1 (e.g. ADR2 Amended by ADR1)

Usage: ${script_name} link [options] <adr1-number> <adr1-prefix> <adr2-number> <adr2-prefix>

Options:
    --help, -h      shows this help
    --version, -V   shows the current version of the tool

Run '${script_name} --help' to show the general help.
"

##
## utility functions
##

print_help_general() {
    printf '%s\n' "$help_general"
}

print_help_new() {
    printf '%s\n' "$help_new"
}

print_help_accept() {
    printf '%s\n' "$help_accept"
}

print_help_link() {
    printf '%s\n' "$help_link"
}

print_version() {
    printf '%s %s\n' "$script_name" "$version"
}

print_unknown() {
    printf 'Unknown command: %s\n' "$1"
}

get_last_rev() {
    ls "$adrs_dir" | grep -Eo '^[0-9]+' | sed -e 's/^0*//' | sort -rn | head -1
}

get_adr_path() {
    rev_num="$1"
    rev_num="$(printf '%04d' "$rev_num")"

    printf '%s\n' "${adrs_dir}/${rev_num}"* | head -1
}

get_adr_title() {
    adr_path="$1"

    head -1 "$adr_path" | cut -c 3-
}

change_state() {
    adr_path="$1"
    state="$2"

    awk -v state="$state" '
        BEGIN {
            in_status_section=0
        }

        /^\S+/ {
            if (in_status_section) {
                print state
                in_status_section=0
                next
            }
        }

        /^## Status$/ {
            in_status_section=1
        }

        { print }
    ' "$adr_path" > "$adr_path.tmp"
    mv --force "$adr_path.tmp" "$adr_path"
}

add_link() {
    adr_path="$1"
    prefix_text="$2"
    linked_adr_name="$3"
    linked_adr_title="$(get_adr_title "${adrs_dir}/${linked_adr_name}")"

    awk -v prefix_text="$prefix_text" -v link_path="$linked_adr_name" -v link_title="$linked_adr_title" '
        BEGIN {
            in_status_section=0
        }

        /^##/ {
            if (in_status_section) {
                print prefix_text " [" link_title "](" link_path ")"
                print ""
            }
            in_status_section=0
        }

        /^## Status$/ {
            in_status_section=1
        }

        { print }
    ' "${adr_path}" > "${adr_path}.tmp"

    mv --force "${adr_path}.tmp" "${adr_path}"
}

command_new() {
    if [ "$#" -lt 1 ]; then
        print_help_new
        exit 1
    fi

    # parse cli options
    supersedes=""
    title=""
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --help|-h) print_help_new; exit 0;;
            --version|-V) print_version; exit 0;;
            --supersedes|-s)
                shift
                if [ "$#" -lt 1 ]; then
                    printf '\-\-supersedes required an argument.\n'
                    exit 1
                fi

                supersedes="$1"
                ;;
            *) break 2;;
        esac

        shift
    done

    if [ "$#" -lt 1 ]; then
        printf 'A title is required.\n'
        exit 1
    fi

    # gather information
    title="$*"
    last_rev="$(get_last_rev)"
    new_rev=$(( last_rev + 1 ))
    nullifed_new_rev="$(printf '%04d' "$new_rev")"
    slug="$(printf '%s' "$title" |\
            sed -e 's/[^[:alnum:]]*$//' -e 's/^[^[:alnum:]]*//' |\
            tr -cs '[:alnum:]' - |\
            tr '[:upper:]' '[:lower:]')"
    
    file_name="${nullifed_new_rev}-${slug}.md"
    file_path="${adrs_dir}/${file_name}"
    date="$(date +%Y-%m-%d)"

    # generate ADR from template
    sed -e "s/%%NUMBER%%/${nullifed_new_rev}/" \
        -e "s/%%TITLE%%/${title}/" \
        -e "s/%%DATE%%/${date}/" \
        "$template_path" > "$file_path"

    # add superseded message
    if [ -n "$supersedes" ]; then
        superseded_adr_path="$(get_adr_path "$supersedes")"
        superseded_adr_file_name="$(basename "$superseded_adr_path")"
        superseded_adr_title="$(get_adr_title "$superseded_adr_path")"

        change_state "$superseded_adr_path" "Deprecated"
        add_link "$superseded_adr_path" "Superseded by" "$file_name"
        add_link "$file_path" "Supersedes" "$superseded_adr_file_name"
        printf 'Supersedes %s\n' "$superseded_adr_title"
    fi

    # add new ADR to README
    awk -v nullified_rev="$nullifed_new_rev" -v adr_title="$title" -v file_name="$file_name" '
        /^<!-- INSERTION_MARK_DO_NO_DELETE -->$/ {
            print "- [ADR-" nullified_rev ": " adr_title "](./adrs/" file_name ")"
            print "<!-- INSERTION_MARK_DO_NO_DELETE -->"
            next
        }
        { print }
    ' "$readme_path" > "$readme_path.tmp"
    mv --force "$readme_path.tmp" "$readme_path"

    printf 'Created %s\n' "$(get_adr_title "$file_path")"
    exit 0
}

command_accept() {
    if [ "$#" -lt 1 ]; then
        print_help_accept
        exit 1
    fi

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --help|-h) print_help_accept; exit 0;;
            --version|-V) print_version; exit 0;;
            *) break 2;;
        esac

        shift
    done

    if [ "$#" -lt 1 ]; then
        printf 'ADR number required.\n'
        exit 1
    fi

    adr_number="$1"
    adr_path="$(get_adr_path "$adr_number")"
    adr_title="$(get_adr_title "$adr_path")"

    change_state "$adr_path" "Accepted"
    
    printf 'Accepted %s\n' "$adr_title"
    exit 0
}

command_link() {
    if [ "$#" -lt 1 ]; then
        print_help_link
        exit 1
    fi

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --help|-h) print_help_link; exit 0;;
            --version|-V) print_version; exit 0;;
            *) break 2;;
        esac

        shift
    done

    if [ "$#" -lt 4 ]; then
        printf 'The following arguments are required: <adr1-number> <adr1-prefix> <adr2-number> <adr2-prefix>.\n'
        exit 1
    fi

    adr1_number="$1"
    adr1_path="$(get_adr_path "$adr1_number")"
    adr1_title="$(get_adr_title "$adr1_path")"
    adr1_prefix="$2"
    adr2_number="$3"
    adr2_path="$(get_adr_path "$adr2_number")"
    adr2_title="$(get_adr_title "$adr2_path")"
    adr2_prefix="$4"

    add_link "$adr1_path" "$adr1_prefix" "$(basename "$adr2_path")"
    add_link "$adr2_path" "$adr2_prefix" "$(basename "$adr1_path")"

    printf '%s %s %s\n' "$adr1_title" "$adr1_prefix" "$adr2_title"
    printf '%s %s %s\n' "$adr2_title" "$adr2_prefix" "$adr1_title"
    exit 0
}

##
## main
##

if [ "$#" -lt 1 ]; then
    print_help_general
    exit 1
fi

command="$1"
shift

case "$command" in
    --help|-h) print_help_general; exit 0;;
    --version|-V) print_version; exit 0;;
    new) command_new "$@";;
    accept) command_accept "$@";;
    link) command_link "$@";;
    *) print_unknown "$command"; exit 1;;
esac
