# `kuberay-example`

Before starting make sure `gcloud` and `terraform` are installed and create a new project with billing set up.

## Bucket for terraform-state

```bash
export PROJECT="nvoss-kuberay-demo"
export REGION="europe-west4"
gsutil mb -p ${PROJECT} -l ${REGION} -b on gs://${PROJECT}-tf-state
gsutil versioning set on gs://${PROJECT}-tf-state
# Make sure terraform is able to use your credentials (only required if not already the case)
gcloud auth application-default login --project ${PROJECT}
```

## Update terraform-variables

Update all *.tfvars files and make sure the state is saved to your bucket:
```bash
rg -l 'backend "gcs"' | xargs -I{} sed -i "s/nvoss-kuberay-demo-tf-state/${PROJECT}-tf-state/g" {}
```

## Create the GKE cluster and node-pools

```bash
terraform -chdir=0-cluster init
terraform -chdir=0-cluster apply
```

## Duplicate images
CLOUD SHELL!
```bash
docker pull rayproject/ray:2.7.1-py310
docker tag rayproject/ray:2.7.1-py310 ${REGION}-docker.pkg.dev/${PROJECT}/images/ray:2.7.1-py310
docker push ${REGION}-docker.pkg.dev/${PROJECT}/images/ray:2.7.1-py310
# On cloud shell space might not be sufficient, so before pulling gpu image, let's clean up
docker rmi rayproject/ray:2.7.1-py310
docker rmi ${REGION}-docker.pkg.dev/${PROJECT}/images/ray:2.7.1-py310
docker pull rayproject/ray:2.7.1-py310-gpu
docker tag rayproject/ray:2.7.1-py310-gpu ${REGION}-docker.pkg.dev/${PROJECT}/images/ray:2.7.1-py310-gpu
docker push ${REGION}-docker.pkg.dev/${PROJECT}/images/ray:2.7.1-py310-gpu
docker rmi rayproject/ray:2.7.1-py310-gpu
docker rmi ${REGION}-docker.pkg.dev/${PROJECT}/images/ray:2.7.1-py310-gpu
```

__NOTE__: Checkout `0-cluster/main.tf` for the particular node-pool configurations and how [time-sharing](https://cloud.google.com/kubernetes-engine/docs/concepts/timesharing-gpus) of GPUs is set up.

## Install the `kuberay-operator`
```bash
terraform -chdir=1-kuberay init
terraform -chdir=1-kuberay apply
```

## Create a Workbench Instance

https://cloud.google.com/vertex-ai/docs/workbench/instances/introduction

__NOTE__: For simplicity we just use the `default`-namespace...
## Create an example `RayService`

Get credentials for the GKE cluster:
```bash
gcloud container clusters get-credentials demo-cluster --region ${REGION} --project ${PROJECT}
```

Create the example stable-diffusion `RayService`:
```bash
kubectl apply -f ray-service.yaml
kubectl describe rayservices
```

To access the dashboard you can port-forward as follows:
```bash
kubectl port-forward svc/stable-diffusion-head-svc --address 0.0.0.0 8265:8265
```

To send a test-request forward the `serve-svc` and do HTTP requests as follows:
```bash
kubectl port-forward svc/stable-diffusion-serve-svc 8000
curl http://127.0.0.1:8000/imagine\?prompt=a+yellow+car+with+six+wheels > example.png
```

## Final thoughts:

* The example here is not fine-tuned: Make sure the ray worker group and your workload scale well with the chosen machine-type and time-shared GPU.
* Before scaling out in a single region consider adding a second zone to your node-pool. For independent scaling of zones a second node-pool is also an option.
* Consider persisting logs: https://docs.ray.io/en/latest/cluster/kubernetes/user-guides/logging.html
* We intentionally use Ubuntu rather than COS as Ray's default images seem to have issues with non-Debian host-OSs.
* Ray's images are fairly big (~10GB), consider duplicating them to artifact registry to benefit from image streaming: https://cloud.google.com/kubernetes-engine/docs/how-to/image-streaming
