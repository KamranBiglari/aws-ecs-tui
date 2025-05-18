# AWS ECS Fargate Terminal UI - Similar to iptraf
# Dependencies: dialog, aws-cli, jq

# Function to install dependencies based on the detected package manager
install_dependencies() {
    local package=$1
    local cmd=$2
    
    echo "Installing $package..."
    
    # Check which package manager is available
    if command -v apt-get &> /dev/null; then
        sudo apt-get update -qq && sudo apt-get install -y $package
    elif command -v yum &> /dev/null; then
        sudo yum -y install $package
    elif command -v brew &> /dev/null; then
        brew install $package
    elif command -v pacman &> /dev/null; then
        sudo pacman -S --noconfirm $package
    elif command -v zypper &> /dev/null; then
        sudo zypper install -y $package
    elif command -v apk &> /dev/null; then
        sudo apk add --no-cache $package
    else
        echo "Could not install $package. No supported package manager found."
        echo "Please install $package manually and try again."
        exit 1
    fi
    
    # Verify installation
    if ! command -v $cmd &> /dev/null; then
        echo "Failed to install $package. Please install it manually."
        exit 1
    else
        echo "$package installed successfully."
    fi
}

# Check for required dependencies and install if missing
check_dependencies() {
    local missing_deps=false
    local deps_to_install=""
    
    # Define package names for different package managers (default to command name)
    local dialog_pkg="dialog"
    local aws_pkg="awscli"
    local jq_pkg="jq"
    
    # Check if dialog is installed
    if ! command -v dialog &> /dev/null; then
        echo "dialog is not installed."
        missing_deps=true
        install_dependencies "$dialog_pkg" "dialog"
    fi
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        echo "AWS CLI is not installed."
        missing_deps=true
        
        # AWS CLI installation is more complex, provide instructions
        echo "Installing AWS CLI..."
        
        # Check which package manager is available for AWS CLI
        if command -v apt-get &> /dev/null; then
            sudo apt-get update -qq && sudo apt-get install -y awscli
        elif command -v yum &> /dev/null; then
            sudo yum -y install awscli
        elif command -v brew &> /dev/null; then
            brew install awscli
        elif command -v pip3 &> /dev/null; then
            pip3 install awscli --upgrade --user
            export PATH=$PATH:~/.local/bin
        elif command -v pip &> /dev/null; then
            pip install awscli --upgrade --user
            export PATH=$PATH:~/.local/bin
        else
            echo "Could not install AWS CLI automatically."
            echo "Please follow the official installation guide at:"
            echo "https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
            exit 1
        fi
        
        # Verify AWS CLI installation
        if ! command -v aws &> /dev/null; then
            echo "Failed to install AWS CLI. Please install it manually following the guide at:"
            echo "https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
            exit 1
        else
            echo "AWS CLI installed successfully."
        fi
    fi
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        echo "jq is not installed."
        missing_deps=true
        install_dependencies "$jq_pkg" "jq"
    fi
    
    # Check if AWS CLI is configured
    if ! aws configure list &> /dev/null; then
        echo "AWS CLI is not configured. Please run 'aws configure' to set up your credentials."
        echo "Would you like to configure AWS CLI now? (y/n)"
        read -r response
        if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
            aws configure
        else
            echo "Please configure AWS CLI before running this script."
            exit 1
        fi
    fi
    
    echo "All dependencies are installed and configured."
}

# Initialize variables
DIALOG_TITLE="AWS ECS Fargate Manager"
DIALOG_HEIGHT=20
DIALOG_WIDTH=70
TEMP_FILE=$(mktemp)
SELECTED_PROFILE=""
SELECTED_REGION=""
SELECTED_CLUSTER=""
SELECTED_SERVICE=""
SELECTED_TASK=""
SELECTED_CONTAINER=""

# Clean up on exit
trap 'rm -f $TEMP_FILE; clear' EXIT

# Get AWS profiles
get_aws_profiles() {
    profiles=$(aws configure list-profiles)
    if [ -z "$profiles" ]; then
        dialog --title "Error" --msgbox "No AWS profiles found. Please configure AWS CLI first." 8 40
        exit 1
    fi
    
    # Get default profile if it exists
    default_profile=$(aws configure get default.profile 2>/dev/null)
    
    # Build the profile list for dialog
    profile_options=()
    for profile in $profiles; do
        if [ "$profile" = "$default_profile" ]; then
            profile_options+=("$profile" "$profile (default)" on)
        else
            profile_options+=("$profile" "$profile" off)
        fi
    done
    
    # Show profile selection dialog
    dialog --title "$DIALOG_TITLE" \
           --radiolist "Select AWS Profile:" $DIALOG_HEIGHT $DIALOG_WIDTH 10 \
           "${profile_options[@]}" 2> $TEMP_FILE
    
    # Get the selected profile
    SELECTED_PROFILE=$(cat $TEMP_FILE)
    if [ -z "$SELECTED_PROFILE" ]; then
        if [ ! -z "$default_profile" ]; then
            SELECTED_PROFILE=$default_profile
        else
            exit 0
        fi
    fi
}

# Get AWS regions
get_aws_regions() {
    # Display a loading message
    dialog --title "$DIALOG_TITLE" --infobox "Retrieving AWS regions, please wait..." 5 50
    
    # Try using EC2 describe-regions first
    regions=$(aws ec2 describe-regions --profile $SELECTED_PROFILE --query "Regions[].RegionName" --output text 2>/dev/null)
    
    # If that fails, use a hardcoded list of common regions
    if [ -z "$regions" ] || [ $? -ne 0 ]; then
        dialog --title "$DIALOG_TITLE" --infobox "Could not retrieve regions via API, using default list..." 5 60
        # Fallback to a predefined list of regions
        regions="us-east-1 us-east-2 us-west-1 us-west-2 ca-central-1 eu-west-1 eu-west-2 eu-west-3 eu-central-1 eu-north-1 ap-northeast-1 ap-northeast-2 ap-northeast-3 ap-southeast-1 ap-southeast-2 ap-south-1 sa-east-1"
    fi
    
    # Get default region for the selected profile
    default_region=$(aws configure get region --profile $SELECTED_PROFILE 2>/dev/null)
    
    # If default region is empty, try the default profile's region
    if [ -z "$default_region" ]; then
        default_region=$(aws configure get region 2>/dev/null)
    fi
    
    # If still empty, default to us-east-1
    if [ -z "$default_region" ]; then
        default_region="us-east-1"
    fi
    
    # Build the region list for dialog
    region_options=()
    for region in $regions; do
        if [ "$region" = "$default_region" ]; then
            region_options+=("$region" "$region (default)" on)
        else
            region_options+=("$region" "$region" off)
        fi
    done
    
    # Show region selection dialog
    dialog --title "$DIALOG_TITLE" \
           --radiolist "Select AWS Region:" $DIALOG_HEIGHT $DIALOG_WIDTH 10 \
           "${region_options[@]}" 2> $TEMP_FILE
    
    # Get the selected region
    SELECTED_REGION=$(cat $TEMP_FILE)
    if [ -z "$SELECTED_REGION" ]; then
        if [ ! -z "$default_region" ]; then
            SELECTED_REGION=$default_region
            dialog --title "Information" --msgbox "Using default region: $SELECTED_REGION" 5 40
        else
            dialog --title "Error" --msgbox "No region selected and no default region found. Please select a region." 8 50
            get_aws_regions
            return
        fi
    fi
    
    # Test if the selected region is valid by making a simple API call
    dialog --title "$DIALOG_TITLE" --infobox "Testing connectivity to region $SELECTED_REGION..." 5 50
    aws ecs list-clusters --profile $SELECTED_PROFILE --region $SELECTED_REGION --output json > /dev/null 2>&1
    
    if [ $? -ne 0 ]; then
        dialog --title "Warning" --yesno "Could not connect to region $SELECTED_REGION.\nThis may be due to:\n- Region doesn't exist\n- No permissions in this region\n- Network connectivity issues\n\nDo you want to try a different region?" 12 60
        if [ $? -eq 0 ]; then
            get_aws_regions
            return
        fi
    fi
}

# Get ECS clusters
get_ecs_clusters() {
    # Fetch list of ECS clusters
    clusters=$(aws ecs list-clusters --profile $SELECTED_PROFILE --region $SELECTED_REGION --query "clusterArns" --output json | jq -r '.[]')
    if [ -z "$clusters" ]; then
        dialog --title "Information" --msgbox "No ECS clusters found in region $SELECTED_REGION." 8 50
        return 1
    fi
    
    # Extract cluster names from ARNs
    cluster_options=()
    for cluster in $clusters; do
        cluster_name=$(echo $cluster | awk -F'/' '{print $2}')
        cluster_options+=("$cluster_name" "$cluster_name" off)
    done
    
    # Show cluster selection dialog
    dialog --title "$DIALOG_TITLE" \
           --radiolist "Select ECS Cluster:" $DIALOG_HEIGHT $DIALOG_WIDTH 10 \
           "${cluster_options[@]}" 2> $TEMP_FILE
    
    # Get the selected cluster
    SELECTED_CLUSTER=$(cat $TEMP_FILE)
    if [ -z "$SELECTED_CLUSTER" ]; then
        return 1
    fi
    
    return 0
}

# Get ECS services for the selected cluster
get_ecs_services() {
    # Fetch list of ECS services for the selected cluster
    services=$(aws ecs list-services --profile $SELECTED_PROFILE --region $SELECTED_REGION --cluster $SELECTED_CLUSTER --query "serviceArns" --output json | jq -r '.[]')
    if [ -z "$services" ]; then
        dialog --title "Information" --msgbox "No services found in cluster $SELECTED_CLUSTER." 8 50
        return 1
    fi
    
    # Extract service names from ARNs
    service_options=()
    for service in $services; do
        service_name=$(echo $service | awk -F'/' '{print $3}')
        service_options+=("$service_name" "$service_name" off)
    done
    
    # Show service selection dialog
    dialog --title "$DIALOG_TITLE" \
           --radiolist "Select ECS Service:" $DIALOG_HEIGHT $DIALOG_WIDTH 10 \
           "${service_options[@]}" 2> $TEMP_FILE
    
    # Get the selected service
    SELECTED_SERVICE=$(cat $TEMP_FILE)
    if [ -z "$SELECTED_SERVICE" ]; then
        return 1
    fi
    
    return 0
}

# Display service details and actions
service_actions() {
    # Get service details
    service_details=$(aws ecs describe-services --profile $SELECTED_PROFILE --region $SELECTED_REGION --cluster $SELECTED_CLUSTER --services $SELECTED_SERVICE --output json)
    
    # Extract relevant information
    desired_count=$(echo "$service_details" | jq -r '.services[0].desiredCount')
    running_count=$(echo "$service_details" | jq -r '.services[0].runningCount')
    pending_count=$(echo "$service_details" | jq -r '.services[0].pendingCount')
    
    # Show service details and action menu
    dialog --title "Service: $SELECTED_SERVICE" \
           --menu "Details:\nDesired Count: $desired_count\nRunning Count: $running_count\nPending Count: $pending_count\n\nSelect an action:" $DIALOG_HEIGHT $DIALOG_WIDTH 10 \
           "1" "Change Desired Count" \
           "2" "Force New Deployment" \
           "3" "Stop Service" \
           "4" "View Tasks" \
           "5" "Enable/Disable Execute Command" \
           "6" "Back to Services" \
           2> $TEMP_FILE
    
    action=$(cat $TEMP_FILE)
    
    case $action in
        1) # Change Desired Count
            dialog --title "Change Desired Count" \
                   --inputbox "Enter new desired count:" 8 40 "$desired_count" 2> $TEMP_FILE
            new_count=$(cat $TEMP_FILE)
            if [ ! -z "$new_count" ] && [[ "$new_count" =~ ^[0-9]+$ ]]; then
                aws ecs update-service --profile $SELECTED_PROFILE --region $SELECTED_REGION --cluster $SELECTED_CLUSTER --service $SELECTED_SERVICE --desired-count $new_count > /dev/null
                dialog --title "Success" --msgbox "Desired count updated to $new_count." 8 40
            else
                dialog --title "Error" --msgbox "Invalid input. Please enter a valid number." 8 40
            fi
            service_actions
            ;;
            
        2) # Force New Deployment
            dialog --title "Confirmation" --yesno "Are you sure you want to force a new deployment?" 8 50
            if [ $? -eq 0 ]; then
                aws ecs update-service --profile $SELECTED_PROFILE --region $SELECTED_REGION --cluster $SELECTED_CLUSTER --service $SELECTED_SERVICE --force-new-deployment > /dev/null
                dialog --title "Success" --msgbox "New deployment initiated." 8 40
            fi
            service_actions
            ;;
            
        3) # Stop Service
            dialog --title "Confirmation" --yesno "Are you sure you want to stop the service? This will set desired count to 0." 8 60
            if [ $? -eq 0 ]; then
                aws ecs update-service --profile $SELECTED_PROFILE --region $SELECTED_REGION --cluster $SELECTED_CLUSTER --service $SELECTED_SERVICE --desired-count 0 > /dev/null
                dialog --title "Success" --msgbox "Service stopped (desired count set to 0)." 8 50
            fi
            service_actions
            ;;
            
        4) # View Tasks
            get_ecs_tasks
            if [ $? -eq 0 ]; then
                task_actions
            else
                service_actions
            fi
            ;;
            
        5) # Enable/Disable Execute Command
            # Check current execute command status
            enabled=$(aws ecs describe-services --profile $SELECTED_PROFILE --region $SELECTED_REGION --cluster $SELECTED_CLUSTER --services $SELECTED_SERVICE --query "services[0].enableExecuteCommand" --output text)
            
            if [ "$enabled" = "true" ]; then
                current_status="enabled"
                new_status="disable"
            else
                current_status="disabled"
                new_status="enable"
            fi
            
            dialog --title "Execute Command" --yesno "Execute Command is currently $current_status for this service.\n\nDo you want to $new_status it?" 10 60
            
            if [ $? -eq 0 ]; then
                # Toggle the execute command setting
                if [ "$enabled" = "true" ]; then
                    # Disable execute command
                    aws ecs update-service --profile $SELECTED_PROFILE --region $SELECTED_REGION --cluster $SELECTED_CLUSTER --service $SELECTED_SERVICE --no-enable-execute-command > /dev/null
                    dialog --title "Success" --msgbox "Execute Command disabled for service $SELECTED_SERVICE." 8 50
                else
                    # Enable execute command
                    aws ecs update-service --profile $SELECTED_PROFILE --region $SELECTED_REGION --cluster $SELECTED_CLUSTER --service $SELECTED_SERVICE --enable-execute-command > /dev/null
                    dialog --title "Success" --msgbox "Execute Command enabled for service $SELECTED_SERVICE." 8 50
                fi
            fi
            service_actions
            ;;
            
        6|"") # Back to Services or Cancel
            return
            ;;
    esac
}

# Get ECS tasks for the selected service
get_ecs_tasks() {
    # Fetch list of ECS tasks for the selected service
    tasks=$(aws ecs list-tasks --profile $SELECTED_PROFILE --region $SELECTED_REGION --cluster $SELECTED_CLUSTER --service-name $SELECTED_SERVICE --query "taskArns" --output json | jq -r '.[]')
    
    if [ -z "$tasks" ]; then
        dialog --title "Information" --msgbox "No tasks found for service $SELECTED_SERVICE." 8 50
        return 1
    fi
    
    # Extract task IDs from ARNs and get task details
    task_options=()
    
    # Get details for all tasks
    all_tasks_details=$(aws ecs describe-tasks --profile $SELECTED_PROFILE --region $SELECTED_REGION --cluster $SELECTED_CLUSTER --tasks $tasks --output json)
    
    # Process each task
    for task in $tasks; do
        task_id=$(echo $task | awk -F'/' '{print $3}')
        
        # Extract last status
        task_status=$(echo "$all_tasks_details" | jq -r --arg taskArn "$task" '.tasks[] | select(.taskArn == $taskArn) | .lastStatus')
        
        task_options+=("$task_id" "$task_status" off)
    done
    
    # Show task selection dialog
    dialog --title "$DIALOG_TITLE" \
           --radiolist "Select ECS Task:" $DIALOG_HEIGHT $DIALOG_WIDTH 10 \
           "${task_options[@]}" 2> $TEMP_FILE
    
    # Get the selected task
    SELECTED_TASK=$(cat $TEMP_FILE)
    if [ -z "$SELECTED_TASK" ]; then
        return 1
    fi
    
    return 0
}

# Display task details and actions
task_actions() {
    # Get the full task ARN
    task_arn=$(aws ecs list-tasks --profile $SELECTED_PROFILE --region $SELECTED_REGION --cluster $SELECTED_CLUSTER --service-name $SELECTED_SERVICE --query "taskArns" --output json | jq -r --arg task "$SELECTED_TASK" '.[] | select(contains($task))')
    
    # Get task details
    task_details=$(aws ecs describe-tasks --profile $SELECTED_PROFILE --region $SELECTED_REGION --cluster $SELECTED_CLUSTER --tasks $task_arn --output json)
    
    # Extract relevant information
    task_status=$(echo "$task_details" | jq -r '.tasks[0].lastStatus')
    task_launch_type=$(echo "$task_details" | jq -r '.tasks[0].launchType')
    
    # Show task details and action menu
    dialog --title "Task: $SELECTED_TASK" \
           --menu "Details:\nStatus: $task_status\nLaunch Type: $task_launch_type\n\nSelect an action:" $DIALOG_HEIGHT $DIALOG_WIDTH 10 \
           "1" "Stop Task" \
           "2" "Execute Command (SSH)" \
           "3" "Back to Tasks" \
           2> $TEMP_FILE
    
    action=$(cat $TEMP_FILE)
    
    case $action in
        1) # Stop Task
            dialog --title "Confirmation" --yesno "Are you sure you want to stop the task $SELECTED_TASK?" 8 60
            if [ $? -eq 0 ]; then
                aws ecs stop-task --profile $SELECTED_PROFILE --region $SELECTED_REGION --cluster $SELECTED_CLUSTER --task $SELECTED_TASK > /dev/null
                dialog --title "Success" --msgbox "Task $SELECTED_TASK stop initiated." 8 40
            fi
            get_ecs_tasks
            if [ $? -eq 0 ]; then
                task_actions
            else
                service_actions
            fi
            ;;
            
        2) # Execute Command (SSH)
            # Get containers for the task
            containers=$(echo "$task_details" | jq -r '.tasks[0].containers[].name')
            if [ -z "$containers" ]; then
                dialog --title "Error" --msgbox "No containers found for this task." 8 40
                task_actions
                return
            fi
            
            # Build container options for dialog
            container_options=()
            for container in $containers; do
                container_options+=("$container" "$container" off)
            done
            
            # Show container selection dialog
            dialog --title "Select Container" \
                   --radiolist "Choose a container to connect to:" $DIALOG_HEIGHT $DIALOG_WIDTH 10 \
                   "${container_options[@]}" 2> $TEMP_FILE
            
            SELECTED_CONTAINER=$(cat $TEMP_FILE)
            if [ -z "$SELECTED_CONTAINER" ]; then
                task_actions
                return
            fi
            
            # Check if execute-command is enabled
            dialog --title "Information" --infobox "Checking if execute-command is enabled..." 5 50
            enabled=$(aws ecs describe-services --profile $SELECTED_PROFILE --region $SELECTED_REGION --cluster $SELECTED_CLUSTER --services $SELECTED_SERVICE --query "services[0].enableExecuteCommand" --output text)
            
            if [ "$enabled" != "true" ]; then
                dialog --title "Execute Command Not Enabled" --yesno "Execute Command is not enabled for this service.\n\nWould you like to enable it now?" 8 60
                
                if [ $? -eq 0 ]; then
                    # Enable execute command
                    dialog --title "Enabling Execute Command" --infobox "Enabling Execute Command for service $SELECTED_SERVICE..." 5 60
                    aws ecs update-service --profile $SELECTED_PROFILE --region $SELECTED_REGION --cluster $SELECTED_CLUSTER --service $SELECTED_SERVICE --enable-execute-command > /dev/null
                    
                    # Verify that it was enabled
                    enabled=$(aws ecs describe-services --profile $SELECTED_PROFILE --region $SELECTED_REGION --cluster $SELECTED_CLUSTER --services $SELECTED_SERVICE --query "services[0].enableExecuteCommand" --output text)
                    
                    if [ "$enabled" = "true" ]; then
                        dialog --title "Success" --msgbox "Execute Command has been enabled for this service." 8 50
                    else
                        dialog --title "Error" --msgbox "Failed to enable Execute Command. You may need to check IAM permissions or task role configurations." 8 60
                        task_actions
                        return
                    fi
                else
                    dialog --title "Information" --msgbox "Execute Command is required to SSH into containers.\nYou can enable it from the Service Actions menu." 8 60
                    task_actions
                    return
                fi
            fi
            
            # Clear the screen before executing the command
            clear
            
            # Execute the command
            echo "Connecting to container $SELECTED_CONTAINER in task $SELECTED_TASK..."
            echo "Press Ctrl+D to exit the shell when finished."
            echo "------------------------------------------------------------"
            
            # Execute the command with interactive shell
            aws ecs execute-command --profile $SELECTED_PROFILE \
                                   --region $SELECTED_REGION \
                                   --cluster $SELECTED_CLUSTER \
                                   --task $SELECTED_TASK \
                                   --container $SELECTED_CONTAINER \
                                   --command "/bin/sh" \
                                   --interactive
            
            # After command execution, press any key to continue
            echo ""
            echo "------------------------------------------------------------"
            echo "Session ended. Press any key to continue..."
            read -n 1
            
            # Return to the task actions menu
            task_actions
            ;;
            
        3|"") # Back to Tasks or Cancel
            get_ecs_tasks
            if [ $? -eq 0 ]; then
                task_actions
            else
                service_actions
            fi
            ;;
    esac
}

# Main menu
main_menu() {
    while true; do
        dialog --title "$DIALOG_TITLE" \
               --menu "AWS Profile: $SELECTED_PROFILE\nAWS Region: $SELECTED_REGION\nCluster: $SELECTED_CLUSTER\n\nSelect an option:" $DIALOG_HEIGHT $DIALOG_WIDTH 10 \
               "1" "Select Cluster" \
               "2" "Change Profile" \
               "3" "Change Region" \
               "4" "Exit" \
               2> $TEMP_FILE
        
        option=$(cat $TEMP_FILE)
        
        case $option in
            1) # Select Cluster
                get_ecs_clusters
                if [ $? -eq 0 ]; then
                    cluster_menu
                fi
                ;;
                
            2) # Change Profile
                get_aws_profiles
                ;;
                
            3) # Change Region
                get_aws_regions
                ;;
                
            4|"") # Exit or Cancel
                clear
                exit 0
                ;;
        esac
    done
}

# Cluster menu
cluster_menu() {
    while true; do
        dialog --title "$DIALOG_TITLE" \
               --menu "AWS Profile: $SELECTED_PROFILE\nAWS Region: $SELECTED_REGION\nCluster: $SELECTED_CLUSTER\n\nSelect an option:" $DIALOG_HEIGHT $DIALOG_WIDTH 10 \
               "1" "View Services" \
               "2" "Back to Main Menu" \
               2> $TEMP_FILE
        
        option=$(cat $TEMP_FILE)
        
        case $option in
            1) # View Services
                get_ecs_services
                if [ $? -eq 0 ]; then
                    service_actions
                fi
                ;;
                
            2|"") # Back to Main Menu or Cancel
                return
                ;;
        esac
    done
}

# Start the application
check_dependencies
get_aws_profiles
get_aws_regions
main_menu
