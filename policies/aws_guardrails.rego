# aws_guardrails.rego
# OrderFlow Global AWS Platform — Conftest OPA v1 CloudFormation Policy
# Target: OPA v1 / openpolicyagent/conftest:latest
# Copyright (c) 2026 Kien Nguyen. Licensed under Apache-2.0.

package main

import rego.v1

s3_public_block_flags := [
  "BlockPublicAcls",
  "IgnorePublicAcls",
  "BlockPublicPolicy",
  "RestrictPublicBuckets",
]

cfn_resources := res if {
  is_object(input)
  res := object.get(input, "Resources", {})
  is_object(res)
} else := {}

has_nonempty_prop(obj, key) if {
  is_object(obj)
  val := obj[key]
  val != null
  val != ""
}

any_origin_has_oac(dist_cfg) if {
  origins := object.get(dist_cfg, "Origins", [])
  is_array(origins)
  some origin in origins
  has_nonempty_prop(origin, "OriginAccessControlId")
}

has_bucket_owner_enforced(props) if {
  oc := object.get(props, "OwnershipControls", {})
  rules := object.get(oc, "Rules", [])
  is_array(rules)
  some rule in rules
  object.get(rule, "ObjectOwnership", "") == "BucketOwnerEnforced"
}

has_stop_conditions(props) if {
  stops := object.get(props, "StopConditions", [])
  is_array(stops)
  count(stops) > 0
}

deny contains msg if {
  some name, res in cfn_resources
  object.get(res, "Type", "") == "AWS::EC2::LaunchTemplate"
  props := object.get(res, "Properties", {})
  lt_data := object.get(props, "LaunchTemplateData", {})
  meta := object.get(lt_data, "MetadataOptions", {})
  object.get(meta, "HttpTokens", "") != "required"
  msg := sprintf(
    "IMDSV2_GUARD: %s must set MetadataOptions.HttpTokens = \"required\"",
    [name],
  )
}

deny contains msg if {
  some name, res in cfn_resources
  object.get(res, "Type", "") == "AWS::CloudFront::Distribution"
  props := object.get(res, "Properties", {})
  dist_cfg := object.get(props, "DistributionConfig", {})
  origins := object.get(dist_cfg, "Origins", [])
  is_array(origins)
  some origin in origins
  s3_cfg := object.get(origin, "S3OriginConfig", {})
  has_nonempty_prop(s3_cfg, "OriginAccessIdentity")
  msg := sprintf(
    "CLOUDFRONT_OAI_GUARD: %s uses legacy OriginAccessIdentity; use OAC",
    [name],
  )
}

deny contains msg if {
  some name, res in cfn_resources
  object.get(res, "Type", "") == "AWS::CloudFront::Distribution"
  props := object.get(res, "Properties", {})
  dist_cfg := object.get(props, "DistributionConfig", {})
  not has_nonempty_prop(dist_cfg, "WebACLId")
  msg := sprintf(
    "CLOUDFRONT_WAF_GUARD: %s must associate an AWS WAF WebACLId",
    [name],
  )
}

deny contains msg if {
  some name, res in cfn_resources
  object.get(res, "Type", "") == "AWS::CloudFront::Distribution"
  props := object.get(res, "Properties", {})
  dist_cfg := object.get(props, "DistributionConfig", {})
  not any_origin_has_oac(dist_cfg)
  msg := sprintf(
    "CLOUDFRONT_OAC_GUARD: %s must configure OriginAccessControlId",
    [name],
  )
}

deny contains msg if {
  some name, res in cfn_resources
  object.get(res, "Type", "") == "AWS::CloudFront::Distribution"
  props := object.get(res, "Properties", {})
  dist_cfg := object.get(props, "DistributionConfig", {})
  any_origin_has_oac(dist_cfg)
  origins := object.get(dist_cfg, "Origins", [])
  is_array(origins)
  some origin in origins
  is_object(object.get(origin, "S3OriginConfig", null))
  not has_nonempty_prop(origin, "OriginAccessControlId")
  msg := sprintf(
    "CLOUDFRONT_OAC_GUARD: %s S3 origin missing OriginAccessControlId",
    [name],
  )
}

deny contains msg if {
  some name, res in cfn_resources
  object.get(res, "Type", "") == "AWS::S3::Bucket"
  props := object.get(res, "Properties", {})
  pab := object.get(props, "PublicAccessBlockConfiguration", {})
  missing := [f |
    some f in s3_public_block_flags
    object.get(pab, f, false) != true
  ]
  count(missing) > 0
  msg := sprintf(
    "S3_PUBLIC_BLOCK_GUARD: %s must set %s = true",
    [name, concat(", ", missing)],
  )
}

deny contains msg if {
  some name, res in cfn_resources
  object.get(res, "Type", "") == "AWS::S3::Bucket"
  props := object.get(res, "Properties", {})
  not has_bucket_owner_enforced(props)
  msg := sprintf(
    "S3_OWNERSHIP_GUARD: %s must enforce BucketOwnerEnforced",
    [name],
  )
}

deny contains msg if {
  some name, res in cfn_resources
  object.get(res, "Type", "") == "AWS::RDS::DBCluster"
  props := object.get(res, "Properties", {})
  object.get(props, "StorageEncrypted", false) != true
  msg := sprintf(
    "RDS_ENCRYPTION_GUARD: %s must set StorageEncrypted = true",
    [name],
  )
}

deny contains msg if {
  some name, res in cfn_resources
  object.get(res, "Type", "") == "AWS::RDS::DBInstance"
  props := object.get(res, "Properties", {})
  object.get(props, "PubliclyAccessible", false) == true
  msg := sprintf(
    "RDS_PUBLIC_GUARD: %s must not set PubliclyAccessible = true",
    [name],
  )
}

deny contains msg if {
  some name, res in cfn_resources
  object.get(res, "Type", "") == "AWS::KMS::Key"
  props := object.get(res, "Properties", {})
  object.get(props, "EnableKeyRotation", false) != true
  msg := sprintf(
    "KMS_ROTATION_GUARD: %s must set EnableKeyRotation = true",
    [name],
  )
}

deny contains msg if {
  some name, res in cfn_resources
  object.get(res, "Type", "") == "AWS::FIS::ExperimentTemplate"
  props := object.get(res, "Properties", {})
  not has_stop_conditions(props)
  msg := sprintf(
    "FIS_STOP_GUARD: %s must define non-empty StopConditions",
    [name],
  )
}
