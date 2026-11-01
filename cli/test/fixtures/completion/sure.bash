# bash completion for sure
_sure_completion() {
  local cur
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"

  case "${cur}" in
    -*)
      COMPREPLY=( $(compgen -W "--profile --server --ca-bundle --insecure --json --table --csv --ndjson --fields --color --no-color --quiet --verbose --help --version" -- "${cur}") )
      return 0
      ;;
  esac

  if [ "$COMP_CWORD" -eq 1 ]; then
    COMPREPLY=( $(compgen -W "version help auth api doctor completion" -- "${cur}") )
    return 0
  fi

  case "${COMP_WORDS[1]}" in
    auth)
      if [ "$COMP_CWORD" -eq 2 ]; then
        COMPREPLY=( $(compgen -W "login logout status" -- "${cur}") )
      fi
      ;;
  esac
}
complete -F _sure_completion sure
