# Data Generation Log — Cinderhaven Product Master

This document records how the synthetic dataset was constructed and, more importantly, how it was intentionally broken. Every defect in the Cinderhaven database was placed deliberately to simulate a pattern observed in real retail product data. The purpose is to demonstrate knowledge of what real data looks like in the wild, not just what clean database tables look like.

> **Verification note:** Run `Rscript R/03_verify.R` to confirm actual counts from the database. Defect counts below were last checked against `output/frames/raw_tables.rds` on 2026-11-15.

## Database overview

The Cinderhaven product master database contains 9 tables: product_master (50 rows), sku_costs (50), stores, distribution_log, chargebacks, promotions, price_history, scan_data (~1.4M rows), and retailer_requirements. The database represents a fictional specialty food company at approximately $33 million in trailing twelve-month revenue with 50 SKUs across 5 product lines (Artisan Sauces, Pantry Staples, Specialty Condiments, Dried Goods, Snack Bites), selling through 6 contracted retailers (national mass retailer, club retailer, natural grocer, conventional grocer, regional natural grocer, Regional Group).

## Intentional defects and their real-world basis

### GTIN-14 check digit errors

**What was done:** Misaligned the mod-10 check digit on 12 of 50 SKUs (24%).

**Real-world basis:** Human data-entry error rates on numeric fields in product masters typically run 5% to 15%, depending on the entry process and whether any validation exists at point of entry. The most common GTIN error is a transposed or miscalculated check digit, because the check digit is the last field entered and is often typed from memory or from a label that has been photocopied, faxed, or re-keyed from a broker spreadsheet. Most product masters have no check digit validation at entry. The error persists indefinitely because nobody re-validates GTIN fields after initial entry.

**What this enables in the analysis:** The chargeback-to-defect linkage that is the centerpiece of the report. Twelve wrong check digits generating chargebacks traceable to a specific field in a specific record.

### UPC-12 check digit errors

**What was done:** Misaligned the mod-10 check digit on 12 of 50 SKUs (24%). They are the same 12 SKUs that carry the GTIN-14 error.

**Real-world basis:** Same mechanism as GTIN-14 errors but less common because UPC-12 is the consumer-facing barcode that gets scanned at retail POS. Errors in the UPC are more likely to be caught by in-store scanning during the first week of sales. GTIN-14 errors persist longer because the case-level barcode is scanned at distribution centers where the feedback loop to the vendor is slower.

### Brand owner field: placeholder values

**What was done:** The brand_owner field is fully populated on all 50 SKUs. No placeholder values exist in the current dataset.

**Real-world basis:** "NA," "N/A," "TBD," and blank values in text fields are the most common data defect in product masters that accept free-text input without validation. The person entering the SKU didn't know the answer, typed a placeholder, and moved on. Nobody reviewed it. The retailer's system accepted it because the field was not empty. It fails validation when a retailer tightens their required-field rules or when a compliance audit runs against the product master.

### Missing case dimensions

**What was done:** Blanked at least one case dimension on 19 of 50 SKUs (38%): length on 9, width on 5, height on 6.

**Real-world basis:** Case dimensions require physical measurement of the actual product. Unlike text fields that can be typed from a specification sheet, dimensions require someone to pull a case from inventory, put it on a scale, and measure it with a tape. This step is skipped more often than any other because it requires physical access to inventory and because the person entering the data may not have access to a warehouse. The 38% rate mirrors the typical state of a mid-market company that has populated dimensions for products that have gone through a full retailer onboarding process but not for products that were added to the master through informal channels.

### Missing case weights

**What was done:** Blanked the case weight on 3 of 50 SKUs (6%). The same 3 SKUs have no unit weight. Every populated case weight is plausible against case pack and unit weight; no implausible values exist in the current dataset.

**Real-world basis:** When case weights are populated, they are sometimes entered in the wrong unit (pounds instead of kilograms or vice versa), copied from the wrong product, or defaulted to zero by an import script that treats null as zero. These values pass a "field is not blank" check but fail a plausibility check, triggering dimension mismatch chargebacks when the warehouse receives a case that doesn't match the record.

### Missing country of origin

**What was done:** Blanked country_of_origin on 1 of 50 SKUs (2%).

**Real-world basis:** Country of origin is usually typed once at item setup and never revisited. A blank passes at retailers that do not require the field and fails at those that do, so the gap surfaces only when the SKU is offered to a stricter customer.

### OneWorldSync registration status

**What was done:** OneWorldSync statuses distributed across 50 SKUs. Exact breakdown requires `Rscript R/03_verify.R`.

**Real-world basis:** OneWorldSync (1WorldSync) registration is the mechanism for synchronizing product data with retailers via the Global Data Synchronization Network (GDSN). Mid-market specialty food companies typically begin the registration process when a major retailer requires it but do not prioritize completing it across the full catalog. A 10% completion rate is typical for a company at Cinderhaven's scale that has registered its top sellers for one retailer but has not extended the process catalog-wide.

### Serving size format inconsistency

**What was done:** Varied serving size strings across 14 different formats (e.g., "2 tbsp (30 mL)," "30ml," "2 tablespoons," "30 milliliters," "2T").

**Real-world basis:** Serving size is entered as a free-text field in most product masters. Different people enter it differently. Brokers copy it from the product label, which may use abbreviated or non-standard notation. Import scripts may strip or reformat units. The result is a field that contains the correct information in an inconsistent format, making it impossible to validate, compare, or aggregate programmatically without normalization.

### Chargeback concentration (Pareto distribution)

**What was done:** Seeded chargeback event counts and dollar amounts across all 50 SKUs. In the current dataset every SKU carries some chargebacks, and the dollars are concentrated: the top 5 SKUs (10%) carry 42% of chargeback dollars and the top 10 (20%) carry 60%. Of 2,873 chargebacks, 275 carry a `triggered_by_field` value naming one of five product-data fields (case dimensions, UPC, GTIN-14, country of origin, case weight).

**Real-world basis:** Chargeback distributions in real retail are consistently Pareto-shaped. A small number of SKUs, typically those with multiple overlapping data defects, generate a disproportionate share of chargeback dollars. The 80/20 pattern (or steeper) is the most commonly observed distribution in chargeback analysis across CPG categories.

### Chargeback assignment logic

**What was done:** Assigned chargebacks only to SKU/retailer pairs with active distribution authorizations, weighted by data quality score (lower quality = more chargebacks), with lognormal variance in event dollar amounts.

**Real-world basis:** Chargebacks can only be issued against products that are actually in distribution at a retailer. The weighting by data quality score ensures that the synthetic chargebacks correlate with data defects, which is the pattern observed in real engagements: SKUs with more data defects generate more compliance penalties. The lognormal variance in dollar amounts reflects the fact that real chargeback amounts vary based on the specific retailer, the type of defect, and the volume of product involved.

### Time-to-shelf quality-dependent lag

**What was done:** Modeled the gap between store authorization date and first scan date with a quality-dependent delay. SKUs with lower data quality scores receive longer delays, calibrated to produce a roughly 3x spread between the worst and best quality tiers (32 days vs. 10 days).

**Real-world basis:** In real retail, the time between a buyer authorizing a product and that product generating its first sale is largely determined by how quickly the product clears automated validation checks in the retailer's item setup system. Products with valid GTINs, complete case dimensions, and registered data pool records clear in days. Products with data defects enter manual review queues, generate correction requests back to the vendor, and wait for resubmission. The 3x spread is conservative. In some retailer systems, a single missing field can add 4 to 6 weeks to the setup process.

### Deauthorization rate by quality tier

**What was done:** Set deauthorization rates to correlate with data quality: bottom-half SKUs lose authorizations at approximately 4.5x the rate of top-half SKUs.

**Real-world basis:** Retailers periodically review product performance and compliance. Products that generate repeated chargebacks, have unresolved data defects, or fail periodic compliance audits are more likely to be removed from store planograms. The correlation between data quality and deauthorization is real but confounded by other factors (poor velocity, category rationalization, planogram resets). The synthetic data isolates the data quality signal by controlling for other variables.

### Data entry source distribution

**What was done:** Assigned each SKU to one of seven data entry sources (broker_upload, production_admin, inventory_admin, import_script, quality_mgr, ops_coordinator, or unknown), with different error profiles per source.

**Real-world basis:** Product masters at mid-market companies are populated through multiple channels, each with different levels of data quality. Broker uploads tend to be lower quality because brokers are entering data for dozens of brands simultaneously with no brand-specific validation. Production admin entries tend to be higher quality because the person entering the data is closer to the product and treats data entry as a primary task rather than a side task. The "unknown" source (9 SKUs with no recorded entry source) represents the common real-world gap where records exist in the product master with no audit trail of who entered them or when.

### Promotional data

**What was done:** Generated 123 promotions across the observation window. Most do not have sufficient pre-promotion scan history to compute lift cleanly. Of the 123 promotions, 18 have sufficient pre-period scan data to estimate lift; the observed median lift is 74% and the mean lift is 77%.

**Real-world basis:** Promotional effectiveness data in real retail is notoriously noisy. Most mid-market specialty food companies cannot isolate promotional lift because they lack control-store methodology, pre-promotion baseline measurement, and consistent promotional calendars. The limited computability (18 of 123 promotions) reflects the reality that most promotional events at this scale lack the clean pre-period baseline needed to measure lift. The positive lift among computable promotions is consistent with the effect of temporary price reductions on specialty food products, where even modest promotions can drive meaningful volume increases.

## What the synthetic data cannot do

The synthetic data is designed to support the analytical frameworks in this audit. It cannot fully replicate three aspects of real retail data:

1. **Seasonality.** Real scan data has seasonal patterns (holiday peaks, summer slowdowns) that affect velocity, promotional planning, and chargeback timing. The synthetic data has no meaningful seasonal signal.

2. **Competitive dynamics.** Real category data includes competitor products, market share, and competitive displacement when a SKU loses shelf space. The synthetic data contains only Cinderhaven products.

3. **Retailer system behavior.** Real retailer systems have idiosyncratic validation rules, timing delays, and exception handling that vary by retailer and change over time. The synthetic data applies uniform logic across all retailers, varying only the required-field sets.

These limitations are documented in the report's "How I'd Do This Differently With Real Data" appendix section.
