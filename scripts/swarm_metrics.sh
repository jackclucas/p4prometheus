#!/bin/bash

# Default config file path
DEFAULT_CONFIG_FILE="/opt/perforce/swarm/data/config.php"

# Function to display help message
function show_help {
    echo "Usage: $0 [-c <config_file>]"
    echo ""
    echo "Options:"
    echo "  -c <config_file>  Specify the Swarm PHP config file path. Default: $DEFAULT_CONFIG_FILE"
    echo "  -h                Show this help message."
}

# Parse command-line options
CONFIG_FILE=$DEFAULT_CONFIG_FILE
while getopts ":c:h" opt; do
    case ${opt} in
        c )
            CONFIG_FILE=$OPTARG
            ;;
        h )
            show_help
            exit 0
            ;;
        \? )
            echo "Invalid option: $OPTARG" 1>&2
            show_help
            exit 1
            ;;
        : )
            echo "Invalid option: $OPTARG requires an argument" 1>&2
            show_help
            exit 1
            ;;
    esac
done
shift $((OPTIND -1))

# Check if the config file exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Config file not found: $CONFIG_FILE"
    exit 1
fi

# Extract the first found username and password from the PHP config file
USERNAME=$(grep -oP "'user'\s*=>\s*'\K[^']+" "$CONFIG_FILE" | head -n 1)
PASSWORD=$(grep -oP "'password'\s*=>\s*'\K[^']+" "$CONFIG_FILE" | head -n 1)

# Debugging outputs
echo "Extracted username: '$USERNAME'"
echo "Extracted password: '$(echo $PASSWORD | sed 's/./*/g')'"  # Masking password for safety

# Check if USERNAME and PASSWORD are not empty
if [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; then
    echo "Error: Username or password not found in the config file."
    exit 1
fi

# Define the URL
FULL_URL="http://localhost/queue/status"

# Call the URL with the credentials from the config file
RESPONSE=$(curl -s -k -u "$USERNAME:$PASSWORD" "$FULL_URL")

# Check if the curl command was successful
if [ $? -ne 0 ]; then
    echo "Error: Failed to call the URL: $FULL_URL"
    exit 1
fi

# Check if the response is valid JSON
echo "$RESPONSE" | jq . > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "Error: Response is not valid JSON:"
    echo "$RESPONSE"
    exit 1
fi

# Extract metrics from the JSON response
tasks=$(echo "$RESPONSE" | jq -r .tasks)
futureTasks=$(echo "$RESPONSE" | jq -r .futureTasks)
workers=$(echo "$RESPONSE" | jq -r .workers)
maxWorkers=$(echo "$RESPONSE" | jq -r .maxWorkers)
workerLifetime=$(echo "$RESPONSE" | jq -r .workerLifetime | sed 's/s$//')  # Remove the 's' at the end

# Generate the Prometheus metrics
cat <<EOF > /var/metrics/swarm_metrics.prom
# HELP swarm_tasks Number of tasks in the Swarm queue.
# TYPE swarm_tasks gauge
swarm_tasks $tasks
# HELP swarm_future_tasks Number of future tasks in the Swarm queue.
# TYPE swarm_future_tasks gauge
swarm_future_tasks $futureTasks
# HELP swarm_workers Number of active Swarm workers.
# TYPE swarm_workers gauge
swarm_workers $workers
# HELP swarm_max_workers Maximum number of Swarm workers.
# TYPE swarm_max_workers gauge
swarm_max_workers $maxWorkers
# HELP swarm_worker_lifetime Lifetime of Swarm workers in seconds.
# TYPE swarm_worker_lifetime gauge
swarm_worker_lifetime $workerLifetime
EOF

echo "Metrics written to /var/metrics/swarm_metrics.prom"

