#!/bin/bash

# Functions
function get_parameter {
    echo "$(aws ssm get-parameter --name ${1} --with-decryption --query "Parameter.Value" --output text)"
}

# Main
headscale_bucket=$(get_parameter "headscale_bucket")
DB_FILE="/var/lib/headscale/db.sqlite"
STATE_FILE="/tmp/.backup_statefile_rows"
# List of tables
TABLES=$(sqlite3 $DB_FILE .tables)
# Craft a statement to list the rows in all tables
STMT=""
for TABLE in $TABLES; do
  STMT="$STMT SELECT COUNT(*) FROM $TABLE;"
done

# Check if the state file exists
if [ -f "$STATE_FILE" ]; then
  # Read the last known state from the state file
  LAST_STATE=$(cat "$STATE_FILE")
else
  # If the state file does not exist, create an initial state
  LAST_STATE=$(sqlite3 "$DB_FILE" "$STMT")
  echo "$LAST_STATE" > "$STATE_FILE"
fi 

# Capture the current state
CURRENT_STATE=$(sqlite3 "$DB_FILE" "$STMT")

# Compare the current state with the last known state
if [ "$CURRENT_STATE" != "$LAST_STATE" ]; then
    # If there are changes, backup the database to S3
    aws s3 cp "$DB_FILE" "s3://${S3_BUCKET}${DB_FILE}"
    
    # Update the last known state in the state file
    echo "$CURRENT_STATE" > "$STATE_FILE"
fi
