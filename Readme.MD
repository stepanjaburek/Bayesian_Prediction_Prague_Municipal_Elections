# Prague 2026 Municipal Election: Bayesian Prediction Model

Largely inspired by the *Zweitstimme* Election Model by Stoetzer et al. (2019, 2025) and the Gelman and King (1993) approach to predicting elections. But adapted with Gaussian Processes, Ordered Beta Regression, and modeling strategies for even less polling data in Prague.

---

## Core Components

- **1. Fundamentals Model using Ordered Beta Regression**  
  Predicts municipal vote shares in Prague based on historical election results and broader political dynamics.
  - **1a. Latent National Polling:** Gaussian Process (GP) regression modeling national party support trends
  - **1b. Prague-Specific Elasticity of National Support:** Elasticity coefficients derived from party performance in Prague vs. nationwide results in Parliamentary elections.
  - **1c. Prague Historical Fundamentals:** Prague vs. National vote share, Mayor incumbency, coalition membership, new party status
  - **1d.** Fit model on data until 2022. Then posterior predict 2026.


- **2. Local Prague Polling Update (Dirichlet–Multinomial conjugate update)**  
  (1) using the Fundamentals prediction as a prior, and (2) Local Prague Polls (Ipsos, Median, SC&C) as the likelihood.

- **3. Seat Allocation Simulation**  
  Probabilistic simulation of seat counts in the Prague City Assembly via d'Hondt and a  5% threshold 

---

## Data Origins

- **National Polls:** Aggregated from [mandaty.cz](https://mandaty.cz/).
- **Local Polls:** Manual extraction from published polling releases and media reports.
- **Historical Fundamentals:** Manually compiled dataset of past municipal and parliamentary election results.

---

Gelman, Andrew, and Gary King. “Why Are American Presidential Election Campaign Polls So Variable When Votes Are So Predictable?” British Journal of Political Science 23, no. 4 (1993): 409–51. https://doi.org/10.1017/S0007123400006682.

Stoetzer, Lukas F., Marcel Neunhoeffer, Thomas Gschwend, Simon Munzert, and Sebastian Sternberg. “Forecasting Elections in Multiparty Systems: A Bayesian Approach Combining Polls and Fundamentals.” Political Analysis 27, no. 2 (2019): 255–62. https://doi.org/10.1017/pan.2018.49.

Lukas F. Stoetzer, Cornelius Erfort, Hannah Rajski, Thomas Gschwend, Simon Munzert, Elias Koch. “An election forecasting model for subnational elections.“ Electoral Studies, Volume 95, (2025), https://doi.org/10.1016/j.electstud.2025.102939.

---

Štěpán Jabůrek

Institute of Political Studies, Charles University  
