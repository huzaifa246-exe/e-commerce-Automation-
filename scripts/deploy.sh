#!/bin/bash
set -e

# Load the AMI ID
AMI_ID=$(cat ami-id.txt)

# Create VPC
VPC_ID=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 --tag-specifications 'ResourceType=vpc,Tags=[{Key=Application,Value=Payment-Processing}]' --query 'Vpc.VpcId' --output text)
echo "Created VPC: $VPC_ID"

# Create Internet Gateway
IGW_ID=$(aws ec2 create-internet-gateway --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Application,Value=Payment-Processing}]' --query 'InternetGateway.InternetGatewayId' --output text)
aws ec2 attach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID
echo "Created and attached IGW: $IGW_ID"

# Create Public Subnets
PUB_SUBNET1=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.1.0/24 --availability-zone us-east-1a --tag-specifications 'ResourceType=subnet,Tags=[{Key=Application,Value=Payment-Processing}]' --query 'Subnet.SubnetId' --output text)
PUB_SUBNET2=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.3.0/24 --availability-zone us-east-1b --tag-specifications 'ResourceType=subnet,Tags=[{Key=Application,Value=Payment-Processing}]' --query 'Subnet.SubnetId' --output text)
echo "Created Public Subnets: $PUB_SUBNET1, $PUB_SUBNET2"

# Create Private Subnets
PRIV_SUBNET1=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.2.0/24 --availability-zone us-east-1a --tag-specifications 'ResourceType=subnet,Tags=[{Key=Application,Value=Payment-Processing}]' --query 'Subnet.SubnetId' --output text)
PRIV_SUBNET2=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.4.0/24 --availability-zone us-east-1b --tag-specifications 'ResourceType=subnet,Tags=[{Key=Application,Value=Payment-Processing}]' --query 'Subnet.SubnetId' --output text)
echo "Created Private Subnets: $PRIV_SUBNET1, $PRIV_SUBNET2"

# Create Route Table and Routes
ROUTE_TABLE_ID=$(aws ec2 create-route-table --vpc-id $VPC_ID --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-route --route-table-id $ROUTE_TABLE_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID
aws ec2 associate-route-table --subnet-id $PUB_SUBNET1 --route-table-id $ROUTE_TABLE_ID
aws ec2 associate-route-table --subnet-id $PUB_SUBNET2 --route-table-id $ROUTE_TABLE_ID
echo "Configured routing for public subnets"

# Create Security Groups
SG_PAYMENT_API=$(aws ec2 create-security-group --group-name sg-payment-api --description "Security Group for Payment API" --vpc-id $VPC_ID --query 'GroupId' --output text)
SG_ALB=$(aws ec2 create-security-group --group-name sg-alb --description "Security Group for ALB" --vpc-id $VPC_ID --query 'GroupId' --output text)

# Authorize Security Groups
aws ec2 authorize-security-group-ingress --group-id $SG_PAYMENT_API --protocol tcp --port 80 --source-group $SG_ALB
aws ec2 authorize-security-group-ingress --group-id $SG_ALB --protocol tcp --port 80 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-egress --group-id $SG_PAYMENT_API --protocol -1 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-egress --group-id $SG_ALB --protocol -1 --cidr 0.0.0.0/0
echo "Configured Security Groups"

# Launch EC2 Instances
EC2_INSTANCE1=$(aws ec2 run-instances --image-id $AMI_ID --instance-type t3.small --subnet-id $PRIV_SUBNET1 --security-group-ids $SG_PAYMENT_API --tag-specifications 'ResourceType=instance,Tags=[{Key=Role,Value=Payment-Server},{Key=Application,Value=Payment-Processing}]' --query 'Instances[0].InstanceId' --output text)
EC2_INSTANCE2=$(aws ec2 run-instances --image-id $AMI_ID --instance-type t3.small --subnet-id $PRIV_SUBNET2 --security-group-ids $SG_PAYMENT_API --tag-specifications 'ResourceType=instance,Tags=[{Key=Role,Value=Payment-Server},{Key=Application,Value=Payment-Processing}]' --query 'Instances[0].InstanceId' --output text)
echo "Launched EC2 Instances: $EC2_INSTANCE1, $EC2_INSTANCE2"

# Create Target Group
TARGET_GROUP_ARN=$(aws elbv2 create-target-group --name payment-api-targets --protocol HTTP --port 80 --vpc-id $VPC_ID --target-type instance --health-check-path "/" --health-check-protocol HTTP --query 'TargetGroups[0].TargetGroupArn' --output text)

# Register Targets
aws elbv2 register-targets --target-group-arn $TARGET_GROUP_ARN --targets Id=$EC2_INSTANCE1 Id=$EC2_INSTANCE2
echo "Registered EC2s with Target Group"

# Create ALB
ALB_ARN=$(aws elbv2 create-load-balancer --name payment-api-alb --subnets $PUB_SUBNET1 $PUB_SUBNET2 --security-groups $SG_ALB --scheme internet-facing --query 'LoadBalancers[0].LoadBalancerArn' --output text)
echo "Created ALB: $ALB_ARN"

# Create Listener
aws elbv2 create-listener --load-balancer-arn $ALB_ARN --protocol HTTP --port 80 --default-actions Type=forward,TargetGroupArn=$TARGET_GROUP_ARN
echo "Created Listener and connected to Target Group"

echo "Deployment Completed Successfully!"
