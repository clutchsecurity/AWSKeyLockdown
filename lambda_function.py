import json
import logging
import boto3

# Initialize the logger
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize the boto3 IAM client
iam = boto3.client('iam')

def lambda_handler(event, context):
    # Log the incoming event
    logger.info('Received event: %s', json.dumps(event))
    
    # Extract policy ARN, event name, and source IP address
    policy_arn = event.get('detail', {}).get('requestParameters', {}).get('policyArn', 'Unknown')
    event_name = event.get('detail', {}).get('eventName', '')
    source_ip = event.get('detail', {}).get('sourceIPAddress', '')
    
    # Extract user details
    user_name = event.get('detail', {}).get('requestParameters', {}).get('userName', 'Unknown')

    logger.info('Policy ARN attached: %s', policy_arn)
    logger.info('Event name: %s', event_name)
    logger.info('Source IP: %s', source_ip)
    logger.info('User name: %s', user_name)

    # Condition to check the policy attachment, event source, and source IP address
    if (
        (
            policy_arn == "arn:aws:iam::aws:policy/AWSCompromisedKeyQuarantineV2"
            or policy_arn == "arn:aws:iam::aws:policy/AWSCompromisedKeyQuarantineV3"
        )
        and event_name == "AttachUserPolicy"
        and source_ip == "AWS Internal"
        ):
        
        # Fetch the list of access keys for the user
        try:
            keys_info = iam.list_access_keys(UserName=user_name)
            for key in keys_info['AccessKeyMetadata']:
                if key['Status'] == 'Active':
                    # Disable each active access key found
                    response = iam.update_access_key(UserName=user_name, AccessKeyId=key['AccessKeyId'], Status='Inactive')
                    logger.info('Disabled access key: %s for user: %s', key['AccessKeyId'], user_name)
                    logger.info(response)
        except Exception as e:
            logger.error('Failed to disable access keys for user %s: %s', user_name, str(e))
            raise

    return {
        'statusCode': 200,
        'body': json.dumps('Event processed successfully!')
    }
