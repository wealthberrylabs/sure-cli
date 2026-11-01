complete -c sure -f
complete -c sure -n '__fish_use_subcommand' -a 'version' -d 'Print the CLI version'
complete -c sure -n '__fish_use_subcommand' -a 'help' -d 'Describe available commands or one specific command'
complete -c sure -n '__fish_use_subcommand' -a 'auth'
complete -c sure -n '__fish_use_subcommand' -a 'api' -d 'Call a Sure /api/v1 endpoint'
complete -c sure -n '__fish_use_subcommand' -a 'doctor' -d 'Check configuration, credentials, and connectivity'
complete -c sure -n '__fish_use_subcommand' -a 'completion' -d 'Generate shell completion from the command catalog'
complete -c sure -n '__fish_seen_subcommand_from auth' -a 'login'
complete -c sure -n '__fish_seen_subcommand_from auth' -a 'logout'
complete -c sure -n '__fish_seen_subcommand_from auth' -a 'status'
complete -c sure -l profile
complete -c sure -l server
complete -c sure -l ca-bundle
complete -c sure -l insecure
complete -c sure -l json
complete -c sure -l table
complete -c sure -l csv
complete -c sure -l ndjson
complete -c sure -l fields
complete -c sure -l color
complete -c sure -l no-color
complete -c sure -l quiet
complete -c sure -l verbose
complete -c sure -l help
complete -c sure -l version
