#-------------------------------------------------------------------------
# Prague 2026 Municipal Election: Bayesian Prediction Model
#-------------------------------------------------------------------------
#
# Largely inspired by the Zweitstimme Election Model by Stoetzer et al. (2019, 2025) and the Gelman and King (1993) approach to predicting elections.
# But with big  changes (GPs, Ordered Beta Regression, even less local polling data in Prague)
#
# Core Components:
# 1. Fundamentals Model (Ordered Beta Regression) for Prague based on historical election data and national trends
#  1a. Latent national polling (Gaussian Processes)
#  1b. Prague-specific elasticity of national support (based on Prague vs. National party performance in Parliamentary elections)
#  1c. Historical fundamentals of Prague  (Prague vs. National vote share, Mayor incumbency, coalition membership, new party status)
#  1d. Fit model on data until 2022. Then posterior predict 2026.
# 2. Local Polling Update (Dirichlet–Multinomial Conjugate Update) for Prague based on the latest polling data (Ipsos, Median, SC&C)
# 3. Seat allocation simulation (d'Hondt, 5% threshold)
#
#
# Štěpán Jabůrek
# Institute of Political Studies, Charles University
# -------------------------------------------------------------------------

# -------------------------------------------------------------------------
# 0. Setup
# -------------------------------------------------------------------------
install.packages(c("tidyverse", "brms", "ordbetareg", "patchwork"), dependencies = TRUE)
library(tidyverse)
library(brms)
library(ordbetareg)
library(patchwork)

set.seed(2026)

# -------------------------------------------------------------------------
# 1. National Polling Latent State (brms GP)
# -------------------------------------------------------------------------
polls_nat <- read_csv("data/national_polls_2025_2026.csv", show_col_types = FALSE) %>%
  mutate(
    date     = dmy(Datum),
    day_norm = as.numeric(date - min(date)) / 100
  )

parties_nat <- c("ANO", "STAN", "ODS", "TOP", "KDU", "Pir", "SPD", "Moto", "Spojena_Levice")
latest_nat  <- list()

for (p in parties_nat) {
  df_p   <- polls_nat %>% filter(!is.na(.data[[p]]))
  fit_gp <- brm(
    as.formula(paste0(p, " ~ s(day_norm, k = 5, bs = 'tp')")),
    data    = df_p,
    control = list(adapt_delta = 0.99),
    chains  = 2, cores = 2, iter = 1000, warmup = 300, refresh = 0,
    backend = "cmdstanr"
  )
  pred_today      <- fitted(fit_gp, newdata = tibble(day_norm = max(polls_nat$day_norm)))
  latest_nat[[p]] <- as.numeric(pred_today[1, "Estimate"])
}
nat <- unlist(latest_nat)

# -------------------------------------------------------------------------
# 2. Regional Elasticity Projection (Prague Macro Trends)
# -------------------------------------------------------------------------
# Historical ratio: Prague vote share vs. National vote share (PS 2025)
elasticity <- c(
  "STAN"           = 1.20,
  "SPOLU"          = 1.45,
  "ANO"            = 0.57,
  "Pirati"         = 1.88,
  "SPD"            = 0.67,
  "Motoriste"      = 0.76,
  "Spojena_Levice" = 0.64
)

parties_2026  <- c("STAN", "SPOLU", "ANO", "Pirati", "Praha_Sobe", "SPD", "Motoriste", "Spojena_Levice", "Ostatni")
display_names <- c("STAN", "SPOLU", "ANO", "Piráti", "Praha Sobě", "SPD", "Motoristé", "Spojená Levice", "Ostatní")

# Project national levels down to Prague and normalize to 100%
raw_prague_proj <- c(
  "STAN"           = as.numeric(nat["STAN"] * elasticity["STAN"]),
  "SPOLU"          = as.numeric((nat["ODS"] + nat["TOP"]) * elasticity["SPOLU"]),
  "ANO"            = as.numeric(nat["ANO"] * elasticity["ANO"]),
  "Pirati"         = as.numeric(nat["Pir"] * elasticity["Pirati"]),
  "Praha_Sobe"     = 11.5, # Local movement benchmark
  "SPD"            = as.numeric(nat["SPD"] * elasticity["SPD"]),
  "Motoriste"      = as.numeric(nat["Moto"] * elasticity["Motoriste"]),
  "Spojena_Levice" = as.numeric(nat["Spojena_Levice"] * elasticity["Spojena_Levice"]),
  "Ostatni"        = 4.0   # Baseline other parties
)
prague_nat_trend <- (raw_prague_proj / sum(raw_prague_proj)) * 100

pred_2026 <- tibble(
  party        = parties_2026,
  nat_trend    = as.numeric(prague_nat_trend[parties_2026]) / 100,
  voteshare_l1 = c(0.0777, 0.2997, 0.1934, 0.1773, 0.1473, 0.0517, 0.0229, 0.0202, 0.0400),
  pm           = c(0, 1, 0, 1, 0, 0, 0, 0, 0),
  gov          = c(1, 1, 0, 1, 0, 0, 0, 0, 0),
  new_party    = c(0, 0, 0, 0, 0, 0, 0, 0, 0)
)

# -------------------------------------------------------------------------
# 3. Prague Historical Fundamentals Model (ordbetareg)
# -------------------------------------------------------------------------
hist_data <- read_csv("data/prague_historical_fundamentals.csv", show_col_types = FALSE)

data_model <- hist_data %>%
  filter(!is.na(voteshare_l1)) %>%
  mutate(nat_trend = fed_trend_months)

my_priors <- c(
  prior(normal(1, 0.5), class = "b", coef = "voteshare_l1"),
  prior(normal(1, 0.5), class = "b", coef = "nat_trend"),
  prior(normal(0, 0.3), class = "b", coef = "pm"),
  prior(normal(0, 0.3), class = "b", coef = "gov"),
  prior(normal(0, 0.3), class = "b", coef = "new_party")
)

fit_fund <- ordbetareg(
  voteshare ~ nat_trend + voteshare_l1 + pm + gov + new_party,
  data        = data_model,
  chains      = 2, cores = 2, iter = 1500, warmup = 500, refresh = 0,
  extra_prior = my_priors,
  backend     = "cmdstanr"
)

# Extract full posterior draws across all parties (retains parameter uncertainty)
prior_draws_raw <- posterior_epred(fit_fund, newdata = pred_2026)
prior_draws     <- prior_draws_raw / rowSums(prior_draws_raw)

# -------------------------------------------------------------------------
# 4. Exact Conjugate Dirichlet Local Poll Update
# -------------------------------------------------------------------------
polls_prague <- read_csv("data/prague_polls_2026.csv", show_col_types = FALSE)

poll_summary <- polls_prague %>%
  mutate(
    date   = as.Date(date),
    weight = n * exp(-0.02 * as.numeric(max(date) - date))
  ) %>%
  group_by(party) %>%
  summarise(poll_pct = sum(poll_pct * weight) / sum(weight), .groups = "drop")

party_map <- c(
  "STAN" = "stan", "SPOLU" = "spolu", "ANO" = "ano", "Pirati" = "pirati",
  "Praha_Sobe" = "praha_sobe", "SPD" = "spd", "Motoriste" = "motoriste", "Spojena_Levice" = "spojena_levice"
)

N_prior         <- 500
N_poll          <- 1500
poll_others_pct <- max(0, 100 - sum(poll_summary$poll_pct))
poll_shares_8   <- poll_summary$poll_pct[match(party_map[parties_2026[1:8]], poll_summary$party)] / 100
poll_shares     <- c(poll_shares_8, poll_others_pct / 100)

# Conjugate Dirichlet update for every MCMC draw
n_draws_fund <- nrow(prior_draws)
alpha_mat    <- N_prior * prior_draws + matrix(N_poll * poll_shares, nrow = n_draws_fund, ncol = length(parties_2026), byrow = TRUE)
gamma_mat    <- matrix(rgamma(length(alpha_mat), shape = alpha_mat, rate = 1), nrow = n_draws_fund)
votes        <- gamma_mat / rowSums(gamma_mat)
colnames(votes) <- parties_2026

# -------------------------------------------------------------------------
# 5. Simulate 65 Seats with 5% Barrier (d'Hondt)
# -------------------------------------------------------------------------
seats <- t(apply(votes, 1, function(p) {
  elig <- which(p >= 0.05 & parties_2026 != "Ostatni")
  if (length(elig) == 0) return(integer(ncol(votes)))
  q <- outer(p[elig], 1:65, "/")
  winners <- elig[((order(q, decreasing = TRUE)[1:65] - 1) %% length(elig)) + 1]
  tabulate(winners, nbins = ncol(votes))
}))
colnames(seats) <- parties_2026

# Summary Table
summary_table <- tibble(
  Party          = display_names,
  `Vote %`       = round(colMeans(votes) * 100, 1),
  `90% CI`       = paste0(round(apply(votes, 2, quantile, 0.05) * 100, 1), "% - ",
                          round(apply(votes, 2, quantile, 0.95) * 100, 1), "%"),
  `Prob >= 5%`   = paste0(round(colMeans(votes >= 0.05) * 100, 0), "%"),
  `Mean Seats`   = round(colMeans(seats), 1),
  `Seats 90% CI` = paste0(apply(seats, 2, quantile, 0.05), " - ", apply(seats, 2, quantile, 0.95))
)

print(summary_table)

# Coalitions
spolu_idx <- which(parties_2026 == "SPOLU")
stan_idx  <- which(parties_2026 == "STAN")
pir_idx   <- which(parties_2026 == "Pirati")
ps_idx    <- which(parties_2026 == "Praha_Sobe")
ano_idx   <- which(parties_2026 == "ANO")
moto_idx  <- which(parties_2026 == "Motoriste")
spd_idx   <- which(parties_2026 == "SPD")

c_incumbent  <- seats[, spolu_idx] + seats[, stan_idx] + seats[, pir_idx]
c_spolu_stan <- seats[, spolu_idx] + seats[, stan_idx]
c_broad      <- c_incumbent + seats[, ps_idx]
c_right      <- seats[, spolu_idx] + seats[, ano_idx] + seats[, moto_idx]
c_nat_gov    <- seats[, ano_idx] + seats[, spd_idx] + seats[, moto_idx]

coalition_summary <- tibble(
  Coalition = c(
    "Současná koalice (SPOLU + STAN + Piráti)",
    "Dvojkoalice (SPOLU + STAN)",
    "Široká liberálně-středová (+ Praha Sobě)",
    "Konzervativní (SPOLU + ANO + Motoristé)",
    "Vládní Koalice (ANO + SPD + Motoristé)"
  ),
  `Mean Seats` = c(
    round(mean(c_incumbent), 1),
    round(mean(c_spolu_stan), 1),
    round(mean(c_broad), 1),
    round(mean(c_right), 1),
    round(mean(c_nat_gov), 1)
  ),
  `Majority Prob (>=33)` = c(
    paste0(round(mean(c_incumbent >= 33) * 100, 1), "%"),
    paste0(round(mean(c_spolu_stan >= 33) * 100, 1), "%"),
    paste0(round(mean(c_broad >= 33) * 100, 1), "%"),
    paste0(round(mean(c_right >= 33) * 100, 1), "%"),
    paste0(round(mean(c_nat_gov >= 33) * 100, 1), "%")
  )
)

print(coalition_summary)

# -------------------------------------------------------------------------
# 6. Save Simulation RDS
# -------------------------------------------------------------------------
forecast_output <- list(
  parties        = parties_2026,
  votes          = votes,
  seats          = seats,
  forecast_table = summary_table,
  coalitions     = list(
    spolu_stan_pir = list(
      name          = "Koalice SPOLU + STAN + Piráti",
      mean_seats    = mean(c_incumbent),
      prob_majority = mean(c_incumbent >= 33) * 100
    ),
    spolu_ano_moto = list(
      name          = "Koalice SPOLU + ANO + Motoristé",
      mean_seats    = mean(c_right),
      prob_majority = mean(c_right >= 33) * 100
    ),
    broad_liberal  = list(
      name          = "Široká liberálně-středová (+ Praha Sobě)",
      mean_seats    = mean(c_broad),
      prob_majority = mean(c_broad >= 33) * 100
    ),
    nat_gov  = list(
      name          = "Vládní Koalice (ANO + SPD + Motoristé)",
      mean_seats    = mean(c_nat_gov),
      prob_majority = mean(c_nat_gov >= 33) * 100
    )
  )
)

saveRDS(forecast_output, "data/prague_2026_forecast_sims.rds")

# -------------------------------------------------------------------------
# 7. Plots (Parties and Coalitions)
# -------------------------------------------------------------------------
colors <- c(
  "STAN" = "#ee0be6", "SPOLU" = "#0a2bbc", "ANO" = "#00b4d8", "Piráti" = "#111111",
  "Praha Sobě" = "#deed11", "SPD" = "#70300c", "Motoristé" = "#0edec9",
  "Spojená Levice" = "#d90429", "Ostatní" = "#888888"
)

df_plot <- tibble(
  party      = display_names,
  vote_mean  = colMeans(votes) * 100,
  vote_low   = apply(votes * 100, 2, quantile, 0.055),
  vote_high  = apply(votes * 100, 2, quantile, 0.945),
  seats_mean = colMeans(seats),
  seats_low  = apply(seats, 2, quantile, 0.055),
  seats_high = apply(seats, 2, quantile, 0.945)
) %>%
  arrange(vote_mean) %>%
  mutate(party = factor(party, levels = party))

p_vote <- ggplot(df_plot, aes(x = vote_mean, y = party, color = party)) +
  geom_vline(xintercept = 5, linetype = "dashed", color = "red") +
  geom_linerange(aes(xmin = vote_low, xmax = vote_high), linewidth = 2) +
  geom_point(size = 3.5, color = "black", fill = "white", shape = 21, stroke = 1.5) +
  geom_text(aes(label = sprintf("%.1f%%", vote_mean)), vjust = -1, size = 3.2, color = "#1a1a1a", fontface = "bold") +
  scale_color_manual(values = colors, guide = "none") +
  scale_x_continuous(limits = c(0, 26)) +
  labs(title = "Vote Share (%)", subtitle = "Point estimate & 89% CI (5% threshold in red)", x = NULL, y = NULL) +
  theme_minimal()

p_seats <- ggplot(df_plot, aes(x = seats_mean, y = party, color = party)) +
  geom_linerange(aes(xmin = seats_low, xmax = seats_high), linewidth = 2) +
  geom_point(size = 3.5, color = "black", fill = "white", shape = 21, stroke = 1.5) +
  geom_text(aes(label = sprintf("%.0f", seats_mean)), vjust = -1, size = 3.2, color = "#1a1a1a", fontface = "bold") +
  scale_color_manual(values = colors, guide = "none") +
  scale_x_continuous(limits = c(0, 22)) +
  labs(title = "Projected Seats (of 65)", subtitle = "d'Hondt allocation", x = NULL, y = NULL) +
  theme_minimal() +
  theme(axis.text.y = element_blank())

p_parties <- (p_vote | p_seats) +
  plot_annotation(
    title    = "Prague 2026 Municipal Election: Bayesian Prediction Model",
    subtitle = "Built on the Zweitstimme Bayesian Election Model: Political fundamentals + National Polls + Prague Election Polls (Ipsos, Median, SC&C)",
    caption  = "Štěpán Jabůrek | Institute of Political Studies, Charles University",
    theme    = theme(
      plot.title = element_text(face = "bold", size = 13)
    )
  )
p_parties
ggsave("prague_parties.png", p_parties, width = 10, height = 5.5, bg = "white")

# -------------------------------------------------------------------------
#  Coalition Majority Plot
# -------------------------------------------------------------------------

df_coal_plot <- tibble(
  coalition = c(
    "Current (SPOLU + STAN + Piráti)",
    "Conservative (SPOLU + ANO + Motoristé)",
    "Broad Liberal (+ Praha Sobě)",
    "Two-Party (SPOLU + STAN)",
    "National Gov Coalition (ANO + SPD + Motoristé)"
  ),
  seats_mean   = c(mean(c_incumbent), mean(c_right), mean(c_broad), mean(c_spolu_stan), mean(c_nat_gov)),
  seats_low89  = c(quantile(c_incumbent, 0.055), quantile(c_right, 0.055), quantile(c_broad, 0.055), quantile(c_spolu_stan, 0.055), quantile(c_nat_gov, 0.055)),
  seats_high89 = c(quantile(c_incumbent, 0.945), quantile(c_right, 0.945), quantile(c_broad, 0.945), quantile(c_spolu_stan, 0.945), quantile(c_nat_gov, 0.945)),
  prob_maj     = c(mean(c_incumbent >= 33), mean(c_right >= 33), mean(c_broad >= 33), mean(c_spolu_stan >= 33), mean(c_nat_gov >= 33)) * 100
) %>%
  mutate(
    coalition_label = sprintf("%s\n(%0.0f%% win prob)", coalition, prob_maj),
    coalition_label = factor(coalition_label, levels = coalition_label[order(seats_mean)]),
    has_majority    = prob_maj >= 50
  )

p_coalitions <- ggplot(df_coal_plot, aes(y = coalition_label, x = seats_mean)) +
  annotate("rect", xmin = 33, xmax = 52, ymin = -Inf, ymax = Inf, fill = "#2e7d32", alpha = 0.08) +
  geom_vline(xintercept = 33, linetype = "solid", color = "#2e7d32", linewidth = 0.8, alpha = 0.85) +
  annotate(
    "label", x = 33, y = Inf, vjust = -0.3,
    label = "33 Seats Needed for Majority",
    color = "#1b5e20", fill = "#f1f8e9", fontface = "bold", size = 3, linewidth = 0.2
  ) +
  geom_linerange(aes(xmin = seats_low89, xmax = seats_high89, color = has_majority), 
                 linewidth = 2, alpha = 0.8) +
  geom_point(size = 3.6, color = "black", fill = "white", shape = 21, stroke = 1.4) +
  geom_text(
    aes(label = sprintf("%.0f", seats_mean)),
    vjust = -1.1, size = 3.3, fontface = "bold", color = "#1a1a1a"
  ) +
  scale_color_manual(values = c("TRUE" = "#2e7d32", "FALSE" = "#6c757d"), guide = "none") +
  scale_x_continuous(limits = c(18, 52), breaks = seq(20, 50, by = 5)) +
  coord_cartesian(clip = "off") +
  labs(
    title    = "Prague Election 2026: Bayesian Coalition Prediction",
    subtitle = "Posterior seat distributions (point = mean, bar = 89% CI)",
    x        = "Combined Projected Seats (out of 65)",
    y        = NULL,
    caption  = "Štěpán Jabůrek | Institute of Political Studies, Charles University"
  ) +
theme_minimal(base_size = 11) +
  theme(
    plot.title         = element_text(face = "bold", size = 13),
    plot.subtitle      = element_text(color = "#555555", size = 9.5, margin = margin(b = 14)),
    plot.caption       = element_text(color = "#888888", size = 8, margin = margin(t = 12)),
    axis.text.y        = element_text(size = 9, color = "#222222", lineheight = 1.15),
    axis.text.x        = element_text(size = 8.5, color = "#555555"),
    plot.margin        = margin(18, 18, 12, 12)
  )

print(p_coalitions)

ggsave("prague_coalitions.png", p_coalitions, width = 8.5, height = 4.8, bg = "white")

