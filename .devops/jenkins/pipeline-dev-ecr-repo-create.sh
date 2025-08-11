APP_REPO_NAME="cloud-repo/microservice-app-dev"
AWS_REGION="us-east-1"

# ECR var mı kontrol et, yoksa oluştur
aws ecr describe-repositories \
  --region ${AWS_REGION} \
  --repository-names ${APP_REPO_NAME} \
  >/dev/null 2>&1 || \
aws ecr create-repository \
  --repository-name ${APP_REPO_NAME} \
  --image-scanning-configuration scanOnPush=false \
  --image-tag-mutability MUTABLE \
  --region ${AWS_REGION}


# ECR registry domain'ini al (repository adı olmadan)
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
export ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

echo "ECR Registry: ${ECR_REGISTRY}"
