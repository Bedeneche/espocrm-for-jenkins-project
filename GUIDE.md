# EspoCRM DevOps Project - Step-by-step Guide

Flow: GitHub -> Jenkins (build + test) -> Docker Hub -> Ansible -> 2 EC2 nodes running EspoCRM + MySQL

## 0. Prerequisites
- AWS CLI configured (`aws configure`), Terraform >= 1.5, Git, a Docker Hub account.
- EC2 key pair already exists in AWS (name `serverkey`) and you have `serverkey.pem` locally.

## 1. Fork the EspoCRM repo and add these files
1. Fork https://github.com/espocrm/espocrm.git to your GitHub, clone your fork.
2. Copy into the root of the fork: `Dockerfile`, `.dockerignore`, `docker-compose.yml`, `Jenkinsfile`,
   `terraform/`, `ansible/`, `scripts/`, `.gitignore`.
3. Edit `Jenkinsfile` (`DOCKERHUB_USER`) and `ansible/deploy.yml` (`app_image`, DB passwords).
4. Commit and push.

## 2. (Optional) Test the image locally
    docker compose up -d --build      # http://localhost:8080 , DB host = db
If the grunt build step in the Dockerfile fails, read the error: the repo's build
instructions are at https://docs.espocrm.com/development/ .

## 3. Provision with Terraform
    cd terraform
    cp terraform.tfvars.example terraform.tfvars    # set my_ip_cidr = "x.x.x.x/32"
    terraform init
    terraform plan
    terraform apply
Creates: 1 controller (Ubuntu 26.04, t3.large, 15 GB) + 2 nodes (Ubuntu 24.04, t3.micro, 8 GB),
security groups, and writes the real private IPs into `ansible/inventory.ini`.
Wait ~5 minutes for the install script on the controller to finish.

## 4. Connect to the controller
    chmod 400 serverkey.pem
    ssh -i serverkey.pem ubuntu@<controller_public_ip>
    sudo tail -f /var/log/install_tools.log      # wait for "install complete"
    java -version; docker --version; ansible --version; systemctl status jenkins

## 5. Put the SSH key where Ansible and Jenkins can use it
From your PC:
    scp -i serverkey.pem serverkey.pem ubuntu@<controller_public_ip>:/home/ubuntu/
On the controller:
    mkdir -p ~/.ssh && mv ~/serverkey.pem ~/.ssh/ && chmod 400 ~/.ssh/serverkey.pem
    sudo mkdir -p /var/lib/jenkins/.ssh
    sudo cp ~/.ssh/serverkey.pem /var/lib/jenkins/.ssh/
    sudo chown -R jenkins:jenkins /var/lib/jenkins/.ssh && sudo chmod 700 /var/lib/jenkins/.ssh
    sudo chmod 400 /var/lib/jenkins/.ssh/serverkey.pem

## 6. Test Ansible manually
    git clone <your-fork-url> && cd espocrm/ansible     # commit the generated inventory.ini first
    ansible all -m ping
    ansible-playbook deploy.yml -e app_image=<dockerhub-user>/espocrm -e app_tag=latest
(The first manual run needs an image already pushed to Docker Hub - or just let Jenkins do it.)

## 7. Set up Jenkins
1. Open http://<controller_public_ip>:8080, get the password:
   `sudo cat /var/lib/jenkins/secrets/initialAdminPassword`.
2. Install suggested plugins, create admin user.
3. Manage Jenkins -> Credentials -> Global -> Add: *Username with password*, ID = `dockerhub-creds`
   (Docker Hub username + access token).
4. New Item -> Pipeline -> "Pipeline script from SCM" -> Git -> your fork URL -> branch `master`
   (or `main`) -> Script Path `Jenkinsfile`.
   (Private fork? add GitHub credentials too.)
5. Build Now.

## 8. Open EspoCRM
http://<node_public_ip>  (port 80) -> run the installer wizard:
- DB host: `espocrm-db`  - DB name/user/password: the values in `deploy.yml`.
Do both nodes separately (each has its own MySQL).

## 9. Automate builds on push (optional)
GitHub repo -> Settings -> Webhooks -> `http://<controller_ip>:8080/github-webhook/`
(open port 8080 to GitHub or use "Poll SCM"), and tick "GitHub hook trigger" in the job.
Note: the controller SG only allows port 8080 from your IP; poll SCM (`H/5 * * * *`) is simpler.

## 10. Clean up (avoid AWS charges)
    cd terraform && terraform destroy

## Security notes
- Change the DB passwords; move them to `ansible-vault` for anything beyond a lab.
- Never commit `*.pem`, `terraform.tfvars` or `terraform.tfstate` (already in .gitignore).
- Your IP changes? Update `my_ip_cidr` and re-run `terraform apply`.
