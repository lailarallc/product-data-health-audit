# tests/test_engagement_titles.R — Regression tests for compose_titles().
#
# Run: Rscript tests/test_engagement_titles.R
#
# Guards the round-3 fix: deliverable titles are COMPOSED from the client identity
# so a present-but-stale report.* literal can't leak the wrong client name. Asserts
# the composed demo defaults reproduce the golden strings byte-for-byte, that an
# explicit report.* value overrides the default, and that a client identity never
# yields a title carrying the demo client's name.

ROOT <- normalizePath(
  Sys.getenv("PROJECT_ROOT", unset = "."),
  winslash = "/", mustWork = FALSE)
source(file.path(ROOT, "R", "engagement.R"))

pass <- 0L
fail <- 0L
assert <- function(desc, expr) {
  ok <- tryCatch(isTRUE(expr), error = function(e) FALSE)
  if (ok) pass <<- pass + 1L
  else { fail <<- fail + 1L; cat(sprintf("  FAIL: %s\n", desc)) }
}
# Byte-for-byte UTF-8 equality (the demo golden must match exactly).
same_bytes <- function(a, b) identical(charToRaw(enc2utf8(a)), charToRaw(enc2utf8(b)))

# A demo-like engagement with NO report.* overrides -> everything composed.
demo_eng <- list(
  client_name  = "Cinderhaven Provisions",
  client_short = "Cinderhaven",
  as_of_date   = "2026-05-03",
  config_raw   = list()
)

DOT <- "·"
gold_subtitle  <- paste0("Cinderhaven Provisions  ", DOT, "  May 2026")
gold_dashboard <- paste0("Cinderhaven ", DOT, " Monday Morning Dashboard")
gold_tearsheet <- paste0("Cinderhaven Provisions ", DOT, " Product Data Readiness")

t <- compose_titles(demo_eng)

cat("--- composed defaults reproduce the golden byte-for-byte ---\n")
assert("subtitle matches golden bytes",  same_bytes(t$report_subtitle, gold_subtitle))
assert("dashboard title matches golden bytes", same_bytes(t$dashboard_title, gold_dashboard))
assert("tearsheet title matches golden bytes", same_bytes(t$tearsheet_title, gold_tearsheet))

cat("\n--- 0.d split: the subtitle month-year is the REPORT date, not data_as_of ---\n")
split_eng <- list(
  client_name  = "Cinderhaven Provisions",
  client_short = "Cinderhaven",
  data_as_of   = "2026-01-31",
  report_date  = "2026-05-03",
  config_raw   = list()
)
assert("subtitle uses report_date (May 2026), not data_as_of (January 2026)",
       same_bytes(compose_titles(split_eng)$report_subtitle, gold_subtitle))

cat("\n--- an explicit report.* value overrides the composed default ---\n")
ovr_eng <- demo_eng
ovr_eng$config_raw <- list(report = list(dashboard_title = "Custom Wording Dashboard"))
to <- compose_titles(ovr_eng)
assert("override wins for the set field",
       identical(to$dashboard_title, "Custom Wording Dashboard"))
assert("unset fields still compose from client identity",
       same_bytes(to$report_subtitle, gold_subtitle))
# An empty-string override is treated as absent (falls back to composed default).
empty_eng <- demo_eng
empty_eng$config_raw <- list(report = list(dashboard_title = ""))
assert("empty override falls back to composed default",
       same_bytes(compose_titles(empty_eng)$dashboard_title, gold_dashboard))

cat("\n--- a client identity never yields the demo client's name (the leak) ---\n")
nwn_eng <- list(
  client_name  = "Northwind Naturals",
  client_short = "Northwind",
  as_of_date   = "2026-06-30",
  config_raw   = list()   # no titles set — the exact stale-literal scenario
)
tn <- compose_titles(nwn_eng)
assert("dashboard title carries the client name",
       grepl("Northwind", tn$dashboard_title, fixed = TRUE))
assert("dashboard title has NO Cinderhaven",
       !grepl("Cinderhaven", tn$dashboard_title, fixed = TRUE))
assert("tearsheet + subtitle also client-clean",
       !grepl("Cinderhaven", paste(tn$tearsheet_title, tn$report_subtitle),
              fixed = TRUE))

cat("\n--- the SHIPPED engagement.demo.yml renders through the real loader ---\n")
# Coverage gap the 0.d break exposed: every fixture above builds config_raw by hand,
# so none exercised load_engagement() on the ACTUAL demo config — whose top-level
# report_date key (and no report: block) made R's $ partial-match `report` ->
# `report_date`, so rpt became an atomic string and the render crashed. This loads the
# real engagement.demo.yml (the exact path the write_variables.R pre-render takes) and
# asserts the golden subtitle. Load it EXPLICITLY so a stray engagement.yml in the
# working clone can't shadow it (the source of the earlier "Northwind" artifact).
old_cfg <- Sys.getenv("ENGAGEMENT_CONFIG", unset = NA)
Sys.setenv(ENGAGEMENT_CONFIG = file.path(ROOT, "engagement.demo.yml"))
demo_cfg_eng <- load_engagement(ROOT)
if (is.na(old_cfg)) Sys.unsetenv("ENGAGEMENT_CONFIG") else Sys.setenv(ENGAGEMENT_CONFIG = old_cfg)

assert("real demo config loads as a demo", isTRUE(demo_cfg_eng$is_demo))
assert("real demo config: data_as_of and report_date are distinct (0.d split)",
       !identical(demo_cfg_eng$data_as_of, demo_cfg_eng$report_date))
assert("real demo config: compose_titles subtitle matches golden bytes",
       same_bytes(compose_titles(demo_cfg_eng)$report_subtitle, gold_subtitle))

cat(sprintf("\n%d passed, %d failed\n", pass, fail))
if (fail > 0) stop("Tests failed.")
