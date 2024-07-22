# AlloyDB Demos

## Prerequisites

* **Google Cloud Platform (GCP) account**
* **(Linux) shell environment:** Bash or similar
* **gcloud CLI:** Installed, configured, and authenticated
* **Terraform client:** Installed
* **Active GCP project:** This project is only used to enable billing APIs for Terraform automation. No resources are intentionally deployed here.
* **Cloud Shell (optional):** A suitable environment, but configuration might differ slightly


## Getting Started

1. **Clone this repository.**
2. **Navigate to the `alloydb` directory.**
3. **Run `chmod +x deploy.sh` to make the deployment script executable.**
4. **Execute `./deploy.sh` to view available demos.**


## Available Demos

### alloydb-base

This demo creates a foundational AlloyDB environment:

* Separate project
* Network
* AlloyDB cluster
* AlloyDB primary instance
* AlloyDB client VM

This provides a quick way to set up AlloyDB but doesn't include additional features.

### alloydb-trial

This demo creates a foundational AlloyDB [free trial environment](https://cloud.google.com/alloydb/docs/free-trial-cluster), similar to the base one.

See the walkthrough here:


[![](https://img.youtube.com/vi/mJ8F4v9y9Nk/0.jpg)](https://www.youtube.com/watch?v=mJ8F4v9y9Nk)


### cymbal-air

This demo builds upon `alloydb-base` and implements the demo described [here](https://codelabs.developers.google.com/codelabs/genai-db-retrieval-app) (source code: [https://github.com/GoogleCloudPlatform/genai-databases-retrieval-app](https://github.com/GoogleCloudPlatform/genai-databases-retrieval-app)). It will:

* Deploy the database schema
* Configure, build, and deploy the middleware in Cloud Run
* Configure the frontend app

#### Manual Steps Required

After the initial deployment, you **must** manually create an OAuth client as described [here](https://codelabs.developers.google.com/codelabs/genai-db-retrieval-app#7). Skip the OAuth consent screen and proceed directly to creating the OAuth client.

Once created, return to your shell and run `./deploy.sh cymbal-air` again to continue. You will be prompted for the client ID.

After deployment, use `./cymbal-air-start.sh` to start the frontend app, which will be mapped to `localhost:8081`.

**Note:** When using Cloud Shell, follow the instructions [here](https://codelabs.developers.google.com/codelabs/genai-db-retrieval-app#connecting-from-cloud-shell) for OAuth configuration.



## Additional Commands

* `detach`: Moves the current configuration to `./deployments/project_id` for independent management. This allows running multiple demos (in different projects) concurrently.
* `clean`: Runs `terraform destroy` to clean up the folder (but not delete it) and remove all resources.

**Warning:** Sometimes `terraform destroy` might fail (e.g., Cloud Run reserving an unreleased IP). In such cases, wait for about an hour and then retry manually.

## Troubleshooting

If your configuration becomes corrupted, try the following:

1. Run `terraform destroy` in the `tf` folder or `./deployments/project_id` (if detached).
2. If that fails, remove the billing account from the project in the Google Cloud Console and schedule the project for deletion.

**Important:** If you don't remove the billing account, resources might remain active for 30 days and you could incur charges.


# Disclaimer

This repository and the scripts contained within are provided as-is. Neither Google nor the authors are responsible for any costs or damages incurred through the use of these scripts. Users are responsible for understanding the potential impact of running these scripts on their Google Cloud Platform projects and associated billing!
