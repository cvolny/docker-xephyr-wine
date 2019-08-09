#!/bin/bash -x

function init()
{
    CMD=$( basename $0 )
    DIR=$( dirname $( realpath $0 ) )
    
    IMAGE="volny/docker-wine:latest"
    IMAGEDEF="$DIR"
    NAME="$CMD.$$"
    REBUILD=false
    CLEANUP=false
    DAEMONIZE=false
    SCREEN_SIZE=1024x768x24
    PREFIX="$HOME/.wine"

    set -- $( getopt -o n:rcs:p:dh --long name:,rebuild,cleanup,screen:,prefix:,daemonize,help --unquoted --name "$CMD" -- "$@" )
    while true; do
        case "$1" in
            -n | --name)
                NAME="$2"
                shift
                shift;;
            -s | --screen )
                SCREEN="$2"
                shift
                shift;;
            -p | --prefix )
                PREFIX="$2"
                shift
                shift;;
            -r | --rebuild )
                REBUILD=true;
                shift;;
            -c | --cleanup )
                CLEANUP=true;
                shift;;
            -d | --daemonize )
                DAEMONIZE=true
                shift;;
            -h | --help | ? )
                cat <<-EOF
Usage:
    $CMD [ -n | --name TEXT ] [ -r | --rebuild ] [ -c | --cleanup ] [ -s | --screen WIDTHxHEIGHTxDEPTH ] [ -- ] COMMAND
    $CMD [ -h | --help ]
EOF
                exit;;
            -- )
                shift
                break;;
            * )
                break;;
        esac
    done
    COMMAND="wine $@"

    CACHEDIR=$( mktemp -d )
    XTMP="/tmp/.X11-unix"
    COOKIE_SERVER="${CACHEDIR}/Xcookie.server"
    COOKIE_CLIENT="${CACHEDIR}/Xcookie.client"
}


function debug()
{
    echo "$@" >&2
}


function nextdisplay()
{
    local num
    for (( num=1 ; num <= 100; num++ )); do
        [[ -e "${XTMP}/X${num}" ]] || break
    done
    echo -n "${num}"
}


function rebuild()
{
    debug "rebuild() $REBUILD"
    if [[ "$REBUILD" == true ]]; then
        docker build --no-cache --tag "$IMAGE" "$IMAGEDEF"
    fi
}


function execute()
{
    local display=$( nextdisplay )
    local socket="${XTMP}/X${display}"
    local pid
    local envfile=$( mktemp )

    cat <<-EOF > "$envfile"
DISPLAY=:${display}
XAUTHORITY=${COOKIE_CLIENT}
WINEPREFIX=${PREFIX}
EOF

    if [[ ! -d "$PREFIX" ]]; then
        debug "New wine-prefix '$PREFIX' specified, mkdir-p-ing it..."
        mkdir -p "$PREFIX"
    fi

    debug "Run Xephyr..."
    Xephyr ":${display}" \
        -auth "$COOKIE_SERVER" \
        -extension MIT-SHM \
        -nolisten tcp \
        -screen $SCREEN_SIZE \
        -retro &
    pid=$!

    debug "Xephyr pid = $pid; Run docker..."
    docker run -it \
        --name "$NAME" \
        --user $( id -u ):$( id -g ) \
        --env-file=$envfile \
        --volume $COOKIE_CLIENT:$COOKIE_CLIENT \
        --volume /etc/passwd:/etc/passwd:ro \
        --volume $PREFIX:$PREFIX:z \
        --volume $socket:$socket:rw \
        --group-add audio \
        --cap-drop=ALL \
        --security-opt=no-new-privileges \
        "$IMAGE" \
        $COMMAND

    rm -rf "$envfile"

    if [[ "$DAEMONIZE" == true ]]; then
        debug "Wait for Xephyr pid $pid..."
        wait $pid
    else
        kill $pid
    fi
}


function cleanup()
{
    debug "cleanup() $CLEANUP"
    if [[ "$CLEANUP" == true ]]; then
        docker container rm --force "$NAME"
    fi
    rm -rf "$CACHEDIR"
}


function main()
{
    trap cleanup EXIT
    rebuild
    execute
}


init "$@"
main
