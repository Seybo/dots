do_times() {
    count=$1
    shift

    for i in $(seq "$count"); do
        echo "========== Running iteration: $i"
        eval "$@"
    done
}

# moves N first files to selected dir
move_n_files() {
  local -i n=$1
  local dst=$2

  if (( n < 1 )); then
    echo "Usage: move_n_files <number_of_files> <destination_folder>"
    return 1
  fi

  mkdir -p -- "$dst"

  # Build an array of **regular files only** (no directories).
  # The glob qualifier `(.)` means “plain files,” and `.N` means “sort names”:
  local files=( *(.) )

  # If you want to include hidden files as well, use: files=( *(D.) )

  # “numfiles” is how many we actually have:
  local -i numfiles=${#files}

  if (( numfiles == 0 )); then
    echo "No files to move."
    return 0
  fi

  # Cap n at the number of files we actually have:
  if (( n > numfiles )); then
    n=$numfiles
  fi

  # Now move the first n items one by one:
  for (( i = 1; i <= n; i++ )); do
    mv -- "${files[i]}" "$dst/"
  done

  echo "Moved $n of $numfiles files into '$dst/'."
}
