# AWS Private IP Finder

A utility script for searching private IP addresses across various AWS resources in your AWS account.

## Overview

This repository contains a bash script that helps you locate which AWS resource is using a specific private IP address. The script searches across multiple AWS services and provides detailed information about the resource using the IP.

## Features

- Search for private IP addresses across multiple AWS resource types
- Support for single region or multi-region searches
- Parallel search capability for faster execution
- Comprehensive coverage of AWS services including:
  - Network Interfaces (ENI)
  - EC2 Instances
  - RDS Instances
  - Load Balancers (ALB/NLB/Classic)
  - ECS Tasks
  - Lambda Functions
  - ElastiCache Clusters
  - Redshift Clusters

## Prerequisites

- AWS CLI installed and configured
- Valid AWS credentials (supports STS tokens)
- `jq` installed for JSON parsing
- `dig` installed for DNS resolution

## Installation

1. Clone this repository:
```bash
git clone https://github.com/HoDaLaaa/find-aws-private-ip.git
cd find-aws-private-ip
```

2. Make the script executable:
```bash
chmod +x find-private-ip.sh
```

## Usage

### Basic Usage
```bash
./find-private-ip.sh <PRIVATE_IP>
```

### Options
- `--region <region>` - Search in specific region (can be used multiple times)
- `--all-regions` - Search in all AWS regions
- `--parallel` - Search regions in parallel (faster but harder to read output)
- `--help` - Display help information

### Examples

Search in current/default region:
```bash
./find-private-ip.sh 10.0.1.100
```

Search in specific region:
```bash
./find-private-ip.sh 10.0.1.100 --region us-west-2
```

Search in multiple specific regions:
```bash
./find-private-ip.sh 10.0.1.100 --region us-east-1 --region eu-west-1
```

Search in all regions:
```bash
./find-private-ip.sh 10.0.1.100 --all-regions
```

Search in all regions in parallel (faster):
```bash
./find-private-ip.sh 10.0.1.100 --all-regions --parallel
```

## How It Works

The script searches AWS resources in the following order (stops on first match):

1. **Network Interfaces (ENI)** - Most comprehensive, shows attachment details
2. **EC2 Instances** - Direct instance searches
3. **RDS Instances** - Resolves endpoints to IPs
4. **Load Balancers** - Checks target groups and backends
5. **ECS Tasks** - Scans all clusters
6. **Lambda Functions** - Checks VPC-enabled functions
7. **ElastiCache Clusters** - Resolves cluster endpoints
8. **Redshift Clusters** - Resolves cluster endpoints

## Output

When a match is found, the script provides detailed information about the resource, including:
- Resource type and identifier
- Region and availability zone
- Additional metadata specific to the resource type
- Attachment information (for ENIs)

## Error Handling

The script includes comprehensive error handling for:
- Invalid IP address formats
- Missing AWS credentials
- Network connectivity issues
- AWS API errors

## Contributing

Feel free to submit issues and enhancement requests!

## License

This project is open source and available under the [MIT License](LICENSE).