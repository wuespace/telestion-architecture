#!/bin/sh

set +x

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

Options:
    --help, -h      shows this help
    --version, -V   shows the current version of the tool

Run '${script_name} <command> --help' to show command specific help.
"

help_new="
Usage: ${script_name} new [options] <title...>

Options:
    --supersedes, -s <adr-version>   Specifies the ADR number that gets superseded by the new ADR.
                                     Additionally, a link to the new ADR gets added.

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

supersede_adr() {
    adr_path="$1"
    replacement_adr_name="$2"
    replacement_adr_title="$(get_adr_title "${adrs_dir}/${replacement_adr_name}")"

    awk -v link_path="$replacement_adr_name" -v link_title="$replacement_adr_title" '
        BEGIN {
            in_status_section=0
            print_superseded=0
        }

        /^##/ {
            in_status_section=0
        }

        /^## Status$/ {
            in_status_section=1
            print_superseded=1
        }

        {
            if (in_status_section) {
                if (print_superseded) {
                    print "## Status"
                    print ""
                    print "Superseded by [" link_title "](" link_path ")"
                    print ""
                    print_superseded=0
                }
            } else {
                print
            }
        }
    ' "${adr_path}" > "${adr_path}.tmp"

    mv --force "${adr_path}.tmp" "${adr_path}"
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
    *) print_unknown "$command"; exit 1;;
esac
