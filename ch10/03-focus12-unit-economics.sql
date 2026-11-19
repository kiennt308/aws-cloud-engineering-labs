-- OrderFlow Global FOCUS 1.2 (FOCUS_1_2_AWS) FinOps Analytics
-- Author: Kien Nguyen | License: Apache-2.0
-- Compatible with SQLite 3 and Amazon Athena (FOCUS_1_2_AWS).

-- 1. Monthly EffectiveCost vs BilledCost by InvoiceId & ServiceName
SELECT
  BillingPeriodStart,
  InvoiceId,
  ServiceName,
  ROUND(SUM(EffectiveCost), 2) AS total_effective_usd,
  ROUND(SUM(BilledCost), 2) AS total_billed_usd,
  ROUND(SUM(EffectiveCost) - SUM(BilledCost), 2) AS delta_usd
FROM focus_1_2
GROUP BY BillingPeriodStart, InvoiceId, ServiceName
ORDER BY BillingPeriodStart, InvoiceId, total_effective_usd DESC;

-- 2. Unit Cost per 1,000 OrderFlow Orders by Environment & Region
SELECT
  BillingPeriodStart,
  x_Environment AS environment,
  RegionId,
  MAX(x_OrderCount) AS orders_count,
  ROUND(SUM(EffectiveCost), 2) AS total_effective_usd,
  ROUND(
    SUM(EffectiveCost) * 1000.0 / NULLIF(MAX(x_OrderCount), 0),
    4
  ) AS cost_per_1k_orders_usd
FROM focus_1_2
GROUP BY BillingPeriodStart, x_Environment, RegionId
ORDER BY BillingPeriodStart, x_Environment, RegionId;

-- 3. Cross-AZ & NAT Gateway Network Waste Detector
SELECT
  BillingPeriodStart,
  SubAccountName,
  RegionId,
  x_Workload AS network_vector,
  ResourceId,
  ROUND(SUM(ConsumedQuantity), 2) AS consumed_qty,
  ConsumedUnit,
  ROUND(SUM(EffectiveCost), 2) AS effective_usd
FROM focus_1_2
WHERE ServiceName = 'AmazonVPC'
GROUP BY
  BillingPeriodStart,
  SubAccountName,
  RegionId,
  x_Workload,
  ResourceId,
  ConsumedUnit
ORDER BY BillingPeriodStart, effective_usd DESC;

-- 4. Intel x86_64 (m7i) vs AWS Graviton5 (m9g) Compute Comparison
SELECT
  BillingPeriodStart,
  CASE
    WHEN ResourceId LIKE '%m9g%' THEN 'Graviton5 (m9g.xlarge)'
    WHEN ResourceId LIKE '%m7i%' THEN 'Intel x86_64 (m7i.xlarge)'
    ELSE 'Other EC2'
  END AS compute_arch,
  ROUND(SUM(ConsumedQuantity), 0) AS compute_hours,
  ROUND(SUM(ListCost), 2) AS list_usd,
  ROUND(SUM(EffectiveCost), 2) AS effective_usd,
  ROUND(
    SUM(EffectiveCost) / NULLIF(SUM(ConsumedQuantity), 0),
    4
  ) AS effective_rate_per_hr
FROM focus_1_2
WHERE ServiceName = 'AmazonEC2'
  AND ChargeCategory = 'Usage'
GROUP BY BillingPeriodStart, compute_arch
ORDER BY BillingPeriodStart, effective_rate_per_hr DESC;
