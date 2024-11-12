<p align="center">
  <img alt="Clutch Logo" src="https://github.com/user-attachments/assets/dad3f718-7e60-488b-92e0-61ee71b46837" />
  <h2 align="center">AWSKeyLockdown</h2>
</p>

<div align="center">

[![License](https://img.shields.io/badge/license-GPL--3.0-brightgreen)](/LICENSE)

</div>

AWSKeyLockdown is a security automation tool designed to enforce immediate deactivation of AWS access keys associated with IAM users flagged by the AWSCompromisedKeyQuarantineV* policy. This tool directly addresses limitations in the AWS response to detected compromised credentials, ensuring enhanced security posture and operational integrity.

## Overview

AWS provides mechanisms to detect exposed credentials, such as those inadvertently committed to GitHub. Upon detection, AWS applies the AWSCompromisedKeyQuarantineV* policy to the compromised IAM user. However, this policy alone does not completely mitigate risks, as it may still permit certain privileged operations. AWSKeyLockdown closes this gap by automatically deactivating all access keys associated with the impacted user upon detection, effectively preventing unauthorized actions and data exfiltration.

## Key Features

- **Automated Key Deactivation**: Instantly disables all access keys associated with an IAM user upon application of the AWSCompromisedKeyQuarantineV* policy.
- **Real-Time Monitoring**: Continuously monitors AWS CloudTrail logs for policy attachment events and responds immediately to flagged IAM users.
- **Enhanced Security Assurance**: Ensures complete lockdown of compromised IAM users, mitigating risks of privilege escalation and unauthorized access.

## Demonstrations

### Local testing demo

[![asciicast](https://asciinema.org/a/98c4Elti9Hh3EhVnhEuRI9rAI.svg)](https://asciinema.org/a/98c4Elti9Hh3EhVnhEuRI9rAI)

### Live Github demo

[![asciicast](https://asciinema.org/a/1nFQqFeZorThuzGId3On3HGyE.svg)](https://asciinema.org/a/1nFQqFeZorThuzGId3On3HGyE)

## Getting Started

### Pre-requisites

#### Cloudtrail

Cloudtrail must be enabled before this tool is used.

#### Pre-requisites for local testing

For local testing, AWSKeyLockdown can simulate a response without requiring actual exposure of AWS credentials. To facilitate testing, make the following changes to `lambda_function.py`

```python
    if (policy_arn == "arn:aws:iam::aws:policy/AWSCompromisedKeyQuarantineV2" ...
        and event_name == "AttachUserPolicy"
        # and source_ip == "AWS Internal"
        ):
```

After making these changes, apply terraform templates.

### Installation

Make sure to update `aws_profile` value in `variables.tf` with your aws profile.

```
terraform init
terraform apply -auto-approve -var aws_profile=default
```

### Demo

#### Testing IAM User

Create a test IAM user. We will leak this user for testing.

```bash
USER_NAME=ExampleUser
aws iam create-user --user-name $USER_NAME
OUTPUT=$(aws iam create-access-key --user-name $USER_NAME --output json)
AWS_ACCESS_KEY=$(echo $OUTPUT | jq -r '.AccessKey.AccessKeyId')
AWS_SECRET_KEY=$(echo $OUTPUT | jq -r '.AccessKey.SecretAccessKey')
echo "Verifying credentials with sts get-caller-identity..."
echo "AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY AWS_SECRET_ACCESS_KEY=$AWS_SECRET_KEY aws sts get-caller-identity"
```

Save the access key and aws secret key. It will be leaked to Github.

#### Live Testing - Leak keys on Github

For a real world demo, leak the above noted AWS access keys and secret keys to a public github repository.

#### Local Testing

If you don't want to leak aws access keys to Github, alterantively attach `AWSCompromisedKeyQuarantineV2` policy to the testing IAM user.

Attach `AWSCompromisedKeyQuarantineV2` manually to a demo user.

```
aws iam attach-user-policy --user-name $USER_NAME --policy-arn arn:aws:iam::aws:policy/AWSCompromisedKeyQuarantineV2
```

### Conclusion

Wait for a while for the policies to apply and run `get-caller-identity` command. To avoid caching, run `aws s3 ls` and then run `aws sts get-caller-identity`.

Once the aws access key is leaked to Github or when `AWSCompromisedKeyQuarantineV2` policy is attached to an IAM user, you will see all the access keys associated with the IAM user gets disabled preventing attackers from escalations and exfiltrations.

## Destroy resources

### Terraform templates

```
terraform destroy -auto-approve
```

### Testing IAM User

```bash
USER_NAME=ExampleUser
echo "Deleting access keys..."
aws iam list-access-keys --user-name "$USER_NAME" --query 'AccessKeyMetadata[*].AccessKeyId' --output text | while read -r key_id
do
    echo "Deleting access key: $key_id"
    aws iam delete-access-key --access-key-id "$key_id" --user-name "$USER_NAME"
done
echo "Detaching attached policies..."
aws iam list-attached-user-policies --user-name "$USER_NAME" --query 'AttachedPolicies[*].PolicyArn' --output text | while read -r policy_arn
do
    echo "Detaching policy: $policy_arn"
    aws iam detach-user-policy --user-name "$USER_NAME" --policy-arn "$policy_arn"
done

echo "Deleting IAM user..."
aws iam delete-user --user-name "$USER_NAME"
```

## Debugging

```
aws iam list-attached-user-policies --user-name $USER_NAME
```

## Future Enahancements

- [ ] Notifications - Slack Integration to instantly notify when an exposure is detected and prevented.
- [ ] Cloudformation support - Include scripts to deploy same infrastructure with cloudformation
