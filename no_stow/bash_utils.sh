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

  # Use ls with quoting to handle complex filenames
  local -a files
  files=( *(.) )
  local -i total_files=${#files[@]}

  if (( total_files == 0 )); then
    echo "No files to move."
    return 0
  fi

  # Cap n at the number of files we actually have
  if (( n > total_files )); then
    n=$total_files
  fi

  # Shuffle and move files
  local -a selected_files
  local -i i=0
  
  # Use a loop to select unique random files
  while (( i < n )); do
    local rand_index=$(( RANDOM % total_files ))
    local candidate="${files[rand_index+1]}"
    
    # Check if file is already selected
    if [[ ! " ${selected_files[@]} " =~ " $candidate " ]]; then
      selected_files+=("$candidate")
      (( i++ ))
    fi
  done

  # Move the selected files (macOS compatible)
  for file in "${selected_files[@]}"; do
    mv -- "$file" "$dst/"
  done

  echo "Moved $n of $total_files files randomly into '$dst/'."
}

undupe_history() {
  nl "$1" | sort -k 2  -k 1,1nr| uniq -f 1 | sort -n | cut -f 2 > unduped_history
  rm "$1"
  mv unduped_history "$1"
}

