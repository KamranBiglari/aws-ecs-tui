# AWS ECS Fargate TUI

A terminal-based user interface (TUI) for managing AWS ECS Fargate resources, inspired by the classic `iptraf` interface style. This tool provides an intuitive, interactive dashboard for ECS cluster, service, and task management directly from your terminal.

![AWS ECS TUI Main Screen](https://raw.githubusercontent.com/KamranBiglari/aws-ecs-tui/main/screenshots/main-screen.png)

## Description

AWS ECS Fargate TUI is a bash script that creates an interactive terminal interface for managing AWS Elastic Container Service (ECS) Fargate resources. It allows you to:

- Navigate through AWS profiles and regions
- View and manage ECS clusters, services, and tasks
- Monitor running containers and their status
- Execute commands (SSH) into running containers
- Perform common management actions like scaling services or stopping tasks

The script automatically handles dependencies, making it easy to deploy and use across different environments.

## Features

- **Profile & Region Selection**
  - List and select AWS profiles from your AWS CLI configuration
  - Use default profile when available
  - List and select AWS regions with connectivity testing
  - Fall back to common regions if API calls fail

- **Cluster Management**
  - View clusters with service and task counts
  - Display statistics (running tasks, services, etc.)
  - Differentiate between Fargate and EC2 tasks

- **Service Management**
  - View service details (desired count, running count, pending count)
  - Change desired task count
  - Force new deployment
  - Stop services
  - Enable/disable execute command feature

- **Task Management**
  - View tasks by service or across the entire cluster
  - Show task status and launch type
  - Stop tasks
  - Execute interactive shell commands into containers

- **Execute Command (SSH) Support**
  - Select containers within tasks
  - Automatically detect and offer to enable execute command if disabled
  - Connect to containers with interactive shell

- **Advanced Features**
  - Auto-installation of dependencies (dialog, AWS CLI, jq)
  - Error handling and fallback mechanisms
  - Automatic detection of AWS configuration
  - Pagination for large numbers of services and tasks

## Screenshots

### Main Menu
![Main Menu](https://raw.githubusercontent.com/KamranBiglari/aws-ecs-tui/main/screenshots/main-menu.png)

### Cluster View
![Cluster View](https://raw.githubusercontent.com/KamranBiglari/aws-ecs-tui/main/screenshots/cluster-view.png)

### Service Management
![Service Management](https://raw.githubusercontent.com/KamranBiglari/aws-ecs-tui/main/screenshots/service-management.png)

### Task Management
![Task Management](https://raw.githubusercontent.com/KamranBiglari/aws-ecs-tui/main/screenshots/task-management.png)

### Execute Command
![Execute Command](https://raw.githubusercontent.com/KamranBiglari/aws-ecs-tui/main/screenshots/execute-command.png)

## Requirements

- Bash shell
- AWS CLI (installed and configured with credentials)
- `dialog` utility for the terminal interface
- `jq` for JSON processing

The script will attempt to install missing dependencies automatically if they're not found.

## Installation

1. Clone this repository:
```bash
git clone https://github.com/KamranBiglari/aws-ecs-tui.git
```

2. Make the script executable:
```bash
chmod +x aws-ecs-tui.sh
```

3. Run the script:
```bash
./aws-ecs-tui.sh
```

The script will check for and install dependencies if needed (requires sudo access for package installation).

## Usage

### Navigation

- Use arrow keys to navigate through menus
- Press Enter to select an option
- In radiolist dialogs (profile/region/cluster selection), use Space to select an item
- Press Tab to move between dialog buttons
- Press Escape to cancel or go back (in most dialogs)

### Common Workflows

1. **View a Service's Tasks**:
   - Select your AWS profile and region
   - Choose a cluster
   - Select "View Services"
   - Select a service
   - Choose "View Tasks"

2. **Scale a Service**:
   - Navigate to the service (as above)
   - Select "Change Desired Count"
   - Enter the new count and confirm

3. **Connect to a Container**:
   - Navigate to a task (through service or "View All Tasks in Cluster")
   - Select "Execute Command (SSH)"
   - Select a container
   - If Execute Command is not enabled, you'll be prompted to enable it
   - Use the shell to interact with the container
   - Press Ctrl+D to exit the shell when finished

4. **Force New Deployment**:
   - Navigate to the service
   - Select "Force New Deployment"
   - Confirm the action

### Tips

- The script will attempt to use default profile and region settings when available
- For services with many tasks, the script efficiently retrieves and displays task information
- If you're having trouble connecting to a container, check that Execute Command is enabled for the service
- Execute Command requires appropriate IAM permissions to function correctly

## Troubleshooting

### Common Issues

1. **"Failed to retrieve AWS regions"**
   - The script will fall back to a predefined list of common regions
   - Check your AWS credentials and network connectivity

2. **"Execute Command failed"**
   - Ensure your task has the necessary IAM permissions
   - Verify the task was launched with Execute Command enabled
   - Check that the AWS Session Manager plugin is installed

3. **"No tasks found"**
   - If your service has no running tasks, scale it up first
   - Check the service's deployment status

### Getting Help

If you encounter any issues or have suggestions for improvements, please [open an issue](https://github.com/KamranBiglari/aws-ecs-tui/issues) on GitHub.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- Inspired by the classic `iptraf` interface
- Built using `dialog`, AWS CLI, and `jq`
- Thanks to the AWS ECS team for providing the APIs that make this tool possible

---

**Note**: Replace placeholder image URLs with actual screenshots once you've created them. You'll need to create the screenshots directory in your repository and add your screenshots there.
