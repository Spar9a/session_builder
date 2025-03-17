## Project Structure

This project implements a data processing pipeline for IDE session tracking with the following components:

### Core Components

```
├── docker_mvp/                # Minimal viable product implementation using Docker
│   ├── data_faker/            # Generates synthetic IDE usage data
│   └── session_processor/     # Processes raw data with Apache Spark and assing user sessions
│
├── iaac/                      # Infrastructure as Code for AWS deployment
│   ├── environments/          # Environment-specific configurations
│   ├── modules/               # Terraform modules
│   │   ├── fake_data_generator/  # Data generation service
│   │   ├── monitoring/        # CloudWatch and monitoring resources
│   │   ├── networking/        # VPC and network configuration
│   │   ├── session_builder/   # Core session processing logic
│   │   └── storage/           # S3 buckets and data storage
│
├── docs/                      # Documentation
│   ├── Task.md                # Project requirements
│   ├── architecture.mermaid   # Architecture diagram
│   └── session_reconciliation_logic.mermaid  # Session logic diagram
```

### Docker Implementation

The project includes a Docker-based MVP solution with two main services:

- **data-faker**: Generates synthetic IDE usage data with configurable parameters
- **session-processor**: Processes raw data into user sessions using Apache Spark

Use `docker-compose -f docker-compose.mvp_solution.yml up` to run the local implementation.

### AWS Infrastructure

The production architecture consists of several layers:

1. **Storage Layer**
   - S3 Input Bucket: Stores raw Parquet files
   - S3 Processed Bucket: Stores processed data in Delta Lake format
   - S3 Code Bucket: Contains Spark scripts

2. **Compute Layer**
   - EC2 instances running Apache Spark

3. **Orchestration Layer**
   - EventBridge for scheduled triggers
   - Step Functions for workflow management
   - Lambda functions for coordination

4. **Monitoring Layer**
   - CloudWatch for metrics and alarms
   - CloudTrail for API logging

5. **Security Layer**
   - IAM roles and policies
   - Systems Manager Parameter Store for configuration

6. **Network Layer**
   - VPC with private subnets
   - VPC Endpoints for secure S3 access

### Session Processing Logic

The core session builder logic:

1. Reads new Parquet files from the raw data folder
2. Identifies user sessions based on activity patterns
3. Reconciles with existing sessions to handle overlaps
4. Writes processed data to Delta Lake format
5. Maintains a 5-minute inactivity timeout for session boundaries
6. Move proccessed files from raw folder to processed folder


## Usage
### Docker Implementation
1. Open your terminal
2. Execute `run_local.sh`


### AWS Local
Currenly this solution are not ready because of limition of localstack in case of EC2 containers virtualization

But it is related only to proccessing logic that do not affect overall deployment to AWS infra

#### Requirements:
- Docker
- Docker Compose
- awslocal
- terraform

To be able to run iaac localy you need:

1. Install localstack
2. Run localstack
3. cd into iaac folder
4. Run `tflocal init`
5. Run `tflocal plan`
6. Run `tflocal apply`

Known issues:
1. If you are using MacOS you need to install `brew` under Rosetta2
2. Not all features of AWS are supported by localstack in Free tier 