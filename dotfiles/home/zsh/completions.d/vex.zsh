_vex() {
    local curcontext="$curcontext" state line
    typeset -A opt_args
    local vpath vbinpath
    local pythons

    pythons=( ${commands[(I)python[0-9].[0-9]|pypy|jython]} )
    _arguments -A "-*" \
        '(: -)'{-h,--help}'[print help information]' \
        '(: -)--shell-config[print config for the specified shell]:shell:( bash zsh )' \
        '--cwd[set working directory for subprocess]:directory:_files -/' \
        '--config[read config file]:file:_files -g *(.r)' \
        '(-m --make)'{-m,--make}'[make the named virtualenv before running command]' \
            '--python[use the named python when making virtualenv]:python:(${pythons})' \
            '--site-packages[made virtualenv allows access to site packages]' \
            '--always-copy[copy files instead of making symlinks]' \
        '(-r --remove)'{-r,--remove}'[remove the named virtualenv after running command]' \
        '(1)--path[set path to virtualenv]:virtualenv directory:_path_files -/' \
        '(--path)1:virtualenv:_path_files -/ -W "/gpfs/gpfs0/groups/chowdhury/peifeng/.local/venvs"' \
        '2:command:->command_state' \
        '*::arguments: _normal'

    case $state in
        command_state)
            vpath="/gpfs/gpfs0/groups/chowdhury/peifeng/.local/venvs/${line[1]}"
            vbinpath="$vpath/bin"
            if [ "$vbinpath" != "/" ] && [ -d "$vbinpath" ]; then
                _alternative \
                    'virtualenvcommand:command in virtualenv:_path_files -W "$vbinpath" -g "*(x-.)"' \
                    '::_command_names -e'
            fi
            ;;
        *)
    esac
}

compdef _vex vex
