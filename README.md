# Snipe-IT AWS Infrastructure Deployment with Terraform

This Terraform plan sets up the necessary resources in AWS for deploying Snipe-IT, an open-source IT asset management system. The resources created include a VPC, Subnets, RDS MySQL database, EFS storage, ECS Fargate service, and Application Load Balancer for hosting Snipe-IT.

## Prerequisites

Before you begin, ensure you have the following:

- [Terraform](https://www.terraform.io/downloads.html) installed on your local machine.
- An AWS account with the necessary permissions to create resources.
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) installed and configured.
- AWS credentials configured (via environment variables, AWS CLI, or IAM role).

## Configuration

### AWS Credentials

Set up AWS credentials as environment variables:

```bash
export AWS_ACCESS_KEY_ID=<your-access-key-id>
export AWS_SECRET_ACCESS_KEY=<your-secret-access-key>
export AWS_REGION=<your-preferred-region>
```

Or configure via AWS CLI:

```bash
aws configure
```

### Terraform Variables

Edit the `main.tf` file or create a `terraform.tfvars` file to configure the following variables as needed:

- `app_name`: Name of the application (default: `assets-inventory-company`).
- `app_url`: URL for the application (default: `https://assets.inventory.company.com`).

## Architecture

The Terraform plan creates the following AWS infrastructure:

```
                                    ┌─────────────────────────────────────────────────────────────┐
                                    │                          VPC                                │
                                    │                      10.0.0.0/16                            │
                                    │                                                             │
    ┌───────────────┐               │  ┌─────────────────────────────────────────────────────┐    │
    │   Internet    │◄──────────────┼──│              Internet Gateway                       │    │
    └───────────────┘               │  └─────────────────────────────────────────────────────┘    │
           │                        │                          │                                  │
           │                        │  ┌───────────────────────┴───────────────────────┐          │
           │                        │  │           Public Subnets (10.0.1.0/24,        │          │
           │                        │  │                       10.0.4.0/24)             │          │
           ▼                        │  │  ┌─────────────────────────────────────────┐  │          │
    ┌───────────────┐               │  │  │       Application Load Balancer         │  │          │
    │     ALB       │◄──────────────┼──┼──│           (HTTP/HTTPS)                  │  │          │
    │  (Port 443)   │               │  │  └─────────────────────────────────────────┘  │          │
    └───────────────┘               │  │  ┌─────────────────────────────────────────┐  │          │
           │                        │  │  │           NAT Gateway                   │  │          │
           │                        │  │  └─────────────────────────────────────────┘  │          │
           │                        │  └───────────────────────┬───────────────────────┘          │
           │                        │                          │                                  │
           │                        │  ┌───────────────────────┴───────────────────────┐          │
           │                        │  │           Private Subnets (ECS)               │          │
           ▼                        │  │           (10.0.2.0/24, 10.0.5.0/24)          │          │
    ┌───────────────┐               │  │  ┌─────────────────────────────────────────┐  │          │
    │  ECS Fargate  │◄──────────────┼──┼──│         Snipe-IT Container              │  │          │
    │   Service     │               │  │  │         (snipe/snipe-it:latest)         │  │          │
    └───────────────┘               │  │  └─────────────────────────────────────────┘  │          │
           │                        │  └───────────────────────────────────────────────┘          │
           │                        │                          │                                  │
           ▼                        │  ┌───────────────────────┴───────────────────────┐          │
    ┌───────────────┐               │  │           Private Subnets (RDS)               │          │
    │  RDS MySQL    │◄──────────────┼──│           (10.0.3.0/24, 10.0.6.0/24)          │          │
    │  (Port 3306)  │               │  │  ┌─────────────────────────────────────────┐  │          │
    └───────────────┘               │  │  │         MySQL 8.0 Database              │  │          │
                                    │  │  └─────────────────────────────────────────┘  │          │
                                    │  └───────────────────────────────────────────────┘          │
                                    │                                                             │
                                    │  ┌─────────────────────────────────────────────────────┐    │
                                    │  │                      EFS                            │    │
                                    │  │         (Persistent Storage for Snipe-IT)          │    │
                                    │  └─────────────────────────────────────────────────────┘    │
                                    └─────────────────────────────────────────────────────────────┘
```

## Deployment

### Step-by-Step Deployment

This Terraform plan automates the provisioning of the following resources:

1. **VPC and Networking**: Creates a VPC with public and private subnets, Internet Gateway, NAT Gateway, and route tables.
2. **Security Groups**: Creates security groups for ALB, ECS, RDS, and EFS with appropriate ingress/egress rules.
3. **AWS Secrets Manager**: Creates secrets for database password, app key, and SendGrid API key.
4. **RDS MySQL**: Provisions a MySQL 8.0 database instance with the required parameter configurations.
5. **EFS**: Creates an Elastic File System for persistent storage with access points for Snipe-IT data and logs.
6. **ECS Cluster and Service**: Sets up an ECS Fargate cluster with a task definition running the Snipe-IT Docker container.
7. **Application Load Balancer**: Creates an ALB with HTTP listener (configured for HTTPS redirect).

### Detailed Steps

1. **Initialize Terraform**

    ```bash
    terraform init
    ```

2. **Create Secrets in AWS Secrets Manager**

    Before applying the Terraform plan, create the required secrets:

    ```bash
    # Generate an APP_KEY (Laravel requires a base64 encoded 32-character key)
    APP_KEY=$(echo -n "base64:$(openssl rand -base64 32)")
    
    # Create secrets
    aws secretsmanager create-secret --name "assets-inventory/db-admin-password" --secret-string "your-secure-db-password"
    aws secretsmanager create-secret --name "assets-inventory/app-key" --secret-string "$APP_KEY"
    aws secretsmanager create-secret --name "assets-inventory/sendgrid-api-key" --secret-string "your-sendgrid-api-key"
    ```

3. **Plan the Deployment**

    ```bash
    terraform plan
    ```

4. **Apply the Terraform Plan**

    ```bash
    terraform apply
    ```

5. **Configure HTTPS (Recommended)**

    After the initial deployment:
    
    - Request or import an SSL certificate in AWS Certificate Manager (ACM)
    - Uncomment the HTTPS listener in `main.tf`
    - Update the `certificate_arn` with your ACM certificate ARN
    - Run `terraform apply` again

6. **Configure DNS**

    Point your domain to the ALB DNS name (output from Terraform):
    
    ```bash
    terraform output alb_dns_name
    ```

    Create a CNAME record in your DNS provider pointing to this DNS name.

## Resources Created

| Resource Type | Name | Description |
|---------------|------|-------------|
| VPC | assets-vpc | Virtual Private Cloud (10.0.0.0/16) |
| Subnets | assets-public-subnet-1/2 | Public subnets for ALB |
| Subnets | assets-ecs-subnet-1/2 | Private subnets for ECS |
| Subnets | assets-mysql-subnet-1/2 | Private subnets for RDS |
| Internet Gateway | assets-igw | Internet access for public subnets |
| NAT Gateway | assets-nat-gateway | Outbound internet for private subnets |
| Security Groups | assets-alb-sg, assets-ecs-sg, assets-mysql-sg, assets-efs-sg | Network security |
| Secrets Manager | assets-inventory/* | Secrets storage |
| RDS MySQL | assets-inventory-db | MySQL 8.0 database |
| EFS | snipeit-efs | Persistent file storage |
| ECS Cluster | assets-inventory-cluster | Container orchestration |
| ECS Service | snipeit-service | Fargate service running Snipe-IT |
| ALB | assets-inventory-alb | Application Load Balancer |

## Outputs

After successful deployment, Terraform will output:

- `alb_dns_name`: DNS name of the Application Load Balancer
- `rds_endpoint`: Endpoint of the RDS MySQL instance
- `ecs_cluster_name`: Name of the ECS cluster
- `efs_file_system_id`: ID of the EFS file system

## Cost Considerations

The default configuration uses cost-effective resources suitable for development/small production:

- **RDS**: db.t3.micro (eligible for free tier)
- **ECS**: Fargate with 0.5 vCPU, 1GB memory
- **EFS**: Pay-per-use with lifecycle policy
- **NAT Gateway**: Hourly charge + data processing

For production workloads, consider:
- Upgrading RDS instance class
- Enabling Multi-AZ for RDS
- Increasing ECS task CPU/memory
- Adding auto-scaling policies

## Cleanup

To destroy all resources:

```bash
terraform destroy
```

**Note**: RDS has deletion protection enabled by default. To delete:
1. Modify `deletion_protection = false` in `main.tf`
2. Run `terraform apply`
3. Run `terraform destroy`

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

## Acknowledgements

- [Snipe-IT](https://snipeitapp.com/) for providing the open-source IT asset management system.
- [Terraform](https://www.terraform.io/) for infrastructure as code tooling.
- [AWS](https://aws.amazon.com/) for cloud services.