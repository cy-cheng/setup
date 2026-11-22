function rm-to-trash --description 'Move files to Trash, then prompt to prune Trash if it is too large'
    set -l files
    set -l force 0
    set -l stop_opts 0

    for arg in $argv
        if test $stop_opts -eq 1
            set -a files $arg
            continue
        end

        switch $arg
            case --
                set stop_opts 1

            case --force
                set force 1

            case --recursive --dir --interactive
                # accepted for rm muscle memory; not needed for trashing

            case '--*'
                echo "rm-to-trash: unsupported rm option: $arg" >&2
                echo "Use 'command rm ...' for real rm." >&2
                return 64

            case '-*'
                set -l chars (string split '' (string replace -r '^-+' '' -- $arg))

                for c in $chars
                    switch $c
                        case f
                            set force 1
                        case r R d i I
                            # accepted for rm muscle memory
                        case '*'
                            echo "rm-to-trash: unsupported rm option: -$c" >&2
                            echo "Use 'command rm ...' for real rm." >&2
                            return 64
                    end
                end

            case '*'
                set -a files $arg
        end
    end

    if test (count $files) -eq 0
        if test $force -eq 1
            return 0
        end

        echo "rm-to-trash: missing operand" >&2
        return 1
    end

    if test $force -eq 1
        command gio trash -f -- $files
    else
        command gio trash -- $files
    end

    set -l trash_status $status

    if test $trash_status -eq 0
        command trash-prune-prompt --max 1G --top 10
    end

    return $trash_status
end
