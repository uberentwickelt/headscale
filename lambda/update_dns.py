import boto3, json, os, requests

def lambda_handler(event, context):

    # Get application name to understand what parameters to retrieve
    app_name = os.environ.get('APP_NAME')

    # Get provided hostname
    hostname = event.get("hostname")
    
    # Initialize clients
    ssm_client = boto3.client('ssm')

    cloudflare_key = ssm_client.get_parameter(Name=f'{app_name}_cloudflare_key', WithDecryption=True).get("Parameter").get("Value")
    cloudflare_zone_identifier = ssm_client.get_parameter(Name=f'{app_name}_cloudflare_zone_identifier', WithDecryption=True).get("Parameter").get("Value")
    domain_name = ssm_client.get_parameter(Name=f'{app_name}_domain_name', WithDecryption=True).get("Parameter").get("Value")

    headers = {
        'Content-Type': 'application/json',
        'Authorization': f'Bearer {cloudflare_key}'
    }

    identifier_url = f'https://api.cloudflare.com/client/v4/zones/{cloudflare_zone_identifier}/dns_records?name={domain_name}'
    response = requests.get(
        url=identifier_url,
        headers=headers
    )
    
    # Check if the request was successful
    if response.status_code not in [200, 201]:
        # Handle errors
        print(f"Failed to update data: {response.status_code}, {response.text}")
    
    data = response.json()

    # Access the 'id' of the first item in 'result'
    try:
        identifier = data['result'][0]['id'].replace('"','')
    except (KeyError, IndexError, TypeError):
        print("error")
    
    put_url = f'https://api.cloudflare.com/client/v4/zones/{cloudflare_zone_identifier}/dns_records/{identifier}'
    put_data = {
        "Content": hostname,
        "name": domain_name,
        "type": "CNAME",
        "proxied": False
    }
    response = requests.put(
        url=put_url,
        headers=headers,
        data=put_data
    )
    
    # Check if the request was successful
    if response.status_code not in [200, 201]:
        # Handle errors
        print(f"Failed to update data: {response.status_code}, {response.text}")
    
    return {
        'statusCode': 200,
        'body': json.dumps('Success')
    }
