#!/bin/bash

# ============================================================
#              CLI Chat Bot using Ollama API
# ============================================================
# This script allows you to have a conversation with an AI
# assistant using the Ollama API directly from your terminal.
# It maintains conversation history and handles errors gracefully.
#
# Note: To submit your message, type your message and press Enter twice.
# ============================================================

# -------------------- Configuration ------------------------

# Ollama API endpoint
OLLAMA_API_URL='http://localhost:11434/v1/completions'

# The model to use (replace with your actual model name)
MODEL_NAME='llama3.2'

# Maximum conversation history length (number of exchanges)
MAX_HISTORY_LENGTH=5  # Adjust this value as needed

# Maximum tokens for assistant's response
MAX_TOKENS=500

# Temperature setting for response randomness
TEMPERATURE=0.7

# Stop tokens for the assistant
STOP_TOKENS='["User:", "Assistant:"]'

# ------------------- Initialization ------------------------

# Initialize conversation history as an empty array
conversation_history=()

# Function to print text with color and formatting
print_text() {
    local color_code="$1"
    local prefix="$2"
    local text="$3"
    printf "\e[${color_code}m%s\e[0m" "$prefix"
    printf "%s\n" "$text"
}

# Function to show loading animation
show_loading() {
    local pid=$1
    local delay=0.1
    local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    tput civis  # Hide cursor
    while kill -0 "$pid" 2>/dev/null; do
        for ((i=0; i<${#spinstr}; i++)); do
            printf "\r%s" "${spinstr:$i:1}"
            sleep $delay
        done
    done
    tput cnorm  # Show cursor
    printf "\r"
}

# Welcome message
clear
print_text "1;34" "" "============================================================"
print_text "1;34" "" "         Welcome to the CLI Chat Bot using Ollama API        "
print_text "1;34" "" "============================================================"
echo "Type 'exit' or 'quit' to end the conversation."
echo "Note: To submit your message, type your message and press Enter twice."
echo

# ------------------- Main Loop -----------------------------

while true; do
    # Read user input (supports multi-line input)
    print_text "1;32" "You: " ""
    user_input=""
    while IFS= read -e -r line; do
        # Break if the user enters an empty line
        [[ -z "$line" ]] && break
        user_input+="$line"$'\n'
    done

    # Trim trailing newline
    user_input="${user_input%$'\n'}"

    # Convert user_input to lowercase for comparison (Bash 3.x compatible)
    user_input_lower=$(echo "$user_input" | tr '[:upper:]' '[:lower:]')

    # Check for exit commands
    if [[ "$user_input_lower" == "exit" ]] || [[ "$user_input_lower" == "quit" ]]; then
        print_text "1;34" "" "Goodbye!"
        break
    fi

    # Append the user's message to the conversation history
    conversation_history+=("User: $user_input")

    # Limit the conversation history to the last N exchanges
    if (( ${#conversation_history[@]} > MAX_HISTORY_LENGTH * 2 )); then
        conversation_history=("${conversation_history[@]: -$((MAX_HISTORY_LENGTH * 2))}")
    fi

    # Construct the prompt by joining the conversation history
    prompt=$(printf "%s\n" "${conversation_history[@]}")
    prompt="$prompt\nAssistant:"

    # Prepare the payload for the Ollama API
    payload=$(jq -n \
        --arg model "$MODEL_NAME" \
        --arg prompt "$prompt" \
        --argjson max_tokens "$MAX_TOKENS" \
        --argjson temperature "$TEMPERATURE" \
        --argjson n 1 \
        --argjson stop "$STOP_TOKENS" \
        '{
            model: $model,
            prompt: $prompt,
            max_tokens: $max_tokens,
            temperature: $temperature,
            n: $n,
            stop: $stop
        }'
    )

    # Create a temporary file for the API response
    response_file=$(mktemp)

    # Send a POST request to the Ollama API in the background
    curl -s -X POST "$OLLAMA_API_URL" \
        -H "Content-Type: application/json" \
        -d "$payload" > "$response_file" &

    # Get the PID of the last background process
    pid=$!

    # Show loading animation while waiting for the response
    show_loading $pid

    # Wait for the background process to finish
    wait $pid

    # Read the response from the temporary file
    response=$(cat "$response_file")

    # Remove the temporary file
    rm -f "$response_file"

    # Check for errors in the response
    error_message=$(echo "$response" | jq -r '.error // empty')
    if [ -n "$error_message" ] && [ "$error_message" != "null" ]; then
        print_text "1;31" "" "Error from API: $error_message"
        echo
        continue
    fi

    # Parse the JSON response to get the assistant's reply
    generated_text=$(echo "$response" | jq -r '.choices[0].text' | sed 's/^[ \t]*//;s/[ \t]*$//')

    # Handle empty responses
    if [ -z "$generated_text" ] || [ "$generated_text" == "null" ]; then
        print_text "1;31" "" "Assistant did not provide a response."
        echo
        continue
    fi

    # Append the assistant's response to the conversation history
    conversation_history+=("Assistant: $generated_text")

    # Print the assistant's response with proper formatting
    print_text "1;36" "Assistant: " "$generated_text"
    echo
done
