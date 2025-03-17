#!/bin/bash
# User data script for Spark master node

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
            "file_path": "/var/log/spark/master.log",
            "log_group_name": "${cloudwatch_group}",
            "log_stream_name": "spark-master-{instance_id}",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/spark/session-builder.log",
            "log_group_name": "${cloudwatch_group}",
            "log_stream_name": "session-builder-{instance_id}",
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

# Create Spark defaults configuration
mkdir -p /opt/spark/conf
cat > /opt/spark/conf/spark-defaults.conf << EOF
spark.master                      spark://$(hostname -i):7077
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

# Start Spark master
/opt/spark/sbin/start-master.sh

# Create a script to run the session builder job
cat > /opt/spark/run_session_builder.sh << 'EOF'
#!/bin/bash
set -e

# Source environment variables
source /etc/profile.d/spark.sh

# Run the Spark job
$SPARK_HOME/bin/spark-submit \
  --master spark://$(hostname -i):7077 \
  --deploy-mode client \
  --name "IDE Session Builder" \
  --conf "spark.driver.memory=4g" \
  --conf "spark.executor.memory=4g" \
  --conf "spark.executor.cores=2" \
  --conf "spark.driver.cores=2" \
  --conf "spark.jars.packages=io.delta:delta-spark_2.12:3.3.0" \
  --conf "spark.sql.extensions=io.delta.sql.DeltaSparkSessionExtension" \
  --conf "spark.sql.catalog.spark_catalog=org.apache.spark.sql.delta.catalog.DeltaCatalog" \
  /opt/spark/session_builder.py \
  --data-lake-bucket "${data_lake_bucket_name}" \
  --raw-data-folder "${raw_data_folder}" \
  --deltalake-folder "${deltalake_folder}" \
  --processed-data-folder "${processed_data_folder}" \
  >> /var/log/spark/session-builder.log 2>&1

# Check exit status
if [ $? -eq 0 ]; then
  echo "$(date) - Session builder job completed successfully" >> /var/log/spark/session-builder.log
  # Create a success flag file for the Lambda function to check
  echo "SUCCESS" > /tmp/job_status
else
  echo "$(date) - Session builder job failed" >> /var/log/spark/session-builder.log
  # Create a failure flag file for the Lambda function to check
  echo "FAILED" > /tmp/job_status
fi
EOF

chmod +x /opt/spark/run_session_builder.sh

# Install helper tools
yum install -y jq python3-pip
pip3 install boto3 awscli

# Create a health check script for Lambda to call
cat > /opt/spark/health_check.sh << 'EOF'
#!/bin/bash
# Check if Spark master is running
if pgrep -f "org.apache.spark.deploy.master.Master" > /dev/null; then
  echo "RUNNING"
else
  echo "STOPPED"
fi

# If job status file exists, return its content
if [ -f /tmp/job_status ]; then
  cat /tmp/job_status
fi
EOF

chmod +x /opt/spark/health_check.sh

# Set proper ownership
chown -R ec2-user:ec2-user /opt/spark /var/log/spark /data/spark

echo "Spark master node setup complete" > /var/log/spark/setup_complete.log