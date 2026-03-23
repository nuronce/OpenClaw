# AWS Setup

This repo can be deployed with one CloudFormation foundation stack. Choose whether the stack should create its own public network layout or launch into an existing VPC and subnet.

Set your target region before running the commands below:

```bash
export AWS_REGION=<your-region>
```

Or pass `--region <your-region>` explicitly to each AWS CLI command.

## 1. Deploy the Foundation Stack

### Option A: Create a New Network Layout

```bash
aws cloudformation deploy \
  --region "${AWS_REGION}" \
  --stack-name openclaw-foundation \
  --template-file aws/openclaw-foundation.yaml \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
    NetworkMode=create \
    ResourcePrefix=OpenClaw \
    InstanceSubnetChoice=primary \
    PublicSubnetCidrAzA=10.42.10.0/24 \
    PublicSubnetCidrAzB=10.42.11.0/24 \
    InstanceType=t4g.medium \
    RootVolumeGiB=30 \
    DataVolumeGiB=100 \
    SshAccessCidr=203.0.113.10/32
```

What create mode provisions:

- VPC
- public subnet A in the first available AZ
- public subnet B in the second available AZ
- internet gateway and public route table
- a managed security group with no inbound rules by default
- optional restricted SSH ingress if `SshAccessCidr` is provided
- S3 archive bucket
- IAM EC2 role and instance profile
- EC2 instance
- attached encrypted data EBS volume

### Option B: Use an Existing VPC and Subnet

```bash
aws cloudformation deploy \
  --region "${AWS_REGION}" \
  --stack-name openclaw-foundation \
  --template-file aws/openclaw-foundation.yaml \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
    NetworkMode=existing \
    ResourcePrefix=OpenClaw \
    ExistingVpcId=vpc-0123456789abcdef0 \
    ExistingInstanceSubnetId=subnet-0123456789abcdef0 \
    ExistingSecurityGroupId=sg-0123456789abcdef0 \
    InstanceType=t4g.medium \
    RootVolumeGiB=30 \
    DataVolumeGiB=100
```

Notes for existing-network mode:

- `ExistingVpcId` and `ExistingInstanceSubnetId` are required.
- `ExistingSecurityGroupId` is optional. If omitted, the stack creates and manages one in the supplied VPC.
- `SshAccessCidr` only affects a security group created by this stack. If you supply an existing security group, manage its SSH rules separately.
- the EBS data volume is created in the launched instance AZ automatically, so no extra subnet or AZ parameter is required

## 2. Get Stack Outputs

```bash
aws cloudformation describe-stacks \
  --region "${AWS_REGION}" \
  --stack-name openclaw-foundation \
  --query "Stacks[0].Outputs[].[OutputKey,OutputValue]" \
  --output table
```

You need these outputs for later steps:

- `InstanceId`
- `ArchiveBucketNameOutput`
- `DataVolumeDeviceName`
- `InstanceSubnetId`
- `SecurityGroupId`
- `SshUser`

Create-mode deployments also expose:

- `SubnetAzAId`
- `SubnetAzBId`
- `PrimaryAvailabilityZone`
- `SecondaryAvailabilityZone`

## 3. Connect to the EC2 Host with SSM

```bash
aws ssm start-session --region "${AWS_REGION}" --target i-INSTANCE_ID
```

Optional SSH works only after both of these are in place:

- the stack allows port 22 with `SshAccessCidr`
- host bootstrap installs the public key referenced by `KEY_PAIR_NAME` in `deploy/.env`

## 4. Mount the Attached Data Volume

Use the device from stack output `DataVolumeDeviceName` (default `/dev/sdf`).

From EC2:

```bash
lsblk
sudo mkfs -t ext4 /dev/nvme1n1
sudo mkdir -p /srv/openclaw
UUID=$(sudo blkid -s UUID -o value /dev/nvme1n1)
echo "UUID=${UUID} /srv/openclaw ext4 defaults,nofail 0 2" | sudo tee -a /etc/fstab
sudo mount -a
sudo mkdir -p /srv/openclaw/app
sudo mkdir -p /var/log/openclaw/archive
```

If `lsblk` shows a different NVMe device name for the attached volume, use that actual device path instead.

## 5. Copy Repo and Bootstrap Host

```bash
sudo mkdir -p /opt
cd /opt
sudo git clone <YOUR_DEPLOYMENT_REPO_URL> openclaw
sudo chown -R ec2-user:ec2-user /opt/openclaw

cd /opt/openclaw
sudo bash scripts/bootstrap-al2023-arm64.sh
```

## 6. Create and Fill `deploy/.env`

```bash
cd /opt/openclaw
cp deploy/.env.example deploy/.env
chmod 600 deploy/.env
```

Set:

- `AWS_REGION=<your-region>`
- `S3_ARCHIVE_BUCKET=<ArchiveBucketNameOutput from stack>`
- `S3_ARCHIVE_PREFIX=openclaw-prod-1`
- `OPENCLAW_MODEL_PRIMARY=anthropic/claude-sonnet-4-20250514`
- `OPENCLAW_MODEL_FAST=anthropic/claude-haiku-4-5`
- `OPENCLAW_MODEL_DEEP=anthropic/claude-opus-4-1`
- `SLACK_BOT_TOKEN=xoxb-...`
- `SLACK_APP_TOKEN=xapp-...`
- `ASANA_PERSONAL_ACCESS_TOKEN=<Asana PAT for the asana skill>`
- `GITHUB_PERSONAL_ACCESS_TOKEN=<GitHub token for the openclaw-github-assistant skill>`

Optional SSH-related values:

- `KEY_PAIR_NAME=openclaw-admin`
- `SSH_ACCESS_HOSTNAME=<public hostname or IP used for SSH>`

## 7. Install OpenClaw Config and Host Services

```bash
cd /opt/openclaw
sudo bash scripts/install-openclaw-config.sh
sudo bash scripts/install-logrotate-config.sh
sudo logrotate -f /etc/logrotate.conf
```

This also installs all workspace instruction files from `deploy/openclaw/workspace/*.md` into the live OpenClaw workspace directory.
It also installs starter focus skills from `deploy/openclaw/workspace/skills/`.
It attempts to install `gh` via GitHub's RPM repo on Amazon Linux.

Install OpenClaw and Claude auth tools:

```bash
runuser -l ec2-user -c 'cd /opt/openclaw && bash scripts/install-openclaw-recommended.sh'
runuser -l ec2-user -c 'openclaw onboard --install-daemon'
runuser -l ec2-user -c 'cd /opt/openclaw && bash scripts/install-openclaw-skills.sh'
runuser -l ec2-user -c 'cd /opt/openclaw && bash scripts/install-claude-code.sh'
runuser -l ec2-user -c 'claude'
runuser -l ec2-user -c 'claude setup-token'
sudo /opt/openclaw/scripts/setup-anthropic-subscription-auth.sh
```

This setup keeps Sonnet as the default model and installs an OpenClaw workspace routing policy that can delegate cheap work to Haiku subagents and heavier reasoning to Opus subagents.

Install CloudWatch and cron maintenance:

```bash
sudo mkdir -p /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.d
sudo cp aws/cloudwatch/amazon-cloudwatch-agent.json /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.d/openclaw.json
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.d/openclaw.json \
  -s

sudo cp deploy/cron/openclaw-maintenance.cron /etc/cron.d/openclaw-maintenance
sudo chmod 644 /etc/cron.d/openclaw-maintenance
sudo systemctl enable --now crond
```

## 8. Validate

```bash
runuser -l ec2-user -c 'openclaw gateway status'
```

Expect OpenClaw gateway running and Slack bot online/responding.
