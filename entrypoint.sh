#!/bin/bash
# Arguments:
#   $1: A string in the format "username1:password1;username2:password2;..."
# Output:
#   Prints the complete TOML formatted string to stdout if successful.
#   Prints warnings or errors to stderr.
# Returns:
#   0 on success.
#   1 if no input string is provided or if there's a fundamental issue.
#
generate_users_toml() {
  local users_string="$1"
  local index=0
  local OLD_IFS
  local -a user_entries # Declare as a local array
  local entry user_pass_part params_part username password # Other local variables
  local toml_output="" # Initialize an empty string to accumulate TOML
  local param_entry param_key param_value

  # Check if the users_string argument is provided
  if [ -z "$users_string" ]; then
    echo "Error: No user string provided to generate_users_toml function." >&2
    return 1
  fi

  # Save the original IFS and set IFS to semicolon for splitting user entries
  OLD_IFS="$IFS"
  IFS=';'
  # Read the user entries into an array
  read -r -a user_entries <<< "$users_string"
  # Restore IFS
  IFS="$OLD_IFS"

  # Loop through each user entry
  for entry in "${user_entries[@]}"; do
    # Skip empty entries that might result from trailing semicolons or multiple semicolons
    if [ -z "$entry" ]; then
      continue
    fi

    # Check if the entry contains a hash for parameters
    if [[ "$entry" != *#* ]]; then
      echo "Warning: Malformed entry '$entry' (missing # for parameters). Skipping." >&2
      continue
    fi

    # Split the entry into user_pass_part and params_part
    user_pass_part="${entry%#*}" # Everything before the last #
    params_part="${entry##*#}" # Everything after the last #

    # Check if the user_pass_part contains a colon
    if [[ "$user_pass_part" != *:* ]]; then
      echo "Warning: Malformed entry '$entry' (missing : in user/password part). Skipping." >&2
      continue
    fi

    # Split the user_pass_part into username and password
    username="${user_pass_part%%:*}" # Everything before the first colon
    password="${user_pass_part#*:}"  # Everything after the first colon

    # Start TOML section for this user
    printf -v toml_output '%s[pools.postgres.users.%s]\n' "$toml_output" "$index"
    printf -v toml_output '%s    username = "%s"\n' "$toml_output" "$username"
    printf -v toml_output '%s    password = "%s"\n' "$toml_output" "$password"

    # Process parameters part (e.g., pool_size=5,statement_timeout=0)
    if [ -n "$params_part" ]; then
      local OLD_PARAMS_IFS="$IFS"
      IFS=','
      local -a params_array
      read -r -a params_array <<< "$params_part"
      IFS="$OLD_PARAMS_IFS"

      for param_entry in "${params_array[@]}"; do
        if [[ "$param_entry" != *=* ]]; then
          echo "Warning: Malformed parameter '$param_entry' in entry '$entry' (missing =). Skipping parameter." >&2
          continue
        fi
        param_key="${param_entry%%=*}"
        param_value="${param_entry#*=}"

        # Sanitize key: remove any leading/trailing whitespace (basic)
        param_key=$(echo "$param_key" | awk '{$1=$1};1') # Trim whitespace

        # Check if param_value is a number or should be a string
        if [[ "$param_value" =~ ^[0-9]+$ ]]; then
          printf -v toml_output '%s    %s = %s\n' "$toml_output" "$param_key" "$param_value"
        elif [[ "$param_value" =~ ^(true|false)$ ]]; then # Handle booleans
          printf -v toml_output '%s    %s = %s\n' "$toml_output" "$param_key" "$param_value"
        else # Treat as string
          printf -v toml_output '%s    %s = "%s"\n' "$toml_output" "$param_key" "$param_value"
        fi
      done
    fi

    printf -v toml_output '%s\n' "$toml_output" # Add a blank line for better readability

    # Increment the index
    index=$((index + 1))
  done

  # If any TOML was generated, print it to stdout
  if [ -n "$toml_output" ]; then
    echo -n "$toml_output"
  fi

  return 0 # Success
}

# Input: SERVERS_VAR="database_name#host1:port1:role1;host2:port2:role2;..."
# Output: TOML string to stdout, or error messages to stderr with a non-zero exit code.
generate_pool_config() {
    local SERVERS_VAR="$1"
    local toml_output=""
    local database_name=""
    local servers_part=""
    local primary_count=0
    # Array to store individual server TOML lines, e.g., "    [ \"host1\", port1, \"role1\" ]"
    local server_details_array=()

    # Check if SERVERS_VAR is empty
    if [[ -z "$SERVERS_VAR" ]]; then
        echo "Error: SERVERS variable string is empty." >&2
        return 1
    fi

    # Extract database_name and servers_part
    # The format is database_name#server_entries
    if [[ "$SERVERS_VAR" != *"#"* ]]; then
        echo "Error: SERVERS variable format is invalid. Missing '#' separator between database name and server list." >&2
        echo "Expected format: database_name#host1:port1:role1;host2:port2:role2" >&2
        return 1
    fi
    database_name="${SERVERS_VAR%%#*}" # Get everything before the first '#'
    servers_part="${SERVERS_VAR#*#}"    # Get everything after the first '#'

    # Validate extracted parts
    if [[ -z "$database_name" ]]; then
        echo "Error: Database name is missing in the SERVERS variable string (before '#')." >&2
        return 1
    fi

    if [[ -z "$servers_part" ]];then
        echo "Error: Server entries are missing in the SERVERS variable string (after '#')." >&2
        return 1
    fi

    # Split servers_part into individual server entry strings (semicolon-separated)
    IFS=';' read -r -a server_array <<< "$servers_part"

    if [[ ${#server_array[@]} -eq 0 ]]; then
        echo "Error: No server entries found after '#'." >&2
        return 1
    fi
    if [[ ${#server_array[@]} -eq 1 && -z "${server_array[0]}" ]]; then # Handle case like "dbname#"
        echo "Error: No server entries found after '#'." >&2
        return 1
    fi


    # Process each server entry
    for server_entry in "${server_array[@]}"; do
        # Skip if an entry is empty (e.g., due to "val1;;val2" or trailing ";")
        if [[ -z "$server_entry" ]]; then
            echo "Warning: Empty server entry segment found, skipping." >&2
            continue
        fi

        # Parse host:port:role using regex for better validation
        # Host can be anything not ':', port must be numeric, role can be anything not ':'
        if ! [[ "$server_entry" =~ ^([^:]+):([0-9]+):([^:]+)$ ]]; then
            echo "Error: Invalid server entry format in '$server_entry'." >&2
            echo "Expected host:port:role, where port is a number (e.g., 'myhost:5432:primary')." >&2
            return 1
        fi

        local host="${BASH_REMATCH[1]}"
        local port="${BASH_REMATCH[2]}" # Port is validated as numeric by the regex
        local role="${BASH_REMATCH[3]}"

        # Validate role type and count primaries
        if [[ "$role" == "primary" ]]; then
            primary_count=$((primary_count + 1))
        elif [[ "$role" != "replica" ]]; then
            echo "Error: Invalid role '$role' for server '$host:$port'. Role must be 'primary' or 'replica'." >&2
            return 1
        fi

        # Add formatted server detail to the array for TOML construction
        # Host and role are quoted strings, port is a number.
        server_details_array+=("    [ \"$host\", $port, \"$role\" ]")
    done

    # Validate primary server count
    if [[ ${#server_details_array[@]} -eq 0 ]]; then # Check if any valid servers were processed
        echo "Error: No valid server configurations were processed." >&2
        return 1
    fi

    if [[ "$primary_count" -eq 0 ]]; then
        echo "Error: No 'primary' server role found. Exactly one primary server is required." >&2
        return 1
    fi
    if [[ "$primary_count" -gt 1 ]]; then
        echo "Error: Multiple 'primary' servers found ($primary_count). Only one 'primary' server is allowed." >&2
        return 1
    fi

    # Construct the TOML string for the 'servers' array
    local servers_toml_lines=""
    for i in "${!server_details_array[@]}"; do
        servers_toml_lines+="${server_details_array[$i]}"
        # Add a comma and newline if it's not the last element in the array
        if [[ $i -lt $((${#server_details_array[@]} - 1)) ]]; then
            servers_toml_lines+=","$'\n'
        fi
    done

    # Use printf to safely construct the final multi-line TOML output
    printf -v toml_output '[pools.postgres.shards.0]\nservers = [\n%s\n]\ndatabase = "%s"\n' \
        "$servers_toml_lines" \
        "$database_name"

    echo "$toml_output"
    return 0
}

export USER_CONFIG=$(generate_users_toml $USERS)
export POOL_CONFIG=$(generate_pool_config $SERVERS)

envsubst < config.template.toml | sponge pgcat.toml

exec "$@"
