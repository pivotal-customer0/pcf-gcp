#!/bin/bash

# Setup env's
export sys_domain=sys.dwallraffcloud.com
export projectid=google.com:pcf-demos
export region=us-east1
export zone=us-east1-c
gcloud config set project ${projectid}
gcloud config set compute/zone ${zone}
gcloud config set compute/region ${region}

# Create networks
gcloud compute networks create vnet --mode custom
gcloud compute networks subnets create bosh --network vnet --range 10.0.0.0/24
gcloud compute networks subnets create concourse-public --network vnet --range 10.0.3.0/24
gcloud compute networks subnets create concourse-private --network vnet --range 10.0.2.0/24
gcloud compute networks subnets create cf-private --network vnet --range 10.0.16.0/22
gcloud compute networks subnets create cf-public --network vnet --range 10.0.15.0/24

# Add some firewall rules
gcloud compute firewall-rules create cf-public --network vnet --source-ranges 0.0.0.0/0 --target-tags cf-public --allow tcp:80,tcp:443,tcp:2222,tcp:4443
gcloud compute firewall-rules create nat-traverse --network vnet --source-tags nat-traverse --target-tags nat-traverse --allow tcp,udp,icmp
gcloud compute firewall-rules create allow-ssh --network vnet --source-ranges 0.0.0.0/0 --target-tags allow-ssh --allow tcp:22
gcloud compute firewall-rules create concourse --network vnet --source-ranges 0.0.0.0/0 --target-tags concourse-public --allow tcp:8080

# Get some public IPs
gcloud compute addresses create cf-public-ip
gcloud compute addresses create concourse-public-ip
cf_address=$(gcloud compute addresses describe cf-public-ip | grep ^address: | cut -f2 -d' ')
concourse_address=$(gcloud compute addresses describe concourse-public-ip | grep ^address: | cut -f2 -d' ')

# CF load balancing
gcloud compute http-health-checks create cf-public --timeout "5s" --check-interval "30s" --healthy-threshold "10" --unhealthy-threshold "2" --port 80 --request-path "/v2/info" --host "api.${sys_domain}"
gcloud compute target-pools create cf-public --health-check cf-public
gcloud compute forwarding-rules create cf-http --ip-protocol TCP --ports 80 --address ${cf_address} --target-pool cf-public
gcloud compute forwarding-rules create cf-https --ip-protocol TCP --ports 443 --address ${cf_address} --target-pool cf-public
gcloud compute forwarding-rules create cf-ssh --ip-protocol TCP --ports 2222 --address ${cf_address} --target-pool cf-public
gcloud compute forwarding-rules create cf-wss --ip-protocol TCP --ports 4443 --address ${cf_address} --target-pool cf-public

# Concourse load balancing
gcloud compute http-health-checks create concourse-public --timeout "5s" --check-interval "30s" --healthy-threshold "10" --unhealthy-threshold "2" --port 8080
gcloud compute target-pools create concourse-public --health-check concourse-public
gcloud compute forwarding-rules create concourse-http --ip-protocol TCP --ports 8080 --address ${concourse_address} --target-pool concourse-public
gcloud compute forwarding-rules create concourse-https --ip-protocol TCP --ports 4443 --address ${concourse_address} --target-pool concourse-public

gcloud compute instances create bosh-bastion --subnet bosh --image-family ubuntu-1404-lts --image-project ubuntu-os-cloud --private-network-ip 10.0.0.10 --tags allow-ssh,nat-traverse --scopes cloud-platform --metadata startup-script="apt-get update -y
apt-get upgrade -y
apt-get install -y build-essential zlibc zlib1g-dev ruby ruby-dev openssl libxslt-dev libxml2-dev libssl-dev libreadline6 libreadline6-dev libyaml-dev libsqlite3-dev sqlite3
gem install bosh_cli
curl -o /tmp/cf.tgz https://s3.amazonaws.com/go-cli/releases/v6.19.0/cf-cli_6.19.0_linux_x86-64.tgz
tar -zxvf /tmp/cf.tgz && mv cf /usr/bin/cf && chmod +x /usr/bin/cf
curl -o /usr/bin/bosh-init https://s3.amazonaws.com/bosh-init-artifacts/bosh-init-0.0.94-linux-amd64
chmod +x /usr/bin/bosh-init"

gcloud compute instances create nat-gateway --subnet bosh --can-ip-forward --image-family ubuntu-1404-lts --image-project ubuntu-os-cloud --tags allow-ssh,nat-traverse --metadata startup-script="sudo sh -c 'echo 1 > /proc/sys/net/ipv4/ip_forward'
sudo iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE"

# Create route to nat-gateway
gcloud compute routes create no-ip-internet-route --network vnet --destination-range 0.0.0.0/0 --next-hop-instance nat-gateway --tags no-ip --priority 800

sleep 30

gcloud compute ssh bosh-bastion --command "zone=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/zone) && \
zone=${zone##*/} && \
region=${zone%-*} && \
gcloud config set compute/zone ${zone} && \
gcloud config set compute/region ${region} && \

ssh-keygen -t rsa -f ~/.ssh/bosh -C bosh -N '' && \
sed '1s/^/bosh:/' ~/.ssh/bosh.pub > ~/.ssh/bosh.pub.gcp && \
gcloud compute project-info add-metadata --metadata-from-file sshKeys=~/.ssh/bosh.pub.gcp"
