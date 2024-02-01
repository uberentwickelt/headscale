#!/bin/bash
# The following are all handled by cloud-config in the launch template before launching this script
## apt caches update
## apt upgrades
## package installation

# Functions
function get_parameter {
    echo "$(aws ssm get-parameter --name ${1} --with-decryption --query "Parameter.Value" --output text)"
}

app_name="headscale"

# Main
# Get parameters
acme_email=$(get_parameter "${app_name}_acme_email")
#cf_key=$(get_parameter "${app_name}_cloudflare_key")
domain_name=$(get_parameter "${app_name}_domain_name")
headscale_bucket=$(get_parameter "${app_name}_bucket")
headscale_version=$(get_parameter "${app_name}_version")
#zone_identifier=$(get_parameter "${app_name}_cloudflare_zone_identifier")

# Get headscale debian package file, and install headscale
curl -Lo headscale.deb "https://github.com/juanfont/headscale/releases/download/v${headscale_version}/headscale_${headscale_version}_linux_arm64.deb"
dpkg -i headscale.deb

# Pull in headscale config file, certificates, database, and keys from s3
for dir in "/etc" "/usr/local/bin" "/var/lib/headscale"; do
  aws s3 cp s3://${headscale_bucket}${dir} ${dir}/ --recursive
done

# Ensure correct file ownership and permissions
chown -R headscale:headscale /var/lib/headscale/* /etc/headscale/key.pem
chown -R root:root /etc/cron.d/* /usr/local/bin/*
chmod -R 0600 /var/lib/headscale/* /etc/headscale/key.pem /etc/cron.d/*
chmod 0700 /var/lib/headscale/cache /usr/local/bin/backup.sh

# Update domain name and acme_email in headscale config
sed -i "s/^\ \ server_url:.*$/  server_url: https:\/\/${domain_name}/g" /etc/headscale/config.yaml
sed -i "s/^\ \ acme_email:.*$/  acme_email: \"${acme_email}\"/g" /etc/headscale/config.yaml
sed -i "s/^\ \ tls_letsencrypt_hostname:.*$/  tls_letsencrypt_hostname: \"${domain_name}\"/g" /etc/headscale/config.yaml

### Update the CNAME record in cloudflare
#identifier=$(curl -fsSL --request GET --url "https://api.cloudflare.com/client/v4/zones/${zone_identifier}/dns_records?name=${domain_name}" --header 'Content-Type: application/json' --header "Authorization: Bearer $cf_key"|jq ".result[0].id"|sed 's/"//g')
#data='{"content":"'$(ec2-metadata --public-hostname|awk '{print $2}')'","name": "'${domain_name}'","type": "CNAME","proxied": false}'
#curl --request PUT --url "https://api.cloudflare.com/client/v4/zones/${zone_identifier}/dns_records/${identifier}" --header 'Content-Type: application/json' --header "Authorization: Bearer ${cf_key}" --data "${data}"
aws lambda invoke --function-name "${app_name}_update_dns" --payload '{ "hostname": "$(ec2-metadata --public-hostname|awk '{print $2}')" }' --cli-binary-format raw-in-base64-out /dev/null

# Backup changes to the following files (keys) when/if changes are made
# Do NOT backup the db.sqlite database file based on "changes" with inotify
### db.sqlite is updated nearly every second by headscale
### this is necessary for the functioning of headscale, but if we back it up
### every time it changes, and s3 versioning is on, it will be costly.
# Instead, we will backup this file on a regular schedule with cron
### This is accomplished by dropping a file in /etc/cron.d with the s3 cp
### command above that pulls in all of /etc recursively.
inotify-hookable -f /var/lib/headscale/noise_private.key -c "aws s3 cp /var/lib/headscale/noise_private.key s3://${headscale_bucket}/var/lib/headscale/" &
inotify-hookable -f /var/lib/headscale/private.key -c "aws s3 cp /var/lib/headscale/private.key s3://${headscale_bucket}/var/lib/headscale/" &
inotify-hookable -f /var/lib/headscale/cache/acme_account+key -c "aws s3 cp /var/lib/headscale/cache/acme_account+key s3://${headscale_bucket}/var/lib/headscale/cache/" &
inotify-hookable -f /var/lib/headscale/cache/${domain_name} -c "aws s3 cp /var/lib/headscale/cache/${domain_name} s3://${headscale_bucket}/var/lib/headscale/cache/" &

# Enable headscale at boot and start it now
systemctl enable --now headscale

# Get and install ssm agent (required for dynamically updating configuration files when they are uploaded to s3)
curl -Lo amazon-ssm-agent.deb https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/debian_arm64/amazon-ssm-agent.deb
dpkg -i amazon-ssm-agent.deb
systemctl enable --now amazon-ssm-agent

# Cleanup
#cf_key=""
#data=""
domain_name=""
headscale_bucket=""
headscale_version=""
#identifier=""
#zone_identifier=""
unset cf_key
#unset data
unset domain_name
unset headscale_bucket
unset headscale_version
#unset identifier
#unset zone_identifier
rm -f ./*.deb /tmp/setup.sh
