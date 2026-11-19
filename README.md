# OrderFlow Global AWS Cloud — Companion Code Labs

Companion CloudFormation templates, `cfn-guard v3.2.1` rules, OPA Rego
policies (`aws_guardrails.rego`), Organizations SCP/RCP/Declarative JSON
policies, IAM Access Analyzer fixtures, LocalStack test scripts, Valkey 8.1
scripts, and `FOCUS 1.2` / `CUR 2.0` SQL FinOps analytics for:

> **AWS Cloud Engineering: From Zero to Production**  
> *A Practical Guide to Multi-Account Landing Zones, Resource Control
> Policies, Cloud WAN, Aurora Global, Valkey, OTel Observability, and
> FOCUS 1.2 FinOps*  
> *Practical Engineering Series — Volume 04*  
> **Author & Publisher:** Kien Nguyen  
> **Repository:** `https://github.com/kiennt308/aws-cloud-engineering-labs`

Copyright © 2026 Kien Nguyen. Companion infrastructure templates, policy
files, shell validation scripts, and analytics SQL queries in this
repository are licensed under the **Apache License, Version 2.0
(Apache-2.0)**.

---

## Verified Toolchain & AWS Baseline (`Nov. 19, 2026`)

| Component / Tool | Verified Version / Baseline | Purpose in Labs |
|---|---|---|
| **AWS CLI v2** | `v2.41.1` | STS, S3, KMS, SQS, CW CLI validation |
| **LocalStack** | `v2026.10.0` (`localstack/localstack:4` offline) | Zero-bill local AWS API emulation |
| **cfn-lint** | `v1.60.0` | CloudFormation resource schema lint |
| **cfn-guard** | `v3.2.1` | Preventive IaC policy-as-code rules |
| **AWS CDK / SAM** | `v2.277.0` (`v2.1148.1`) / `v1.172.1` | Synth & serverless IaC baseline |
| **Prowler / Checkov** | `v5.14.2` / `v3.4.5` | Continuous CIS / FSBP compliance checks |
| **Conftest / Trivy** | `OPA v1` / `v0.76+` (Docker) | Offline Rego & IaC misconfig checks |
| **Aurora PostgreSQL** | `17` & `18` (`18.3`) Global DB | Multi-region relational tier |
| **ElastiCache Valkey** | `8.0` & `8.1` | Bloom filters, Swiss hash, COMMANDLOG |
| **CloudWatch OTLP** | Native OTLP + `aws/spans` | Replaces retired X-Ray SDKs/Daemon |
| **Data Exports** | `FOCUS 1.2` (`FOCUS_1_2_AWS`) & `CUR 2.0` | Unit-cost & invoice SQL analytics |

> **Retired Patterns Replaced:** AWS X-Ray SDKs/Daemon (maintenance mode
> Feb 25, 2026; End-of-Support Feb 25, 2027), CloudFront OAI (use OAC),
> CUR 1.0 (use `FOCUS 1.2` & `CUR 2.0`), EC2 IMDSv1 (`HttpTokens: required`),
> static IAM `AKIA` keys, S3 ACLs, Redis OSS defaults, and standalone
> member-account root credentials are excluded from all production files.

---

## Repository Directory Map

```text
code-labs/
├── README.md        Baseline versions & zero-cloud-bill test guide
├── policies/        cfn-guard (.guard) & Conftest Rego guardrails
├── ch01/            Org OUs, SCPs, RCPs, Declarative Policies & audit
├── ch02/            Identity Center, Pod Identity & Access Analyzer
├── ch03/            IPAM, Cloud WAN policy, PrivateLink, Lattice & ARC
├── ch04/            Graviton5 ASG, IMDSv2, ECR, ECS & EventBridge/SQS
├── ch05/            CloudFront OAC SigV4, WAF v2, Functions & Route 53
├── ch06/            Aurora PG 18 Global, Valkey 8.1 & live cache lab
├── ch07/            S3 Tables/Express, KMS mrk-*, Backup Vault & S3 KMS
├── ch08/            GuardDuty, Security Hub CSPM, Trail & Prowler cfg
├── ch09/            CloudWatch OTLP, Transaction Search, FIS & EMF lab
└── ch10/            Data Exports FOCUS 1.2 / CUR 2.0 & SQL analytics
```

---

## Zero-Cloud-Bill Verification Quickstart

Run offline schema, policy, LocalStack, Valkey 8.1, and FOCUS 1.2 SQL
checks cleanly without creating billable AWS cloud resources:

```bash
python3 ch10/04-run-finops-sql-lab.py
```

Pair static checks (`cfn-lint`, `cfn-guard`, `trivy config`, `conftest`)
with disposable `LocalStack` and `valkey:8.1` Docker containers as detailed
in Chapters 1–10.
