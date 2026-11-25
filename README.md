# Terraform Website on EC2

SEIS 616 Terraform homework. This configuration builds a small website in AWS:

```
Browser ──► Load balancer ──► seis616-web-1 (us-east-1a) ──┐
                         └──► seis616-web-2 (us-east-1b) ──┴──► MySQL database
```

- **Network:** one public and one private subnet in each of two Availability Zones.
- **Web servers:** one in each public subnet. Their names come from the input variables `instance1_name` and `instance2_name`, set in `terraform.tfvars`. They allow port 80 from anywhere.
- **Database:** MySQL in the private subnets. It allows port 3306 only from the web servers.
- **Load balancer:** sends visitors to both web servers.

Everything is in `main.tf`. The variables are in `variables.tf` and the outputs are in `outputs.tf`.

## Deploy

```bash
export AWS_PROFILE=<your-profile>
terraform init
terraform apply
```

Type `yes` when asked. It takes about 6 minutes. At the end it prints the outputs: each web server's public IP, the load balancer's address (`alb_url`), and the database endpoint.

<img src="screenshots/1-apply-outputs.png" alt="terraform apply complete with the instance public IPs, load balancer address, and RDS endpoint" width="700">

## Verify

1. **VPC → Subnets:** four subnets, a public and a private one in each of us-east-1a and us-east-1b.

   <img src="screenshots/2-subnets.png" alt="Four seis616-tf subnets, a public and a private one in each of us-east-1a and us-east-1b" width="700">

2. **EC2 → Instances:** `seis616-web-1` and `seis616-web-2` are running, one in each Availability Zone. These names come from `terraform.tfvars`.

   <img src="screenshots/3-instances.png" alt="seis616-web-1 in us-east-1a and seis616-web-2 in us-east-1b, both running" width="700">

3. **EC2 → Security Groups:** `seis616-tf-web-sg` allows port 80 from `0.0.0.0/0`. `seis616-tf-db-sg` allows port 3306 only from `seis616-tf-web-sg`.

   <img src="screenshots/4-web-sg.png" alt="Web server security group: HTTP port 80 from 0.0.0.0/0" width="700">

   <img src="screenshots/5-db-sg.png" alt="Database security group: MySQL port 3306 from the web server security group only" width="700">

4. **Database:** the RDS console doesn't show these settings together, so check them in the terminal. The database is MySQL, not publicly accessible, and uses the two private subnets.

   ```bash
   aws rds describe-db-instances --db-instance-identifier seis616-tf-mysql \
     --query 'DBInstances[0].{Engine:Engine,Version:EngineVersion,Status:DBInstanceStatus,PubliclyAccessible:PubliclyAccessible,Subnets:DBSubnetGroup.Subnets[].[SubnetIdentifier,SubnetAvailabilityZone.Name]}'
   ```

   <img src="screenshots/6-rds.png" alt="RDS: mysql 8.4.11, available, not publicly accessible, in the two private subnets" width="700">

5. **Browser:** open `alb_url` + `/index.php`. It shows "Hi, I'm instance" and a server ID. Refresh and the ID changes, which shows the load balancer is using both servers.

   <img src="screenshots/7-browser-web2.png" alt="Browser showing seis616-web-2's instance ID through the load balancer" width="700">

   <img src="screenshots/8-browser-web1.png" alt="Browser showing seis616-web-1's instance ID through the load balancer" width="700">

## Tear down

```bash
terraform destroy
```

Type `yes` when asked.

<img src="screenshots/9-destroy.png" alt="terraform destroy complete, 33 resources destroyed" width="700">
