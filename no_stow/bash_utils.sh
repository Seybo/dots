do_times() {
    count=$1
    shift

    for i in $(seq "$count"); do
        echo "========== Running iteration: $i"
        eval "$@"
    done
}
