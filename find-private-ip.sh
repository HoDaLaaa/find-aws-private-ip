#!/bin/bash

# AWS Private IP Finder Script
# This script searches for a specific private IP across various AWS resources
# Usage: ./find-private-ip.sh <PRIVATE_IP> [OPTIONS]
# Options:
#   --region <region>     Search in specific region
#   --all-regions        Search in all AWS regions
#   --parallel           Search regions in parallel (faster but harder to read output)

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Parse command line arguments
PRIVATE_IP=""
SEARCH_REGIONS=""
ALL_REGIONS=false
PARALLEL_SEARCH=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --region)
            if [ -z "$SEARCH_REGIONS" ]; then
                SEARCH_REGIONS="$2"
            else
                SEARCH_REGIONS="$SEARCH_REGIONS $2"
            fi
            shift 2
            ;;
        --all-regions)
            ALL_REGIONS=true
            shift
            ;;
        --parallel)
            PARALLEL_SEARCH=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 <PRIVATE_IP> [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --region <region>     Search in specific region (can be used multiple times)"
            echo "  --all-regions        Search in all AWS regions"
            echo "  --parallel           Search regions in parallel (faster but harder to read output)"
            echo ""
            echo "Examples:"
            echo "  $0 10.0.1.100"
            echo "  $0 10.0.1.100 --region us-west-2"
            echo "  $0 10.0.1.100 --region us-east-1 --region eu-west-1"
            echo "  $0 10.0.1.100 --all-regions"
            echo "  $0 10.0.1.100 --all-regions --parallel"
            exit 0
            ;;
        *)
            if [[ -z "$PRIVATE_IP" ]]; then
                PRIVATE_IP="$1"
            else
                echo -e "${RED}Error: Unknown option: $1${NC}"
                echo "Use --help for usage information"
                exit 1
            fi
            shift
            ;;
    esac
done

# Check if IP address is provided
if [ -z "$PRIVATE_IP" ]; then
    echo -e "${RED}Error: Please provide a private IP address${NC}"
    echo "Usage: $0 <PRIVATE_IP> [OPTIONS]"
    echo "Use --help for more information"
    exit 1
fi

FOUND=false
RESULT=""

# Validate IP address format
if ! [[ $PRIVATE_IP =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    echo -e "${RED}Error: Invalid IP address format${NC}"
    exit 1
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}AWS Private IP Finder${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "${YELLOW}Searching for IP: ${PRIVATE_IP}${NC}"

# Function to get all AWS regions
get_all_regions() {
    aws ec2 describe-regions --query "Regions[].RegionName" --output text 2>/dev/null || echo "us-east-1"
}

# Function to check AWS CLI configuration
check_aws_config() {
    if ! aws sts get-caller-identity &>/dev/null; then
        echo -e "${RED}Error: AWS credentials not configured or expired${NC}"
        echo "Please configure your AWS credentials (STS token) and try again"
        exit 1
    fi

    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    echo -e "${GREEN}✓ AWS Account: ${ACCOUNT_ID}${NC}"
}

# Determine which regions to search
if [ "$ALL_REGIONS" = true ]; then
    echo -e "${YELLOW}Fetching all AWS regions...${NC}"
    SEARCH_REGIONS=$(get_all_regions)
    echo -e "${CYAN}Will search in: $(echo $SEARCH_REGIONS | wc -w) regions${NC}"
elif [ -z "$SEARCH_REGIONS" ]; then
    # Use current region if no specific region specified
    SEARCH_REGIONS=$(aws configure get region || echo "us-east-1")
    echo -e "${CYAN}Searching in region: ${SEARCH_REGIONS}${NC}"
else
    echo -e "${CYAN}Searching in specified region(s): ${SEARCH_REGIONS}${NC}"
fi

echo ""

# Function to print resource details
print_resource_details() {
    local resource_type=$1
    local details=$2

    echo -e "${GREEN}✓ FOUND!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Resource Type: ${resource_type}${NC}"
    echo -e "${GREEN}Details:${NC}"
    echo "$details" | jq '.' 2>/dev/null || echo "$details"
    echo -e "${GREEN}========================================${NC}"
    FOUND=true
}

# Function to search in a specific region
search_in_region() {
    local region=$1
    local region_found=false

    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}Searching in region: ${region}${NC}"
    echo -e "${CYAN}========================================${NC}"

    # 1. Search in Network Interfaces (ENI) - Most comprehensive
    echo -e "${YELLOW}[1/8] Searching in Network Interfaces (ENI)...${NC}"
    ENI_RESULT=$(aws ec2 describe-network-interfaces \
        --region "$region" \
        --filters "Name=private-ip-address,Values=${PRIVATE_IP}" \
        --output json 2>/dev/null || echo "{}")

    if [ "$(echo "$ENI_RESULT" | jq '.NetworkInterfaces | length')" -gt 0 ]; then
        # Extract relevant information
        ENI_INFO=$(echo "$ENI_RESULT" | jq -r '.NetworkInterfaces[0] | {
            NetworkInterfaceId: .NetworkInterfaceId,
            PrivateIpAddress: .PrivateIpAddress,
            Description: .Description,
            Status: .Status,
            AttachmentId: .Attachment.AttachmentId,
            InstanceId: .Attachment.InstanceId,
            InstanceOwnerId: .Attachment.InstanceOwnerId,
            AttachTime: .Attachment.AttachTime,
            InterfaceType: .InterfaceType,
            SubnetId: .SubnetId,
            VpcId: .VpcId,
            AvailabilityZone: .AvailabilityZone,
            Groups: .Groups
        }')

        print_resource_details "Network Interface (ENI)" "$ENI_INFO"
        echo -e "${GREEN}Region: ${region}${NC}"

        # If attached to an instance, get instance details
        INSTANCE_ID=$(echo "$ENI_INFO" | jq -r '.InstanceId // empty')
        if [ ! -z "$INSTANCE_ID" ] && [ "$INSTANCE_ID" != "null" ]; then
            echo -e "${YELLOW}Fetching attached EC2 instance details...${NC}"
            INSTANCE_INFO=$(aws ec2 describe-instances \
                --region "$region" \
                --instance-ids "$INSTANCE_ID" \
                --output json 2>/dev/null | jq -r '.Reservations[0].Instances[0] | {
                    InstanceId: .InstanceId,
                    InstanceType: .InstanceType,
                    State: .State.Name,
                    LaunchTime: .LaunchTime,
                    Tags: .Tags
                }')
            echo -e "${BLUE}Attached EC2 Instance:${NC}"
            echo "$INSTANCE_INFO" | jq '.'
        fi
        return 0
    fi

    # 2. Search in EC2 Instances
    if [ "$region_found" = false ]; then
        echo -e "${YELLOW}[2/8] Searching in EC2 Instances...${NC}"
        EC2_RESULT=$(aws ec2 describe-instances \
            --region "$region" \
            --filters "Name=private-ip-address,Values=${PRIVATE_IP}" \
            --output json 2>/dev/null || echo "{}")

    if [ "$(echo "$EC2_RESULT" | jq '.Reservations | length')" -gt 0 ]; then
        EC2_INFO=$(echo "$EC2_RESULT" | jq -r '.Reservations[0].Instances[0] | {
            InstanceId: .InstanceId,
            InstanceType: .InstanceType,
            State: .State.Name,
            PrivateIpAddress: .PrivateIpAddress,
            PublicIpAddress: .PublicIpAddress,
            LaunchTime: .LaunchTime,
            SubnetId: .SubnetId,
            VpcId: .VpcId,
            Tags: .Tags
        }')

            print_resource_details "EC2 Instance" "$EC2_INFO"
            echo -e "${GREEN}Region: ${region}${NC}"
            return 0
        fi
    fi

    # 3. Search in RDS Instances
    if [ "$region_found" = false ]; then
        echo -e "${YELLOW}[3/8] Searching in RDS Instances...${NC}"
        RDS_INSTANCES=$(aws rds describe-db-instances --region "$region" --output json 2>/dev/null | jq -r '.DBInstances[]' || echo "")

    if [ ! -z "$RDS_INSTANCES" ]; then
        while IFS= read -r instance; do
            if [ ! -z "$instance" ]; then
                ENDPOINT=$(echo "$instance" | jq -r '.Endpoint.Address // empty')
                if [ ! -z "$ENDPOINT" ] && [ "$ENDPOINT" != "null" ]; then
                    # Resolve endpoint to IP
                    RESOLVED_IP=$(dig +short "$ENDPOINT" 2>/dev/null | head -n 1)
                    if [ "$RESOLVED_IP" = "$PRIVATE_IP" ]; then
                        RDS_INFO=$(echo "$instance" | jq '{
                            DBInstanceIdentifier: .DBInstanceIdentifier,
                            DBInstanceClass: .DBInstanceClass,
                            Engine: .Engine,
                            DBInstanceStatus: .DBInstanceStatus,
                            Endpoint: .Endpoint,
                            AllocatedStorage: .AllocatedStorage,
                            VpcId: .DBSubnetGroup.VpcId
                        }')

                            print_resource_details "RDS Instance" "$RDS_INFO"
                            echo -e "${GREEN}Region: ${region}${NC}"
                            return 0
                    fi
                    fi
                fi
            done <<< "$(echo "$RDS_INSTANCES" | jq -c '.')"
        fi
    fi

    # 4. Search in Load Balancers (ALB/NLB/Classic)
    if [ "$region_found" = false ]; then
        echo -e "${YELLOW}[4/8] Searching in Load Balancers (ALB/NLB)...${NC}"

        # Search in ALB/NLB
        LB_RESULT=$(aws elbv2 describe-load-balancers --region "$region" --output json 2>/dev/null || echo "{}")
    if [ "$(echo "$LB_RESULT" | jq '.LoadBalancers | length')" -gt 0 ]; then
        while IFS= read -r lb; do
            if [ ! -z "$lb" ]; then
                LB_ARN=$(echo "$lb" | jq -r '.LoadBalancerArn')
                # Get target health to find IPs
                    TARGET_GROUPS=$(aws elbv2 describe-target-groups \
                        --region "$region" \
                        --load-balancer-arn "$LB_ARN" \
                        --output json 2>/dev/null | jq -r '.TargetGroups[].TargetGroupArn' || echo "")

                for TG_ARN in $TARGET_GROUPS; do
                    if [ ! -z "$TG_ARN" ]; then
                            TARGETS=$(aws elbv2 describe-target-health \
                                --region "$region" \
                                --target-group-arn "$TG_ARN" \
                                --output json 2>/dev/null || echo "{}")

                        if echo "$TARGETS" | jq -r '.TargetHealthDescriptions[].Target.Id' | grep -q "^${PRIVATE_IP}$"; then
                            LB_INFO=$(echo "$lb" | jq '{
                                LoadBalancerName: .LoadBalancerName,
                                Type: .Type,
                                Scheme: .Scheme,
                                State: .State.Code,
                                DNSName: .DNSName,
                                VpcId: .VpcId
                            }')

                                print_resource_details "Load Balancer" "$LB_INFO"
                                echo -e "${BLUE}Target Group ARN: ${TG_ARN}${NC}"
                                echo -e "${GREEN}Region: ${region}${NC}"
                                return 0
                        fi
                    fi
                done
            fi
        done <<< "$(echo "$LB_RESULT" | jq -c '.LoadBalancers[]')"
    fi

    # Search in Classic Load Balancers
    echo -e "${YELLOW}[4b/8] Searching in Classic Load Balancers...${NC}"
    CLB_RESULT=$(aws elb describe-load-balancers --output json 2>/dev/null || echo "{}")
    if [ "$(echo "$CLB_RESULT" | jq '.LoadBalancerDescriptions | length')" -gt 0 ]; then
        while IFS= read -r clb; do
            if [ ! -z "$clb" ]; then
                INSTANCES=$(echo "$clb" | jq -r '.Instances[].InstanceId')
                for INSTANCE_ID in $INSTANCES; do
                    if [ ! -z "$INSTANCE_ID" ]; then
                            INSTANCE_IP=$(aws ec2 describe-instances \
                                --region "$region" \
                                --instance-ids "$INSTANCE_ID" \
                                --query "Reservations[0].Instances[0].PrivateIpAddress" \
                                --output text 2>/dev/null || echo "")

                            if [ "$INSTANCE_IP" = "$PRIVATE_IP" ]; then
                                CLB_INFO=$(echo "$clb" | jq '{
                                    LoadBalancerName: .LoadBalancerName,
                                    DNSName: .DNSName,
                                    Scheme: .Scheme,
                                    VPCId: .VPCId
                                }')

                                print_resource_details "Classic Load Balancer" "$CLB_INFO"
                                echo -e "${BLUE}Instance ID: ${INSTANCE_ID}${NC}"
                                echo -e "${GREEN}Region: ${region}${NC}"
                                return 0
                            fi
                        fi
                    done
                fi
            done <<< "$(echo "$CLB_RESULT" | jq -c '.LoadBalancerDescriptions[]')"
        fi
    fi

    # 5. Search in ECS Tasks
    if [ "$region_found" = false ]; then
        echo -e "${YELLOW}[5/8] Searching in ECS Tasks...${NC}"

        # Get all ECS clusters
        CLUSTERS=$(aws ecs list-clusters --region "$region" --output json 2>/dev/null | jq -r '.clusterArns[]' || echo "")

    for CLUSTER in $CLUSTERS; do
        if [ ! -z "$CLUSTER" ]; then
                # List tasks in the cluster
                TASKS=$(aws ecs list-tasks --region "$region" --cluster "$CLUSTER" --output json 2>/dev/null | jq -r '.taskArns[]' || echo "")

                if [ ! -z "$TASKS" ]; then
                    # Describe tasks to get their IPs
                    TASK_DETAILS=$(aws ecs describe-tasks \
                        --region "$region" \
                        --cluster "$CLUSTER" \
                        --tasks $TASKS \
                        --output json 2>/dev/null || echo "{}")

                # Check if any task has the target IP
                MATCHING_TASK=$(echo "$TASK_DETAILS" | jq --arg ip "$PRIVATE_IP" '.tasks[] | select(.attachments[]?.details[]? | select(.name == "privateIPv4Address" and .value == $ip))')

                if [ ! -z "$MATCHING_TASK" ]; then
                    TASK_INFO=$(echo "$MATCHING_TASK" | jq '{
                        TaskArn: .taskArn,
                        TaskDefinitionArn: .taskDefinitionArn,
                        DesiredStatus: .desiredStatus,
                        LastStatus: .lastStatus,
                        LaunchType: .launchType,
                        PlatformVersion: .platformVersion,
                        Cluster: .clusterArn
                    }')

                        print_resource_details "ECS Task" "$TASK_INFO"
                        echo -e "${GREEN}Region: ${region}${NC}"
                        return 0
                    fi
                fi
            fi
        done
    fi

    # 6. Search in Lambda Functions (VPC-enabled)
    if [ "$region_found" = false ]; then
        echo -e "${YELLOW}[6/8] Searching in Lambda Functions...${NC}"

        # Get all Lambda functions
        FUNCTIONS=$(aws lambda list-functions --region "$region" --output json 2>/dev/null | jq -r '.Functions[]' || echo "")

    if [ ! -z "$FUNCTIONS" ]; then
        while IFS= read -r func; do
            if [ ! -z "$func" ]; then
                VPC_CONFIG=$(echo "$func" | jq '.VpcConfig // empty')
                if [ ! -z "$VPC_CONFIG" ] && [ "$VPC_CONFIG" != "null" ] && [ "$VPC_CONFIG" != "{}" ]; then
                    FUNC_NAME=$(echo "$func" | jq -r '.FunctionName')

                    # Get ENIs associated with the Lambda function
                    SUBNET_IDS=$(echo "$VPC_CONFIG" | jq -r '.SubnetIds[]' 2>/dev/null || echo "")

                    for SUBNET_ID in $SUBNET_IDS; do
                        if [ ! -z "$SUBNET_ID" ]; then
                                # Check ENIs in the subnet for Lambda
                                ENI_CHECK=$(aws ec2 describe-network-interfaces \
                                    --region "$region" \
                                    --filters "Name=subnet-id,Values=${SUBNET_ID}" \
                                              "Name=description,Values=*Lambda*${FUNC_NAME}*" \
                                              "Name=private-ip-address,Values=${PRIVATE_IP}" \
                                    --output json 2>/dev/null || echo "{}")

                            if [ "$(echo "$ENI_CHECK" | jq '.NetworkInterfaces | length')" -gt 0 ]; then
                                LAMBDA_INFO=$(echo "$func" | jq '{
                                    FunctionName: .FunctionName,
                                    FunctionArn: .FunctionArn,
                                    Runtime: .Runtime,
                                    Handler: .Handler,
                                    State: .State,
                                    LastModified: .LastModified,
                                    VpcConfig: .VpcConfig
                                }')

                                    print_resource_details "Lambda Function" "$LAMBDA_INFO"
                                    echo -e "${GREEN}Region: ${region}${NC}"
                                    return 0
                                fi
                            fi
                        done
                    fi
                fi
            done <<< "$(echo "$FUNCTIONS" | jq -c '.')"
        fi
    fi

    # 7. Search in ElastiCache Nodes
    if [ "$region_found" = false ]; then
        echo -e "${YELLOW}[7/8] Searching in ElastiCache Clusters...${NC}"

        # Redis clusters
        REDIS_CLUSTERS=$(aws elasticache describe-cache-clusters \
            --region "$region" \
            --show-cache-node-info \
            --output json 2>/dev/null | jq -r '.CacheClusters[]' || echo "")

    if [ ! -z "$REDIS_CLUSTERS" ]; then
        while IFS= read -r cluster; do
            if [ ! -z "$cluster" ]; then
                NODES=$(echo "$cluster" | jq -r '.CacheNodes[]' 2>/dev/null || echo "")
                if [ ! -z "$NODES" ]; then
                    while IFS= read -r node; do
                        if [ ! -z "$node" ]; then
                            ENDPOINT=$(echo "$node" | jq -r '.Endpoint.Address // empty')
                            if [ ! -z "$ENDPOINT" ] && [ "$ENDPOINT" != "null" ]; then
                                # Resolve endpoint to IP
                                RESOLVED_IP=$(dig +short "$ENDPOINT" 2>/dev/null | head -n 1)
                                if [ "$RESOLVED_IP" = "$PRIVATE_IP" ]; then
                                    CACHE_INFO=$(echo "$cluster" | jq '{
                                        CacheClusterId: .CacheClusterId,
                                        CacheNodeType: .CacheNodeType,
                                        Engine: .Engine,
                                        EngineVersion: .EngineVersion,
                                        CacheClusterStatus: .CacheClusterStatus,
                                        NumCacheNodes: .NumCacheNodes
                                    }')

                                        print_resource_details "ElastiCache Cluster" "$CACHE_INFO"
                                        echo -e "${BLUE}Node Endpoint: ${ENDPOINT}${NC}"
                                        echo -e "${GREEN}Region: ${region}${NC}"
                                        return 0
                                fi
                                fi
                            fi
                        done <<< "$(echo "$NODES" | jq -c '.')"
                    fi
                fi
            done <<< "$(echo "$REDIS_CLUSTERS" | jq -c '.')"
        fi
    fi

    # 8. Search in Redshift Clusters
    if [ "$region_found" = false ]; then
        echo -e "${YELLOW}[8/8] Searching in Redshift Clusters...${NC}"

        REDSHIFT_CLUSTERS=$(aws redshift describe-clusters --region "$region" --output json 2>/dev/null | jq -r '.Clusters[]' || echo "")

    if [ ! -z "$REDSHIFT_CLUSTERS" ]; then
        while IFS= read -r cluster; do
            if [ ! -z "$cluster" ]; then
                ENDPOINT=$(echo "$cluster" | jq -r '.Endpoint.Address // empty')
                if [ ! -z "$ENDPOINT" ] && [ "$ENDPOINT" != "null" ]; then
                    # Resolve endpoint to IP
                    RESOLVED_IP=$(dig +short "$ENDPOINT" 2>/dev/null | head -n 1)
                    if [ "$RESOLVED_IP" = "$PRIVATE_IP" ]; then
                        REDSHIFT_INFO=$(echo "$cluster" | jq '{
                            ClusterIdentifier: .ClusterIdentifier,
                            NodeType: .NodeType,
                            ClusterStatus: .ClusterStatus,
                            MasterUsername: .MasterUsername,
                            DBName: .DBName,
                            Endpoint: .Endpoint,
                            NumberOfNodes: .NumberOfNodes,
                            VpcId: .VpcId
                        }')

                            print_resource_details "Redshift Cluster" "$REDSHIFT_INFO"
                            echo -e "${GREEN}Region: ${region}${NC}"
                            return 0
                        fi
                    fi
                fi
            done <<< "$(echo "$REDSHIFT_CLUSTERS" | jq -c '.')"
        fi
    fi

    # Return 1 if not found in this region
    return 1
}

# Check AWS configuration
check_aws_config

# Search in each region
for REGION in $SEARCH_REGIONS; do
    if [ "$PARALLEL_SEARCH" = true ]; then
        # Run search in background for parallel execution
        search_in_region "$REGION" &
    else
        # Run search sequentially
        if search_in_region "$REGION"; then
            FOUND=true
            exit 0
        fi
    fi
done

# Wait for all parallel searches to complete if running in parallel
if [ "$PARALLEL_SEARCH" = true ]; then
    wait
    # Check if any parallel search found the IP
    if [ "$FOUND" = true ]; then
        exit 0
    fi
fi

# If not found in any region
echo ""
echo -e "${RED}✗ IP address ${PRIVATE_IP} not found in any AWS resources${NC}"
echo ""
echo -e "${YELLOW}Possible reasons:${NC}"
if [ "$ALL_REGIONS" = false ] && [ $(echo "$SEARCH_REGIONS" | wc -w) -eq 1 ]; then
    echo "  1. The IP might be in a different AWS region (searched: $SEARCH_REGIONS)"
else
    echo "  1. Searched all requested regions: $SEARCH_REGIONS"
fi
echo "  2. The IP might have been recently released"
echo "  3. The IP might belong to a service not covered by this script"
echo "  4. Insufficient permissions to query certain resources"
echo ""
echo -e "${BLUE}Searched regions:${NC} $(echo $SEARCH_REGIONS | tr ' ' ', ')"
echo ""
echo -e "${BLUE}Searched resources per region:${NC}"
echo "  • Network Interfaces (ENI)"
echo "  • EC2 Instances"
echo "  • RDS Instances"
echo "  • Load Balancers (ALB/NLB/Classic)"
echo "  • ECS Tasks"
echo "  • Lambda Functions"
echo "  • ElastiCache Clusters"
echo "  • Redshift Clusters"
exit 1