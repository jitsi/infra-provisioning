#!/bin/bash

set -e
set -x

# Redrive Queue Script
# This script consumes messages from an OCI Dead Letter Queue (DLQ) and reposts them to the main queue
# Usage: ./redrive-queue.sh <main_queue_id> <queue_endpoint> [max_messages] [visibility_timeout]

# Show help
if [ "$1" = "-h" ] || [ "$1" = "--help" ] || [ -z "$1" ] || [ -z "$2" ]; then
  echo "Usage: $0 <main_queue_id> <queue_endpoint> [max_messages] [visibility_timeout]"
  echo ""
  echo "Arguments:"
  echo "  main_queue_id       - OCI Queue OCID for the main queue (required)"
  echo "  queue_endpoint      - OCI Queue endpoint URL (required)"
  echo "  max_messages        - Maximum number of messages to process (default: 10)"
  echo "  visibility_timeout  - Message visibility timeout in seconds (default: 30)"
  echo ""
  echo "Environment variables:"
  echo "  ORACLE_REGION       - OCI region (required, e.g., 'us-ashburn-1')"
  echo "  DLQ_SUFFIX          - Suffix to identify DLQ OCID (default: '-dlq')"
  echo "  OCI_CONFIG_FILE     - Path to OCI config file (default: ~/.oci/config)"
  echo "  OCI_PROFILE         - OCI config profile to use (default: DEFAULT)"
  echo "  DRY_RUN             - Set to 'true' to validate without making API calls (default: false)"
  echo ""
  echo "Examples:"
  echo "  # Redrive messages from a DLQ back to main queue"
  echo "  ORACLE_REGION=us-ashburn-1 $0 \\"
  echo "    'ocid1.queue.oc1.iad.example' \\"
  echo "    'https://cell-1.queue.messaging.us-ashburn-1.oci.oraclecloud.com'"
  echo ""
  echo "  # Process maximum 50 messages with 60 second timeout"
  echo "  ORACLE_REGION=us-ashburn-1 $0 \\"
  echo "    'ocid1.queue.oc1.iad.example' \\"
  echo "    'https://cell-1.queue.messaging.us-ashburn-1.oci.oraclecloud.com' 50 60"
  echo ""
  echo "  # Use custom DLQ suffix and dry run"
  echo "  ORACLE_REGION=us-ashburn-1 DLQ_SUFFIX='-deadletter' DRY_RUN=true $0 \\"
  echo "    'ocid1.queue.oc1.iad.example' \\"
  echo "    'https://cell-1.queue.messaging.us-ashburn-1.oci.oraclecloud.com'"
  exit 1
fi

MAIN_QUEUE_ID="$1"
QUEUE_ENDPOINT="$2"
MAX_MESSAGES="${3:-10}"
VISIBILITY_TIMEOUT="${4:-30}"
DLQ_SUFFIX="${DLQ_SUFFIX:--dlq}"
OCI_CONFIG_FILE="${OCI_CONFIG_FILE:-$HOME/.oci/config}"
OCI_PROFILE="${OCI_PROFILE:-DEFAULT}"
DRY_RUN="${DRY_RUN:-false}"

# Validate ORACLE_REGION is set
if [ -z "$ORACLE_REGION" ]; then
  echo "Error: ORACLE_REGION environment variable is required"
  echo "Example: export ORACLE_REGION=us-ashburn-1"
  exit 1
fi

# Derive DLQ queue ID from main queue ID
if [[ "$MAIN_QUEUE_ID" == *"$DLQ_SUFFIX" ]]; then
  # If queue ID already ends with DLQ suffix, it's the DLQ ID
  DLQ_QUEUE_ID="$MAIN_QUEUE_ID"
  # Remove DLQ suffix to get main queue ID
  MAIN_QUEUE_ID="${MAIN_QUEUE_ID%"$DLQ_SUFFIX"}"
else
  # If queue ID doesn't end with DLQ suffix, it's the main queue ID
  # Add DLQ suffix to get DLQ queue ID
  DLQ_QUEUE_ID="${MAIN_QUEUE_ID}${DLQ_SUFFIX}"
fi

echo "=== OCI Queue Redrive Script ==="
echo "Main Queue ID: $MAIN_QUEUE_ID"
echo "DLQ Queue ID: $DLQ_QUEUE_ID"
echo "Queue Endpoint: $QUEUE_ENDPOINT"
echo "Region: $ORACLE_REGION"
echo "Max Messages: $MAX_MESSAGES"
echo "Visibility Timeout: $VISIBILITY_TIMEOUT seconds"
echo "OCI Config: $OCI_CONFIG_FILE (profile: $OCI_PROFILE)"
if [ "$DRY_RUN" = "true" ]; then
  echo "Mode: DRY RUN (no actual API calls will be made)"
fi
echo ""

# Validate OCI config file exists (skip in dry run mode)
if [ "$DRY_RUN" != "true" ] && [ ! -f "$OCI_CONFIG_FILE" ]; then
  echo "Error: OCI config file not found at $OCI_CONFIG_FILE"
  echo "Please ensure you have a valid OCI configuration file."
  exit 1
fi


# Function to consume messages from DLQ
consume_dlq_messages() {
  local count=0
  local processed=0
  local failed=0
  
  echo "Starting to consume messages from DLQ..."
  
  while [ "$count" -lt "$MAX_MESSAGES" ]; do
    echo "Attempting to receive messages (batch $((count + 1))-$((count + 10)))..."
    
    # Use OCI CLI to get messages from DLQ
    # Note: This uses oci CLI - in production you might want to use direct REST API calls
    local messages_json
    if [ "$DRY_RUN" = "true" ]; then
      # Mock response for dry run
      messages_json='{"data": {"messages": []}}'
      echo "DRY RUN: Would call 'oci queue messages get-messages --queue-id $DLQ_QUEUE_ID --endpoint $QUEUE_ENDPOINT --region $ORACLE_REGION --limit 10 --visibility-in-seconds $VISIBILITY_TIMEOUT'"
    else
      if ! messages_json=$(oci queue messages get-messages \
        --queue-id "$DLQ_QUEUE_ID" \
        --endpoint "$QUEUE_ENDPOINT" \
        --region "$ORACLE_REGION" \
        --limit 10 \
        --visibility-in-seconds "$VISIBILITY_TIMEOUT" \
        --config-file "$OCI_CONFIG_FILE" \
        --profile "$OCI_PROFILE" \
        --output json 2>/dev/null); then
        echo "Failed to receive messages from DLQ. Check your OCI configuration and queue parameters."
        exit 1
      fi
    fi
    
    # Check if we got any messages
    local message_count
    message_count=$(echo "$messages_json" | jq -r '.data.messages | length' 2>/dev/null || echo "0")
    
    if [ "$message_count" -eq 0 ]; then
      echo "No more messages found in DLQ."
      break
    fi
    
    echo "Received $message_count messages from DLQ"
    
    # Process each message
    local i=0
    while [ "$i" -lt "$message_count" ]; do
      local message_content receipt_handle
      message_content=$(echo "$messages_json" | jq -r ".data.messages[$i].content" 2>/dev/null)
      receipt_handle=$(echo "$messages_json" | jq -r ".data.messages[$i].receipt" 2>/dev/null)
      
      if [ "$message_content" != "null" ] && [ "$receipt_handle" != "null" ]; then
        echo "Processing message $((processed + 1)): ${message_content:0:100}..."
        
        # Send message to main queue
        if send_to_main_queue "$message_content"; then
          # Delete message from DLQ after successful repost
          if delete_from_dlq "$receipt_handle"; then
            echo "✓ Message successfully redriven and deleted from DLQ"
            ((processed++))
          else
            echo "✗ Message sent to main queue but failed to delete from DLQ"
            ((failed++))
          fi
        else
          echo "✗ Failed to send message to main queue"
          ((failed++))
        fi
      else
        echo "✗ Invalid message format received"
        ((failed++))
      fi
      
      ((i++))
      ((count++))
      
      if [ "$count" -ge "$MAX_MESSAGES" ]; then
        break
      fi
    done
    
    # Small delay between batches
    sleep 1
  done
  
  echo ""
  echo "=== Summary ==="
  echo "Messages processed: $processed"
  echo "Messages failed: $failed"
  echo "Total messages handled: $((processed + failed))"
}

# Function to send message to main queue
send_to_main_queue() {
  local message_content="$1"
  
  # Create a temporary file for the message
  local temp_file
  temp_file=$(mktemp)
  echo "$message_content" > "$temp_file"
  
  # Send message to main queue using OCI CLI
  if [ "$DRY_RUN" = "true" ]; then
    echo "  DRY RUN: Would send message to main queue: $MAIN_QUEUE_ID"
    rm -f "$temp_file"
    return 0
  else
    # Create proper message format for OCI queue
    local message_json
    message_json=$(jq -n --arg content "$message_content" '[{content: $content}]')
    echo "$message_json" > "$temp_file"
    
    if oci queue messages put-messages \
      --queue-id "$MAIN_QUEUE_ID" \
      --endpoint "$QUEUE_ENDPOINT" \
      --region "$ORACLE_REGION" \
      --messages file://"$temp_file" \
      --config-file "$OCI_CONFIG_FILE" \
      --profile "$OCI_PROFILE" \
      >/dev/null 2>&1; then
      rm -f "$temp_file"
      return 0
    else
      rm -f "$temp_file"
      return 1
    fi
  fi
}

# Function to delete message from DLQ
delete_from_dlq() {
  local receipt_handle="$1"
  
  # Delete message from DLQ using OCI CLI
  if [ "$DRY_RUN" = "true" ]; then
    echo "  DRY RUN: Would delete message from DLQ: $receipt_handle"
    return 0
  else
    oci queue messages delete-message \
      --queue-id "$DLQ_QUEUE_ID" \
      --endpoint "$QUEUE_ENDPOINT" \
      --region "$ORACLE_REGION" \
      --message-receipt "$receipt_handle" \
      --config-file "$OCI_CONFIG_FILE" \
      --profile "$OCI_PROFILE" \
      --force
    if [ $? -eq 0 ]; then
      return 0
    else
      return 1
    fi
  fi
}

# Check prerequisites
if ! command -v jq &> /dev/null; then
  echo "Error: jq is required but not installed. Please install jq."
  exit 1
fi

if [ "$DRY_RUN" != "true" ] && ! command -v oci &> /dev/null; then
  echo "Error: OCI CLI is required but not installed. Please install and configure OCI CLI."
  exit 1
elif [ "$DRY_RUN" = "true" ] && ! command -v oci &> /dev/null; then
  echo "Warning: OCI CLI not found, but continuing in dry-run mode"
fi

# Main execution
consume_dlq_messages

echo "Redrive operation completed."
