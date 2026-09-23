# Prague 2026 Municipal Election: Bayesian Prediction Model

Largely inspired by the *Zweitstimme* Election Model by Stoetzer et al. (2019, 2025) and the Gelman and King (1993) approach to predicting elections, adapted with Gaussian Processes, Ordered Beta Regression, and modeling strategies tailored to sparse local polling data in Prague.

---

## Core Components

- **1. Fundamentals Model (Ordered Beta Regression)**  
  Predicts municipal vote shares in Prague based on historical election results and broader political dynamics.
  - **1a. Latent National Polling:** Gaussian Process (GP) regression modeling continuous national party support trends over time.
  - **1b. Prague-Specific Elasticity of National Support:** Elasticity coefficients derived from relative party performance in Prague vs. nationwide results in Parliamentary elections.
  - **1c. Prague Historical Fundamentals:** Predictors capturing long-term baseline divergence (Prague vs. national vote), mayoral incumbency advantages, governing coalition membership, and new party entry dynamics.

- **2. Local Polling Update (Exact Conjugate Dirichlet)**  
  Bayesian updating using an exact Dirichlet-Multinomial conjugate framework to combine the fundamentals-based prior with available Prague municipal polling (e.g., Ipsos, Median, SC&C).

- **3. Seat Allocation Simulation**  
  Full probabilistic simulation of seat counts across the Prague City Assembly:
  - Enforces the statutory 5% threshold for entering the assembly.
  - Allocates seats via the standard d'Hondt method across posterior draws.

---

## Data Origins

- **National Polls:** Aggregated from [mandaty.cz](https://mandaty.cz/).
- **Local Polls:** Systematic manual extraction and harmonization from published polling releases and media reports.
- **Historical Fundamentals:** Manually compiled and standardized dataset of historical municipal, regional, and parliamentary election results.

---

**Author:** Štěpán Jabůrek  
**Affiliation:** Institute of Political Studies, Faculty of Social Sciences, Charles University  
