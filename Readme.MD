# Prague 2026 Municipal Election: Bayesian Prediction Model

Largely inspired by the Zweitstimme Election Model by Stoetzer et al. (2019, 2025) and the Gelman and King (1993) approach to predicting elections.
But with big  changes (GPs, Ordered Beta Regression, even less local polling data in Prague)

## Core Components:
1. Fundamentals Model (Ordered Beta Regression) for Prague based on historical election data and national trends

 1a. Latent national polling (Gaussian Processes)

1b. Prague-specific elasticity of national support (based on Prague vs. National party performance in Parliamentary elections)

1c. Historical fundamentals of Prague  (Prague vs. National vote share, Mayor incumbency, coalition membership, new party status)

2. Local Polling Update (Exact Conjugate Dirichlet) for Prague based on the latest polling data (Ipsos, Median, SC&C)
3. Seat allocation simulation (d'Hondt, 5% threshold)

## Data Origins
1. National Polls from https://mandaty.cz/ aggregator
2. Local Polls from manual scrape of news reports (no nice outputs)
3. Historical Fundamentals manual creation from past elections

 Štěpán Jabůrek
 Institute of Political Studies, Charles University
