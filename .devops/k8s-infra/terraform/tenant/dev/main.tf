


#------------------------------------------------------

# module "vpc" {
#   source              = "../../modules/vpc"
#   name                = "capstone"
#   vpc_cidr            = "10.0.0.0/16"
#   public_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
#   azs                 = ["us-east-1a", "us-east-1b", "us-east-1c"]
# }

module "master" {
  source             = "../../modules/ec2"
  name               = "k8s-master-node"
  ami                = "ami-020cba7c55df1f615" # us-east-1 Canonical, Ubuntu, 24.04, amd64 noble image
  instance_type      = "t3a.medium"
  subnet_id          = "subnet-0b78db19a655d84fd" #module.vpc.public_subnet_ids[0]
  vpc_id             = "vpc-01576a488cbfb349b"    #module.vpc.vpc_id
  key_name           = aws_key_pair.generated_key.key_name # "devops-keypem-va"
  security_group_ids = aws_security_group.ec2_sg.id
  user_data          = file("${path.module}/scripts/master_user_data.sh")

  NodeName    = "kube-master"
  Project     = "tera-kube-ans"
  NodeRole    = "master"
  NodeId      = "1"
  environment = "dev"

}

module "worker_1" {
  source             = "../../modules/ec2"
  name               = "k8s-worker1-node"
  ami                = "ami-020cba7c55df1f615" # us-east-1 Canonical, Ubuntu, 24.04, amd64 noble image
  instance_type      = "t3a.medium"
  subnet_id          = "subnet-0422d59cc6615b3f7" #module.vpc.public_subnet_ids[1]
  vpc_id             = "vpc-01576a488cbfb349b"    #module.vpc.vpc_id
  key_name           = aws_key_pair.generated_key.key_name # "devops-keypem-va"
  security_group_ids = aws_security_group.ec2_sg.id
  user_data          = file("${path.module}/scripts/worker1_user_data.sh")
  depends_on         = [module.master]

  NodeName    = "worker-1"
  Project     = "tera-kube-ans"
  NodeRole    = "worker"
  NodeId      = "1"
  environment = "dev"

}

module "worker_2" {
  source             = "../../modules/ec2"
  name               = "k8s-worker2-node"
  ami                = "ami-020cba7c55df1f615" # us-east-1 Canonical, Ubuntu, 24.04, amd64 noble image
  instance_type      = "t3a.medium"
  subnet_id          = "subnet-011f6bb6c5244e5bb" #module.vpc.public_subnet_ids[2]
  vpc_id             = "vpc-01576a488cbfb349b"    #module.vpc.vpc_id
  key_name           = aws_key_pair.generated_key.key_name # "devops-keypem-va"
  security_group_ids = aws_security_group.ec2_sg.id
  user_data          = file("${path.module}/scripts/worker2_user_data.sh")
  depends_on         = [module.worker_1]

  NodeName    = "worker-2"
  Project     = "tera-kube-ans"
  NodeRole    = "worker"
  NodeId      = "2"
  environment = "dev"


}


# -------------------------------
# Output'lar (Ansible için IP bilgileri)
# -------------------------------

# -------------------------------
# inventory.ini dosyasını oluştur
# -------------------------------
resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/ansible/inventory.ini", {
    MASTER_PUBLIC_IP  = module.master.public_ip
    WORKER1_PUBLIC_IP = module.worker_1.public_ip
    WORKER2_PUBLIC_IP = module.worker_2.public_ip
  })
  filename = "${path.module}/ansible/inventory.generated.ini"
}

# -------------------------------
# Terraform sonrası Ansible çalıştır
# -------------------------------
resource "null_resource" "join_workers" {
  depends_on = [
    module.master,
    module.worker_1,
    module.worker_2,
    local_file.ansible_inventory
  ]

  provisioner "local-exec" {
    command = "ansible-playbook -i ${path.module}/ansible/inventory.generated.ini ${path.module}/ansible/join-workers.yml"

  }
}

############# ORTAK securty group #########3


resource "aws_security_group" "ec2_sg" {
  vpc_id = "vpc-01576a488cbfb349b"
  name   = "K8S-CLUSTER-sg"
  tags = {
    Name = "K8S-CLUSTER-sg"
  }

  # ---- Master API Server ----
  ingress {
    description = "Kubernetes API Server"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # İstersen sadece kendi IP adresini koy
  }

  # ---- etcd (Master <-> Master) ----
  ingress {
    description = "etcd server client API"
    from_port   = 2379
    to_port     = 2380
    protocol    = "tcp"
    self        = true
  }

  # ---- Kubelet API ----
  ingress {
    description = "Kubelet API"
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    self        = true
  }

  # ---- kube-scheduler ----
  ingress {
    description = "kube-scheduler"
    from_port   = 10251
    to_port     = 10251
    protocol    = "tcp"
    self        = true
  }

  # ---- kube-controller-manager ----
  ingress {
    description = "kube-controller-manager"
    from_port   = 10252
    to_port     = 10252
    protocol    = "tcp"
    self        = true
  }

  # ---- kube-proxy health check ----
  ingress {
    description = "kube-proxy health check"
    from_port   = 10256
    to_port     = 10256
    protocol    = "tcp"
    self        = true
  }

  # ---- NodePort Service Range ----
  ingress {
    description = "NodePort Services"
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Opsiyonel, dış erişim gerekmiyorsa kaldır
  }

  # ---- Allow SSH ----
  ingress {
    description = "SSH Access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # İstersen kendi IP ile sınırla
  }
  ingress {
    description = "Flannel VXLAN UDP port"
    from_port   = 8285
    to_port     = 8285
    protocol    = "udp"
    self        = true
  }

  # Opsiyonel, eğer VXLAN dışında başka mod kullanıyorsan açılabilir

  ingress {
    description = "Flannel VXLAN alternative port UDP"
    from_port   = 8472
    to_port     = 8472
    protocol    = "udp"
    self        = true
  }



  # ---- Outbound trafik serbest ----
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

}

############### KEY OLUŞTUR ###########3
variable "key_name" {
  description = "AWS Key Pair Name"
  type        = string
  default     = "devops-keypem-ansible"
}



# EC2 Key Pair oluştur
resource "tls_private_key" "ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "generated_key" {
  key_name   = var.key_name
  public_key = tls_private_key.ssh_key.public_key_openssh
}

# Private key'i local makinedeki ~/.ssh klasörüne kaydet
resource "local_file" "private_key_pem" {
  content              = tls_private_key.ssh_key.private_key_pem
  filename             = pathexpand("~/.ssh/${var.key_name}.pem")
  file_permission      = "0400" # SSH için güvenli izinler
}

output "private_key_path" {
  value = pathexpand("~/.ssh/${var.key_name}.pem")
}
