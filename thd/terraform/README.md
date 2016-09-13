# gcp-pcf-terraform

Initial draft of terraform templates to deploy Pivotal Cloud Foundry on GCP

## Environment Variables
```
export projectid=REPLACE_WITH_YOUR_PROJECT_ID
export region=us-central1
export zone=us-central1-a
export zone2=us-central1-b
export sysdomain="<system domain>"
export pivnet=<Pivotal Network Token>
export ert=<Pivotal Network Elastic Runtime API Download URL>
```

## GCloud Config
```
gcloud auth login
gcloud config set project ${projectid}
gcloud config set compute/zone ${zone}
gcloud config set compute/region ${region}
```

Make your service account's key available in an environment variable to be used by terraform. This is the same JSON file you use on Ops Manager Google tile
```
export GOOGLE_CREDENTIALS="$(cat /tmp/terraform-gcp.key.json)"
```

## Terraform 

### State

```
terraform state --state=central/gcp_central.tfstate -var projectid=${projectid} -var region=${region} -var zone=${zone} -var zone-2=${zone2} -var sys-domain=${sysdomain} -var pivnet=${pivnet} -var ert=${ert}
```
### Apply

```
terraform apply --state=central/gcp_central.tfstate -var projectid=${projectid} -var region=${region} -var zone=${zone} -var zone-2=${zone2} -var sys-domain=${sysdomain} -var pivnet=${pivnet} -var ert=${ert}
```

### Destroy 

```
terraform destroy --state=central/gcp_central.tfstate -var projectid=${projectid} -var region=${region} -var zone=${zone} -var zone-2=${zone2} -var sys-domain=${sysdomain} -var pivnet=${pivnet} -var ert=${ert}
```

