#!/bin/bash
# config/common.sh - Host detection and shared logic

# 1. Path Management
# Get the directory where THIS script lives (the config folder)
CONF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The project root is one level up
export PROJECT_DIR="$(dirname "$CONF_DIR")"

# Load local environment overrides, if present.
if [[ -f "$PROJECT_DIR/.env" ]]; then
    set -a
    source "$PROJECT_DIR/.env"
    set +a
fi

# 2. Host Detection
HOSTNAME_S=$(hostname -s)
if [[ "$HOSTNAME_S" == palma* || "$HOSTNAME_S" == r* ]]; then
    export PIPELINE_HOST="palma"
else
    export PIPELINE_HOST="omen"
fi

# 3. Source host-specific configuration
# We use CONF_DIR here because omen.sh/palma.sh are in the same folder
if [ -f "$CONF_DIR/${PIPELINE_HOST}.sh" ]; then
    source "$CONF_DIR/${PIPELINE_HOST}.sh"
else
    echo "❌ Error: Configuration for host $PIPELINE_HOST not found in $CONF_DIR"
    exit 1
fi

export MPLBACKEND=Agg

# --- Helper Functions ---

load_modules() {
    if [ "$HAS_MODULE_SYSTEM" = true ]; then
        for mod in "$@"; do
            [ -z "$mod" ] && continue
            module load "$mod"
        done
    fi
    return 0
}

purge_modules() {
    [ "$HAS_MODULE_SYSTEM" = true ] && module purge || true
}

load_ngs_python_env() {
    if [ -f "$VENV_PATH/bin/activate" ]; then
        source "$VENV_PATH/bin/activate"
    else
        echo "❌ Error: Virtual environment not found at $VENV_PATH. Run setup.sh first."
        exit 1
    fi
}


# Layout Helper (defaults to -, takes any kind of symbol as argument. wont overflow inside terminal) 
layout() {
  local width char
  width=$(tput cols 2>/dev/null || echo 80)
  char=${1:--}  
  printf "%${width}s\n" | tr ' ' "$char"
}
#layout      # dashes
#layout '='  # equals

update_check() {

# Update Check / Interactive yes/no
git fetch --quiet #get newest info from repo
BEHIND=$(git rev-list --count HEAD..origin/main) #how many commits are we behind

if [ "$BEHIND" -gt 0 ]; then
    if [ "$BEHIND" -eq 1 ]; then
        echo -e "\nThere is $BEHIND new update available."
    else
        echo -e "\nThere are $BEHIND new update(s) available."
    fi
    if [ "$BEHIND" -lt 5 ]; then
        echo "Consider updating."
    else
        echo "Your Pipeline is outdated. Please update!"
    fi
    
    layout '='
    echo "Update Messages"
    
    # show $behind amount of commit messages:
    git log -"$BEHIND" --format="%h %s" origin/main
    layout '='
        
    # Ask user if they want to update
    read -rp "Do you want to update now? [Y/N] " answer
    case "${answer,,}" in
        y|yes)
        echo "Updating..."
        git reset --hard origin/main
        git pull
        #git status -sb #test command
        echo "Updated."
        ;;
        *)
        echo "Skipping update."
        ;;
    esac
else
    echo -e "\nYou are up to date!\n"
fi

}