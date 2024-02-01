# Headscale in AWS spot instances

---- In progress ----

# Setup:

Create the following Systems Manager Parameters replacing ${Name} with the name you will use with cloudformation:

- ${Name}_acme_email
- ${Name}_cloudflare_key
- ${Name}_domain_name
- ${Name}_bucket
- ${Name}_version
- ${Name}_cloudflare_zone_identifier

# Troubleshooting:

Cloudformation will create a keypair and add the public key to all instances. This is in case you need to troubleshoot anything.

To retrieve the private key data, go to AWS Systems Manager Parameter Store and look for `/ec2/keypair/{key_pair_id}` where `{key_pair_id}` will be the name value provided at the top of cloudformation.

Ref: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-ec2-keypair.html

By default, the security group does NOT allow ssh.
