import boto3, json, os

def lambda_handler(event, context):
    s3 = event.get("Records")[0].get("s3")
    s3_bucket = s3.get("bucket").get("name")
    s3_object = s3.get("object").get("key")
    
    # Initialize clients
    autoscaling_client = boto3.client('autoscaling')
    ssm_client = boto3.client('ssm')
    
    # Get the Auto Scaling group ARN from an environment variable
    ASG_NAME = os.environ.get('ASG_NAME')
    
    if not ASG_NAME:
        print("Please set the ASG_NAME environment variable with the Auto Scaling group Name.")
        return {
            'statusCode': 500,
            'body': json.dumps('Failed to find ASG_NAME in environment variables')
        }
    else:
        # Step 1: Describe the Auto Scaling group to get instance IDs
        response = autoscaling_client.describe_auto_scaling_groups(AutoScalingGroupNames=[ASG_NAME])
    
        # Extract the instance IDs from the Auto Scaling group description
        instances = []
        for group in response['AutoScalingGroups']:
            instances.extend(group['Instances'])
        
        instance_ids = []
        for instance in instances:
            instance_ids.append(instance.get("InstanceId"))
    
        # Step 2: If instance ids exist, send command to the instances
        if instance_ids:
            # Specify the command document name (e.g., AWS-RunShellScript for running shell scripts)
            document_name = 'AWS-RunShellScript'
            
            command = "aws s3 cp s3://{}/{} /{};systemctl restart headscale.service".format(s3_bucket,s3_object,s3_object)
            print("command: {}".format(command))
            
            # Specify the command parameters
            command_parameters = {
                'commands': [command]
            }
            # Send the command to the EC2 instance
            result = ssm_client.send_command(
                InstanceIds=instance_ids,
                DocumentName=document_name,
                DocumentVersion='$DEFAULT',
                TimeoutSeconds=30, # Specify a timeout in seconds (minimum of 30)
                Parameters=command_parameters
            )
            return {
                'statusCode': 200,
                'body': json.dumps('Command sent to instances: {} with result: {}'.format(instance_ids,result))
            }
        else:
            print(f"No instances found in Auto Scaling group with Name: {ASG_NAME}")
            return {
                'statusCode': 500,
                'body': json.dumps('No instances found in Auto Scaling group with Name: {}'.format(ASG_NAME))
            }
