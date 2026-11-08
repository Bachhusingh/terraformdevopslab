bash
#!/bin/bash
set -euo pipefail
yum update -y
yum install -y docker
systemctl enable docker && systemctl start docker
curl -sfL https://get.k3s.io | sh -
mkdir -p /home/ec2-user/.kube
cp /etc/rancher/k3s/k3s.yaml /home/ec2-user/.kube/config
chown ec2-user:ec2-user /home/ec2-user/.kube/config