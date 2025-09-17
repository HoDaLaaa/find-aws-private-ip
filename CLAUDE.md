# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Purpose

This repository contains AWS utility scripts for infrastructure investigation and management tasks.

## Available Scripts

### find-private-ip.sh
Searches for a specific private IP address across various AWS resources and returns detailed information about the resource using it. Supports searching in multiple regions.

**Usage:**
```bash
./find-private-ip.sh <PRIVATE_IP> [OPTIONS]
```

**Options:**
- `--region <region>` - Search in specific region (can be used multiple times)
- `--all-regions` - Search in all AWS regions
- `--parallel` - Search regions in parallel (faster but harder to read output)
- `--help` - Display help information

**Examples:**
```bash
# Search in current/default region
./find-private-ip.sh 10.0.1.100

# Search in specific region
./find-private-ip.sh 10.0.1.100 --region us-west-2

# Search in multiple specific regions
./find-private-ip.sh 10.0.1.100 --region us-east-1 --region eu-west-1

# Search in all regions
./find-private-ip.sh 10.0.1.100 --all-regions

# Search in all regions in parallel (faster)
./find-private-ip.sh 10.0.1.100 --all-regions --parallel
```

**Prerequisites:**
- AWS CLI installed and configured
- Valid AWS credentials (can use STS tokens)
- jq installed for JSON parsing
- dig installed for DNS resolution

**Search order (stops on first match):**
1. Network Interfaces (ENI) - Most comprehensive, shows attachment details
2. EC2 Instances
3. RDS Instances - Resolves endpoints to IPs
4. Load Balancers (ALB/NLB/Classic) - Checks target groups
5. ECS Tasks - Scans all clusters
6. Lambda Functions - Checks VPC-enabled functions
7. ElastiCache Clusters - Resolves endpoints
8. Redshift Clusters

## Development Guidelines

### AWS CLI Best Practices
- Always check AWS credentials before running operations: `aws sts get-caller-identity`
- Use `--output json` and parse with `jq` for reliable data extraction
- Include proper error handling with `2>/dev/null || echo "{}"`
- Use filters efficiently to minimize API calls
- Always include `--region` parameter in AWS commands when supporting multi-region operations
- Use `aws ec2 describe-regions` to dynamically get all available regions

### Script Patterns
- Use color codes for better terminal output visibility
- Implement early exit when target is found to optimize performance
- DNS resolution pattern for services with endpoints: `dig +short "$ENDPOINT" | head -n 1`
- Iterate through collections safely with: `while IFS= read -r item; do ... done <<< "$(echo "$JSON" | jq -c '.')"`
- For multi-region support, wrap search logic in functions that accept region parameter
- Support both sequential and parallel region searches using background processes (`&`) and `wait`

## Common Tasks

### Adding New AWS Resource Types
1. Add new search section following the numbered pattern `[X/Y]`
2. Query the AWS service using appropriate describe command
3. Extract and match against the target IP
4. Call `print_resource_details` function if found
5. Exit with status 0 on success

### Testing Scripts
```bash
# Test with invalid IP format
./find-private-ip.sh invalid

# Test without credentials
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
./find-private-ip.sh 10.0.1.100

# Test with specific IP
./find-private-ip.sh 10.0.1.100
```

## AWS Service Coverage Notes

- **ENI Search**: Most reliable as it covers resources that create network interfaces
- **RDS/ElastiCache/Redshift**: Requires DNS resolution of endpoints
- **ECS Tasks**: Must iterate through all clusters and tasks
- **Lambda**: Only finds VPC-enabled functions with active ENIs
- **Load Balancers**: Checks both target registration and instance backends