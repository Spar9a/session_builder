resource "aws_sfn_state_machine" "session_builder_workflow" {
  name     = "${var.resources_name_prefix}-session-workflow"
  role_arn = aws_iam_role.step_function_role.arn
  
  definition = <<EOF
{
  "Comment": "IDE Session Builder Pipeline Workflow",
  "StartAt": "CheckForNewData",
  "States": {
    "CheckForNewData": {
      "Type": "Task",
      "Resource": "${module.check_new_data.lambda_function_arn}",
      "Next": "HasNewData",
      "Retry": [
        {
          "ErrorEquals": ["Lambda.ServiceException", "Lambda.AWSLambdaException", "Lambda.SdkClientException"],
          "IntervalSeconds": 2,
          "MaxAttempts": 3,
          "BackoffRate": 2.0
        }
      ]
    },
    "HasNewData": {
      "Type": "Choice",
      "Choices": [
        {
          "Variable": "$.hasNewData",
          "BooleanEquals": true,
          "Next": "StartEC2Instances"
        }
      ],
      "Default": "NoNewData"
    },
    "StartEC2Instances": {
      "Type": "Task",
      "Resource": "${module.start_ec2_instances.lambda_function_arn}",
      "Next": "WaitForInstancesRunning",
      "Retry": [
        {
          "ErrorEquals": ["Lambda.ServiceException", "Lambda.AWSLambdaException", "Lambda.SdkClientException"],
          "IntervalSeconds": 2,
          "MaxAttempts": 3,
          "BackoffRate": 2.0
        }
      ]
    },
    "WaitForInstancesRunning": {
      "Type": "Wait",
      "Seconds": 120,
      "Next": "CheckJobStatus"
    },
    "CheckJobStatus": {
      "Type": "Task",
      "Resource": "${module.check_job_status.lambda_function_arn}",
      "Next": "IsJobComplete",
      "Retry": [
        {
          "ErrorEquals": ["Lambda.ServiceException", "Lambda.AWSLambdaException", "Lambda.SdkClientException"],
          "IntervalSeconds": 2,
          "MaxAttempts": 3,
          "BackoffRate": 2.0
        }
      ]
    },
    "IsJobComplete": {
      "Type": "Choice",
      "Choices": [
        {
          "Variable": "$.jobStatus",
          "StringEquals": "COMPLETED",
          "Next": "StopEC2Instances"
        },
        {
          "Variable": "$.jobStatus",
          "StringEquals": "RUNNING",
          "Next": "WaitForJobCompletion"
        }
      ],
      "Default": "JobFailed"
    },
    "WaitForJobCompletion": {
      "Type": "Wait",
      "Seconds": 300,
      "Next": "CheckJobStatus"
    },
    "StopEC2Instances": {
      "Type": "Task",
      "Resource": "${module.stop_ec2_instances.lambda_function_arn}",
      "Next": "JobSucceeded",
      "Retry": [
        {
          "ErrorEquals": ["Lambda.ServiceException", "Lambda.AWSLambdaException", "Lambda.SdkClientException"],
          "IntervalSeconds": 2,
          "MaxAttempts": 3,
          "BackoffRate": 2.0
        }
      ]
    },
    "JobSucceeded": {
      "Type": "Succeed"
    },
    "JobFailed": {
      "Type": "Fail",
      "Error": "SessionBuilderJobFailed",
      "Cause": "The Spark job failed to complete successfully"
    },
    "NoNewData": {
      "Type": "Succeed"
    }
  }
}
EOF

  tags = var.tags
}