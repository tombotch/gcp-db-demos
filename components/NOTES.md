### Cloud Build runs under default compute vm service account

Some demos require cloud build, and it seems that invoking cloud build through
gcloud results in cloud build running under the default compute account,
even if another service account is configured in cloud build settings.

Instead of a demo-specific or client VM specific SA with appropriate roles, 
it makes more sense to just use default compute vm SA for instance(s) and assign required roles to the default compute vm SA.

Demos should be run in separate projects, so this should not be an issue, but
users need to be careful about how the vms are configured.

We might/will run into dependency issue if/when multiple demos require the same
permissions.


### Terraform does not run destroy provisioners when resources are removed from active config

Destroy provisioner like the one below will only be executed on terraform destroy,
but not on configuration change applied through terraform apply.

This limits the ability to destroy resources just by changing the active configuration.

At the time of this writing there is a new feature in TF beta which whould support this throught "remove", something to look into going forward: https://github.com/hashicorp/terraform/pull/35230
 

resource "null_resource" "cymbal_air_demo_exec_db_script" {
  triggers = {
    instance_ip     = "${google_alloydb_instance.primary_instance.ip_address}"
    password        = var.alloydb_password
    region          = var.region
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<EOT
      gcloud compute ssh alloydb-client --zone=${self.triggers.region}-a \
      --tunnel-through-iap --command='export PGHOST=${self.triggers.instance_ip}
      export PGUSER=postgres
      export PGPASSWORD=${self.triggers.alloydb_password}
      psql -c 'DROP DATABASE assistantdemo'
    EOT
  }
}
