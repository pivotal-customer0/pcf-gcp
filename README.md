# customer[0]: PCF on GCP

Create a new [GCP project](https://console.cloud.google.com/iam-admin/projects)  
Enable the [Compute API](https://console.cloud.google.com/apis/api/compute_component) on the project  
Download and install the [gcloud cli](https://cloud.google.com/sdk/docs/quickstarts)  
Download and install [terraform](https://www.terraform.io/downloads.html)  

```
git clone https://github.com/pivotal-customer0/pcf-gcp
cd pcf-gcp/terraform/pcf

export projectid=REPLACE_WITH_YOUR_PROJECT_ID
export region=us-east1
export zone=us-east1-c

gcloud auth login
gcloud config set project ${projectid}
gcloud config set compute/zone ${zone}
gcloud config set compute/region ${region}

gcloud iam service-accounts create terraform-bosh
gcloud iam service-accounts keys create terraform-bosh.key.json --iam-account terraform-bosh@${projectid}.iam.gserviceaccount.com
gcloud projects add-iam-policy-binding ${projectid} \
    --member serviceAccount:terraform-bosh@${projectid}.iam.gserviceaccount.com \
    --role roles/editor
    
export GOOGLE_CREDENTIALS=$(cat terraform-bosh.key.json)

Update variables.tf.sample and move to variables.tf

terraform plan
terraform apply
```
