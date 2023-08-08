```bash
export PROJECT="nvoss-kuberay"
export REGION="europe-west4"
gsutil mb -p ${PROJECT} -l ${REGION} -b on gs://${PROJECT}-tf-state
gsutil versioning set on gs://${PROJECT}-tf-state
# Make sure terraform is able to use your credentials (only required if not already the case)
gcloud auth application-default login --project ${PROJECT}
```

__TODO__: Update tfvars

```bash
rg -l 'backend "gcs"' | xargs -I{} sed -i "s/nvoss-kuberay-tf-state/${PROJECT}-tf-state/g" {}
```


```bash
terraform -chdir=0-cluster init
terraform -chdir=0-cluster apply
```



```bash
gcloud container clusters get-credentials cluster-kuberay --region ${REGION} --project ${PROJECT}
```


```bash
terraform -chdir=1-operator init
terraform -chdir=1-operator apply
```

__NOTE__: Well runs in default namespace :D



# TODO

* Use GKE Standard cluster, create tainted node-pool for GPU workloads
* Use time-sharing and make sure node fits workload: https://cloud.google.com/kubernetes-engine/docs/concepts/timesharing-gpus
* Configure RayCluster with the correct requests and selectors: https://github.com/richardsliu/ray-on-gke/blob/main/user/modules/kuberay/kuberay-values.yaml
* Deploy a RayService and make sure autoscaling fits the time-sharing setup: https://docs.ray.io/en/master/serve/scaling-and-resource-allocation.html#ray-serve-autoscalin
* Details how to properly configure them for kuberay can be found here: https://github.com/ray-project/kuberay/blob/master/ray-operator/config/samples/ray-service.autoscaler.yaml
* A good example to illustrate the above with kuberay and autoscaling on time-shared GPUs would be: https://github.com/ray-project/kuberay/blob/master/ray-operator/config/samples/ray-service.stable-diffusion.yaml

