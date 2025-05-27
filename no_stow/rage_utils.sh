#!/usr/bin/env bash
# rage_utils.sh - Utility functions for age/rage operations

rage_folder() {
  if [[ $# -ne 1 ]]; then
    echo "Usage: rage_folder <relative-folder-path>"
    return 1
  fi

  local input="$1"
  if [[ ! -d "$input" ]]; then
    echo "Error: '$input' is not a directory."
    return 1
  fi

  local dir base out recipient_file
  dir=$(dirname "$input")
  base=$(basename "$input")
  out="${base}.tar.age"
  # Expand tilde or environment variables in the recipient path
  recipient_file=$(eval echo "$RAGE_PUBLIC_KEY")

  # Check recipient file exists
  if [[ ! -f "$recipient_file" ]]; then
    echo "Error: Recipients file not found: $recipient_file"
    return 1
  fi

  # Perform encryption and handle errors
  if tar -C "$dir" -cf - "$base" | rage -R "$recipient_file" > "$out"; then
    echo "Encrypted '$input' -> '$out'"
  else
    echo "Error: Encryption failed for '$input'"
    return 1
  fi
}

unrage_folder() {
  if [[ $# -ne 1 ]]; then
    echo "Usage: unrage_folder <encrypted-archive-file>"
    return 1
  fi

  local archive="$1"
  if [[ ! -f "$archive" ]]; then
    echo "Error: '$archive' is not a file."
    return 1
  fi

  # Expand private key path
  local private_key
  private_key=$(eval echo "$RAGE_PRIVATE_KEY")

  # Check private key exists
  if [[ ! -f "$private_key" ]]; then
    echo "Error: Private key not found: $private_key"
    return 1
  fi

  # Perform decryption and extraction without overwriting existing files/folders
  if rage -d -i "$private_key" "$archive" | tar --keep-old-files -xvf -; then
    echo "Decrypted and extracted '$archive' -> ./"
  else
    echo "Error: Decryption failed for '$archive'"
    return 1
  fi
}

rage_file() {
  if [[ $# -ne 1 ]]; then
    echo "Usage: rage_file <file-path>"
    return 1
  fi

  local input="$1"
  if [[ ! -f "$input" ]]; then
    echo "Error: '$input' is not a file."
    return 1
  fi

  local base out recipient_file
  base=$(basename "$input")
  out="${base}.age"
  recipient_file=$(eval echo "$RAGE_PUBLIC_KEY")

  if [[ ! -f "$recipient_file" ]]; then
    echo "Error: Recipients file not found: $recipient_file"
    return 1
  fi

  if rage -R "$recipient_file" "$input" > "$out"; then
    echo "Encrypted file '$input' -> '$out'"
  else
    echo "Error: Encryption failed for file '$input'"
    return 1
  fi
}

unrage_file() {
  if [[ $# -ne 1 ]]; then
    echo "Usage: unrage_file <encrypted-file.age>"
    return 1
  fi

  local archive="$1"
  if [[ ! -f "$archive" ]]; then
    echo "Error: '$archive' is not a file."
    return 1
  fi

  local private_key out
  private_key=$(eval echo "$RAGE_PRIVATE_KEY")
  out="${archive%.age}"

  if [[ ! -f "$private_key" ]]; then
    echo "Error: Private key not found: $private_key"
    return 1
  fi

  # Prevent overwriting existing files
  if [[ -e "$out" ]]; then
    echo "Error: Output file '$out' already exists. Not overwriting."
    return 1
  fi

  if rage -d -i "$private_key" "$archive" > "$out"; then
    echo "Decrypted file '$archive' -> '$out'"
  else
    echo "Error: Decryption failed for file '$archive'"
    return 1
  fi
}
