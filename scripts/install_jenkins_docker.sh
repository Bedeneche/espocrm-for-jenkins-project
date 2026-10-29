#!/bin/bash
# Runs as root via EC2 user_data on the controller (Ubuntu 26.04).
# Installs: Java 21, Jenkins, Docker, Git, Ansible.
# Log: /var/log/install_tools.log
set -euxo pipefail
exec > >(tee -a /var/log/install_tools.log) 2>&1
export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get install -y ca-certificates curl gnupg git unzip fontconfig openjdk-21-jre-headless
java -version

# ---------- Jenkins (LTS repo) ----------
# Jenkins rotates its repo signing key; fetch current + previous key into one keyring.
install -d -m 0755 /etc/apt/keyrings
: > /etc/apt/keyrings/jenkins-keyring.asc
for y in 2026 2023; do
  curl -fsSL "https://pkg.jenkins.io/debian-stable/jenkins.io-${y}.key" >> /etc/apt/keyrings/jenkins-keyring.asc || true
  echo >> /etc/apt/keyrings/jenkins-keyring.asc
done
echo "deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" \
  > /etc/apt/sources.list.d/jenkins.list
apt-get update -y
apt-get install -y jenkins

# ---------- Docker ----------
apt-get install -y docker.io
apt-get install -y docker-compose-v2 docker-buildx || true
systemctl enable --now docker

# let Jenkins (and ubuntu) run docker
usermod -aG docker jenkins
usermod -aG docker ubuntu

# ---------- Ansible (controller role) ----------
apt-get install -y ansible
ansible-galaxy collection install community.docker -p /usr/share/ansible/collections || true

# ---------- Start Jenkins ----------
systemctl daemon-reload
systemctl enable jenkins
systemctl restart jenkins   # restart so the docker group is picked up

# wait for the initial admin password and log it
for i in $(seq 1 60); do
  [ -f /var/lib/jenkins/secrets/initialAdminPassword ] && break
  sleep 5
done
echo "=== Jenkins initial admin password ==="
cat /var/lib/jenkins/secrets/initialAdminPassword || true
echo "=== install complete ==="
