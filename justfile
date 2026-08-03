set shell := ["bash", "-euo", "pipefail", "-c"]

# Show available recipes.
default:
    @just --list

# Symlink cubrid-ini-fzf into ~/.local/bin (override with CUBRID_INI_FZF_BIN_DIR).
install:
    #!/usr/bin/env bash
    source_path=$(realpath -- "{{ justfile_directory() }}/cubrid-ini-fzf")
    target_dir=${CUBRID_INI_FZF_BIN_DIR:-$HOME/.local/bin}

    [[ -x "$source_path" ]] || {
      printf 'error: source is not executable: %s\n' "$source_path" >&2
      exit 1
    }

    mkdir -p -- "$target_dir"
    target_dir=$(cd -- "$target_dir" && pwd -P)
    target_path=$target_dir/cubrid-ini-fzf

    if [[ -L "$target_path" ]]; then
      current_source=$(readlink -f -- "$target_path" || true)
      if [[ "$current_source" != "$source_path" ]]; then
        printf 'error: refusing to replace unrelated symlink: %s -> %s\n' \
          "$target_path" "$(readlink -- "$target_path")" >&2
        exit 1
      fi
      printf 'Already installed: %s -> %s\n' "$target_path" "$source_path"
    elif [[ -e "$target_path" ]]; then
      printf 'error: refusing to replace existing path: %s\n' "$target_path" >&2
      exit 1
    else
      ln -s -- "$source_path" "$target_path"
      printf 'Installed: %s -> %s\n' "$target_path" "$source_path"
    fi

    case :${PATH:-}: in
      *:"$target_dir":*) ;;
      *)
        printf 'warning: %s is not on PATH\n' "$target_dir" >&2
        ;;
    esac

# Remove the symlink created by `just install` without touching unrelated paths.
uninstall:
    #!/usr/bin/env bash
    source_path=$(realpath -- "{{ justfile_directory() }}/cubrid-ini-fzf")
    target_dir=${CUBRID_INI_FZF_BIN_DIR:-$HOME/.local/bin}
    target_path=$target_dir/cubrid-ini-fzf

    if [[ ! -e "$target_path" && ! -L "$target_path" ]]; then
      printf 'Already uninstalled: %s\n' "$target_path"
      exit 0
    fi

    if [[ ! -L "$target_path" ]]; then
      printf 'error: refusing to remove non-symlink path: %s\n' "$target_path" >&2
      exit 1
    fi

    current_source=$(readlink -f -- "$target_path" || true)
    if [[ "$current_source" != "$source_path" ]]; then
      printf 'error: refusing to remove unrelated symlink: %s -> %s\n' \
        "$target_path" "$(readlink -- "$target_path")" >&2
      exit 1
    fi

    unlink -- "$target_path"
    printf 'Uninstalled: %s\n' "$target_path"
