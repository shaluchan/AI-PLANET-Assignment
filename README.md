# Prefect Worker on ECS with Self-Hosted Prefect Server (EC2)

## 📌 Overview
This project demonstrates deploying a **Prefect server (Orion)** on an **EC2 instance** and running a **Prefect worker on ECS (Fargate)** using **Terraform**.

Since **Prefect Cloud Free Plan** does not allow ECS workers (pull pools), the solution was to **self-host the Prefect server** and connect workers to it.

---

## 🚀 Architecture
1. **VPC** with public/private subnets, Internet Gateway, and NAT Gateway.  
2. **EC2 instance** running Prefect server (Orion).  
3. **ECS cluster** with a worker task definition.  
4. **IAM roles** for ECS tasks (execution + secrets access).  
5. **AWS Secrets Manager** to securely store EC2 INSTANCE IP.  
6. **CloudWatch logs** for debugging worker tasks.  

---

## 🛠 Prerequisites
- AWS Account  
- Terraform installed (`>=1.5`)  
- AWS CLI configured (`aws configure`)  
- Prefect installed locally (`pipx install prefect` or `pip install prefect`)  

---


---

## ⚙️ Steps

### 1. Clone the Repo
```bash
git clone <repo-url>
cd AI-PLANET ASSIGNMENT
```

### 2. Launch Prefect Server on EC2
- Spin up an **Ubuntu EC2 instance** in the VPC public subnet.  
- Install Prefect:
  ```bash
  sudo apt update
  sudo apt install python3-pip -y
  pip install prefect
  ```
- Start Prefect Orion server:
  ```bash
  prefect server start --host 0.0.0.0
  ```
- Open **port 4200** in EC2 security group to allow access.  
- Verify in browser:  
  ```
  http://<EC2-Public-IP>:4200
  ```

### 3.Configure Secrets
 Store EC2 instance public IP in AWS Secrets manager as ec2.


### 4. Terraform Init & Apply
```bash
terraform init
terraform plan
terraform apply -auto-approve
```

This provisions:
- VPC, subnets, routes, gateways  
- ECS cluster (`prefect-cluster`)  
- Worker service (`prefect-worker-svc`) connected to EC2-hosted server  


---

## ✅ Verification
1. **Prefect UI** → Visit `http://<EC2-Public-IP>:4200` and confirm the server is running.  
2. **ECS Console** → Worker task should show `RUNNING`.  
3. **CloudWatch Logs** → Logs should confirm:
   ```
   Worker 'dev-worker' started!
   Connected to self-hosted Prefect server.
   ```
 4. check on self hosted prefecct cloud ur work pool and dev-worker is created and showing.

---

## ⚡ Challenges & Learnings
- **Free Prefect Cloud Limitation:** Pull-based workers (ECS/K8s) aren’t supported on free tier.  
- **Solution:** Host Prefect Orion on EC2 and connect ECS worker.  
- **Debugging:** CloudWatch logs were essential for identifying issues (401 Unauthorized, worker exit).  

---

## 💡 Improvements
- Add **ECS Auto Scaling** for worker count.  
- Use **ALB** to expose Prefect server with HTTPS.  
- Configure **Prometheus/Grafana** for monitoring.  
- CI/CD with GitHub Actions to automate Terraform deploys.  

---

## ✅ Conclusion
This project successfully demonstrates deploying a **Prefect worker on ECS** connected to a **self-hosted Prefect Orion server on EC2** using Terraform.

Even though Prefect Cloud Free limited ECS integration, the **EC2-hosted server approach** enabled a working solution and provided valuable hands-on learning in **IaC, AWS ECS, networking, IAM, and Prefect orchestration**.
