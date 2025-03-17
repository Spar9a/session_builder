#!/bin/bash
# User data script for Spark worker nodes

# Configure AWS CLI region
echo "export AWS_DEFAULT_REGION=${aws_region}" >> /etc/profile.d/aws-config.sh
source /etc/profile.d/aws-config.sh

pip3 install awscli-local

# Install CloudWatch agent
wget https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm
rpm -U amazon-cloudwatch-agent.rpm

# Create CloudWatch agent configuration
mkdir -p /opt/aws/cloudwatch
cat > /opt/aws/cloudwatch/config.json << EOF
{
  "agent": {
    "metrics_collection_interval": 60,
    "run_as_user": "root",
    "endpoint_override": "http://localhost:4566"
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/spark/worker.log",
            "log_group_name": "${cloudwatch_group}",
            "log_stream_name": "spark-worker-{instance_id}",
            "timezone": "UTC"
          }
        ]
      }
    }
  },
  "metrics": {
    "metrics_collected": {
      "mem": {
        "measurement": [
          "mem_used_percent"
        ]
      },
      "disk": {
        "measurement": [
          "used_percent"
        ],
        "resources": [
          "/"
        ]
      },
      "cpu": {
        "totalcpu": true
      }
    }
  }
}
EOF

# Start CloudWatch agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:/opt/aws/cloudwatch/config.json

# Install Java if not already installed
if ! command -v java &> /dev/null
then
    amazon-linux-extras install java-openjdk11 -y
fi

# Create directories
mkdir -p /opt/spark /var/log/spark /data/spark

# Get Spark configuration from SSM Parameter Store
SPARK_CONFIG=$(awslocal ssm get-parameter --name "${ssm_config_path}" --query "Parameter.Value" --output text)

# Install helper tools
yum install -y jq python3-pip
pip3 install boto3 awscli

# Discover Spark master using EC2 tags
echo "Discovering Spark master..." > /var/log/spark/worker_init.log

# Wait for master to be fully initialized (retry logic)
MAX_RETRIES=10
RETRY_INTERVAL=30
RETRIES=0
MASTER_IP=""

while [ -z "$MASTER_IP" ] && [ $RETRIES -lt $MAX_RETRIES ]
do
  # Find the master instance by tag
  MASTER_IP=$(awslocal ec2 describe-instances \
    --filters "Name=tag:Name,Values=*-spark-master" "Name=instance-state-name,Values=running" \
    --query "Reservations[].Instances[].PrivateIpAddress" \
    --output text)
  
  if [ -z "$MASTER_IP" ]
  then
    echo "Attempt $RETRIES: Master not found yet, waiting $RETRY_INTERVAL seconds..." >> /var/log/spark/worker_init.log
    sleep $RETRY_INTERVAL
    RETRIES=$((RETRIES+1))
  else
    echo "Found Spark master at $MASTER_IP" >> /var/log/spark/worker_init.log
  fi
done

if [ -z "$MASTER_IP" ]
then
  echo "ERROR: Could not find Spark master after $MAX_RETRIES attempts" >> /var/log/spark/worker_init.log
  exit 1
fi

# Create Spark defaults configuration
mkdir -p /opt/spark/conf
cat > /opt/spark/conf/spark-defaults.conf << EOF
spark.master                      spark://$MASTER_IP:7077
spark.driver.memory               4g
spark.executor.memory             4g
spark.executor.cores              2
spark.driver.cores                2
spark.default.parallelism         20
spark.sql.extensions              io.delta.sql.DeltaSparkSessionExtension
spark.sql.catalog.spark_catalog   org.apache.spark.sql.delta.catalog.DeltaCatalog
spark.hadoop.fs.s3a.impl          org.apache.hadoop.fs.s3a.S3AFileSystem
spark.hadoop.fs.s3a.aws.credentials.provider  com.amazonaws.auth.InstanceProfileCredentialsProvider
EOF

# Create environment file
cat > /etc/profile.d/spark.sh << EOF
export SPARK_HOME=/opt/spark
export PATH=\$PATH:\$SPARK_HOME/bin
export PYSPARK_PYTHON=/usr/bin/python3
export PYSPARK_DRIVER_PYTHON=/usr/bin/python3
EOF

source /etc/profile.d/spark.sh

# Start Spark worker
/opt/spark/sbin/start-worker.sh spark://$MASTER_IP:7077

# Set proper ownership
chown -R ec2-user:ec2-user /opt/spark /var/log/spark /data/spark

echo "Spark worker node setup complete" > /var/log/spark/setup_complete.log