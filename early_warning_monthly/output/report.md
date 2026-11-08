# Monatliches Frühwarnsystem - automatischer Evaluationsbericht

_Erzeugt am 08.11.2026. Alle Kennzahlen sind echte Out-of-sample-Werte: Testmonate 01/2021 bis 06/2026, Neutraining alle 6 Monate._

## Datengrundlage

* 156 Länder (>= 1 Mio. Einwohner), Monatsdaten 01/2011 bis 09/2026
* Features: 36 strukturierte (Konflikt inkl. räumlich, Makro monatlich, Struktur) + 18 News-Features + 6 Foundation-Prognosen
* Testdaten Konflikt: 10296 Länder-Monate, davon 63 Ausbruchs-Monate in 25 Episoden
* Testdaten Währung: 9391 Länder-Monate, davon 72 Ausbruchs-Monate in 36 Episoden

## Gewaltkonflikt

| Rang | Methode | AUC Ausbrüche | KI | AUC schwierig | PR-AUC Ausbr. | Ausbrüche auf Liste | Lift | Treffer Liste | AUC alle | BSS | Kal.-Steigung |
|---|---|---|---|---|---|---|---|---|---|---|---|
|  1 | Ensemble - Hybrid (+Foundation) | 0.855 | 0.77-0.92 | 0.662 | 0.045 | 21/25 | 4.710 | 0.036 | 0.988 | 0.820 | 1.101 |
|  2 | Elastic Net - Hybrid (+Foundation) | 0.824 | 0.73-0.90 | 0.626 | 0.059 | 20/25 | 4.486 | 0.034 | 0.987 | 0.817 | 1.112 |
|  3 | Ensemble (EN+RF+GBM, mit News) | 0.842 | 0.75-0.91 | 0.662 | 0.043 | 22/25 | 4.934 | 0.036 | 0.987 | 0.811 | 1.113 |
|  4 | Boosting - Struktur, Training ab 2011 | 0.828 | 0.73-0.89 | 0.599 | 0.044 | 20/25 | 4.486 | 0.032 | 0.986 | 0.810 | 1.010 |
|  4 | Random Forest - Hybrid (+Foundation) | 0.861 | 0.79-0.92 | 0.673 | 0.043 | 19/25 | 4.261 | 0.035 | 0.987 | 0.814 | 1.127 |
|  6 | Elastic Net - Struktur | 0.824 | 0.73-0.90 | 0.639 | 0.047 | 20/25 | 4.486 | 0.033 | 0.986 | 0.806 | 1.105 |
|  7 | Random Forest - Struktur+News | 0.851 | 0.77-0.92 | 0.677 | 0.042 | 22/25 | 4.934 | 0.036 | 0.986 | 0.806 | 1.158 |
|  8 | Elastic Net - Struktur+News | 0.809 | 0.71-0.89 | 0.632 | 0.047 | 20/25 | 4.486 | 0.033 | 0.986 | 0.806 | 1.110 |
|  8 | Foundation-Stack (kalibriert) | 0.758 | 0.65-0.87 | 0.605 | 0.045 | 19/25 | 4.261 | 0.032 | 0.985 | 0.815 | 1.003 |
| 10 | Random Forest - Struktur | 0.821 | 0.72-0.90 | 0.682 | 0.039 | 19/25 | 4.261 | 0.034 | 0.986 | 0.806 | 1.103 |
| 11 | Logit (Kernvariablen) | 0.818 | 0.72-0.89 | 0.599 | 0.048 | 19/25 | 4.261 | 0.030 | 0.985 | 0.798 | 0.972 |
| 12 | Boosting - Hybrid (+Foundation) | 0.812 | 0.72-0.88 | 0.586 | 0.036 | 19/25 | 4.261 | 0.033 | 0.986 | 0.811 | 0.932 |
| 13 | Chronos-2 (zero-shot) | 0.797 | 0.70-0.88 | 0.587 | 0.047 | 18/25 | 4.037 | 0.028 | 0.985 | 0.810 | 0.929 |
| 14 | Faustregel (1 Variable) | 0.762 | 0.63-0.86 | 0.624 | 0.048 | 19/25 | 4.261 | 0.032 | 0.981 | 0.774 | 0.956 |
| 15 | Moirai-2 (zero-shot) | 0.751 | 0.66-0.83 | 0.554 | 0.038 | 20/25 | 4.486 | 0.031 | 0.984 | 0.814 | 0.853 |
| 16 | TimesFM 3 (zero-shot) | 0.733 | 0.64-0.82 | 0.600 | 0.045 | 20/25 | 4.486 | 0.031 | 0.978 | 0.767 | 0.854 |
| 17 | Boosting - Struktur+News | 0.792 | 0.69-0.88 | 0.553 | 0.034 | 19/25 | 4.261 | 0.030 | 0.984 | 0.801 | 0.926 |
| 18 | Boosting - Struktur | 0.795 | 0.70-0.87 | 0.552 | 0.033 | 19/25 | 4.261 | 0.028 | 0.985 | 0.800 | 0.925 |
| 19 | Elastic Net - nur News | 0.713 | 0.60-0.81 | 0.601 | 0.030 | 12/25 | 2.691 | 0.023 | 0.860 | 0.376 | 1.031 |
| 20 | Persistenz (naiv) | 0.307 | 0.22-0.40 | 0.288 | 0.006 | 12/25 | 2.691 | 0.011 | 0.919 | 0.729 | 0.992 |

## Währungskrise

| Rang | Methode | AUC Ausbrüche | KI | AUC schwierig | PR-AUC Ausbr. | Ausbrüche auf Liste | Lift | Treffer Liste | AUC alle | BSS | Kal.-Steigung |
|---|---|---|---|---|---|---|---|---|---|---|---|
|  1 | Boosting - Struktur, Training ab 2011 | 0.872 | 0.83-0.91 | 0.801 | 0.113 | 25/36 | 4.599 | 0.034 | 0.915 | 0.228 | 1.109 |
|  2 | Ensemble - Hybrid (+Foundation) | 0.811 | 0.73-0.87 | 0.764 | 0.066 | 21/36 | 3.863 | 0.028 | 0.893 | 0.183 | 1.088 |
|  3 | Chronos-2 (zero-shot) | 0.791 | 0.69-0.88 | 0.793 | 0.088 | 26/36 | 4.783 | 0.032 | 0.886 | 0.112 | 0.926 |
|  4 | Foundation-Stack (kalibriert) | 0.748 | 0.63-0.85 | 0.774 | 0.119 | 25/36 | 4.599 | 0.032 | 0.869 | 0.192 | 0.980 |
|  5 | Elastic Net - Hybrid (+Foundation) | 0.787 | 0.72-0.85 | 0.782 | 0.105 | 27/36 | 4.967 | 0.036 | 0.886 | 0.174 | 1.169 |
|  6 | Random Forest - Hybrid (+Foundation) | 0.790 | 0.71-0.85 | 0.744 | 0.057 | 20/36 | 3.679 | 0.027 | 0.883 | 0.131 | 0.890 |
|  7 | Ensemble (EN+RF+GBM, mit News) | 0.805 | 0.74-0.86 | 0.728 | 0.063 | 19/36 | 3.495 | 0.025 | 0.889 | 0.155 | 1.162 |
|  8 | Random Forest - Struktur+News | 0.768 | 0.69-0.84 | 0.711 | 0.061 | 18/36 | 3.311 | 0.022 | 0.872 | 0.109 | 0.908 |
|  9 | TimesFM 3 (zero-shot) | 0.676 | 0.55-0.79 | 0.740 | 0.086 | 21/36 | 3.863 | 0.025 | 0.824 | 0.177 | 1.120 |
| 10 | Random Forest - Struktur | 0.765 | 0.68-0.84 | 0.703 | 0.049 | 20/36 | 3.679 | 0.025 | 0.871 | 0.097 | 0.891 |
| 11 | Boosting - Hybrid (+Foundation) | 0.764 | 0.68-0.83 | 0.729 | 0.048 | 23/36 | 4.231 | 0.028 | 0.863 | 0.114 | 0.797 |
| 12 | Elastic Net - Struktur+News | 0.765 | 0.68-0.84 | 0.732 | 0.044 | 19/36 | 3.495 | 0.027 | 0.869 | 0.078 | 1.186 |
| 13 | Moirai-2 (zero-shot) | 0.662 | 0.54-0.78 | 0.656 | 0.041 | 20/36 | 3.679 | 0.024 | 0.827 | 0.049 | 0.950 |
| 14 | Boosting - Struktur | 0.679 | 0.57-0.76 | 0.624 | 0.043 | 18/36 | 3.311 | 0.025 | 0.833 | 0.138 | 0.833 |
| 15 | Elastic Net - Struktur | 0.707 | 0.59-0.81 | 0.660 | 0.049 | 15/36 | 2.759 | 0.024 | 0.851 | 0.083 | 1.253 |
| 16 | Logit (Kernvariablen) | 0.685 | 0.57-0.81 | 0.602 | 0.041 | 13/36 | 2.391 | 0.020 | 0.837 | 0.049 | 0.896 |
| 17 | Boosting - Struktur+News | 0.676 | 0.57-0.75 | 0.617 | 0.033 | 15/36 | 2.759 | 0.021 | 0.833 | 0.130 | 0.833 |
| 18 | Faustregel (1 Variable) | 0.669 | 0.55-0.75 | 0.531 | 0.033 | 13/36 | 2.391 | 0.021 | 0.616 | 0.015 | 1.079 |
| 19 | Persistenz (naiv) | 0.431 | 0.32-0.53 | 0.487 | 0.014 | 11/36 | 2.023 | 0.012 | 0.667 | 0.073 | 1.131 |
| 20 | Elastic Net - nur News | 0.340 | 0.26-0.43 | 0.364 | 0.006 | 11/36 | 2.023 | 0.009 | 0.425 | -0.002 | -1.187 |

_Ausbrüche = Länder, die in den 12 Monaten davor unter der Schwelle lagen. Schwierige Fälle = ruhige Länder mit Vorzeichen (Konflikt: mindestens 1 Toter in 12 Monaten; Währung: mehr als 5 % Abwertung in 12 Monaten) - hier entscheidet sich, ob ein Modell mehr kann als eine Faustregel. 'Ausbrüche auf Liste' = Episoden, bei denen das Land vorher mindestens einmal unter den Top 20 der ruhigen Länder stand. Lift = wie viel Mal mehr Ausbrüche die Liste enthält als eine Zufallsauswahl gleicher Grösse. 'Treffer Liste' = Anteil der Listenplätze mit tatsächlichem Ausbruch._

![Leistung](figures/01_performance.png)

## Was bringt welcher Baustein?

News = Wikipedia-Nachrichtenticker; Foundation = Zero-shot-Prognosen von TimesFM 3, Chronos-2 und Moirai-2 als Zusatz-Features; Faustregel = Logit mit einer einzigen Variable.

| Ziel | Baustein | Methode | Metrik | Delta | KI unten | KI oben | P(Delta>0) |
|---|---|---|---|---|---|---|---|
| Gewaltkonflikt (>= 25 Tote in 3 Monaten) | News | Elastic Net | AUC Ausbrüche | -0.014 | -0.038 | 0.006 | 0.115 |
| Gewaltkonflikt (>= 25 Tote in 3 Monaten) | News | Elastic Net | AUC schwierige Fälle | -0.007 | -0.022 | 0.005 | 0.225 |
| Gewaltkonflikt (>= 25 Tote in 3 Monaten) | News | Elastic Net | PR-AUC Ausbrüche | -0.000 | -0.002 | 0.002 | 0.375 |
| Gewaltkonflikt (>= 25 Tote in 3 Monaten) | News | Random Forest | AUC Ausbrüche | 0.029 | -0.009 | 0.076 | 0.925 |
| Gewaltkonflikt (>= 25 Tote in 3 Monaten) | News | Random Forest | AUC schwierige Fälle | -0.005 | -0.050 | 0.051 | 0.345 |
| Gewaltkonflikt (>= 25 Tote in 3 Monaten) | News | Random Forest | PR-AUC Ausbrüche | 0.004 | -0.004 | 0.009 | 0.795 |
| Gewaltkonflikt (>= 25 Tote in 3 Monaten) | News | Boosting | AUC Ausbrüche | -0.004 | -0.050 | 0.035 | 0.505 |
| Gewaltkonflikt (>= 25 Tote in 3 Monaten) | News | Boosting | AUC schwierige Fälle | 0.001 | -0.027 | 0.042 | 0.500 |
| Gewaltkonflikt (>= 25 Tote in 3 Monaten) | News | Boosting | PR-AUC Ausbrüche | 0.001 | -0.006 | 0.007 | 0.685 |
| Gewaltkonflikt (>= 25 Tote in 3 Monaten) | Foundation | Elastic Net | AUC Ausbrüche | 0.015 | -0.002 | 0.031 | 0.955 |
| Gewaltkonflikt (>= 25 Tote in 3 Monaten) | Foundation | Elastic Net | AUC schwierige Fälle | -0.006 | -0.056 | 0.022 | 0.355 |
| Gewaltkonflikt (>= 25 Tote in 3 Monaten) | Foundation | Elastic Net | PR-AUC Ausbrüche | 0.012 | -0.003 | 0.065 | 0.890 |
| Gewaltkonflikt (>= 25 Tote in 3 Monaten) | Foundation | Random Forest | AUC Ausbrüche | 0.011 | -0.005 | 0.030 | 0.870 |
| Gewaltkonflikt (>= 25 Tote in 3 Monaten) | Foundation | Random Forest | AUC schwierige Fälle | -0.004 | -0.046 | 0.032 | 0.465 |
| Gewaltkonflikt (>= 25 Tote in 3 Monaten) | Foundation | Random Forest | PR-AUC Ausbrüche | 0.001 | -0.004 | 0.010 | 0.705 |
| Gewaltkonflikt (>= 25 Tote in 3 Monaten) | Foundation | Boosting | AUC Ausbrüche | 0.021 | -0.022 | 0.073 | 0.775 |
| Gewaltkonflikt (>= 25 Tote in 3 Monaten) | Foundation | Boosting | AUC schwierige Fälle | 0.033 | -0.018 | 0.116 | 0.825 |
| Gewaltkonflikt (>= 25 Tote in 3 Monaten) | Foundation | Boosting | PR-AUC Ausbrüche | 0.002 | -0.008 | 0.010 | 0.620 |
| Gewaltkonflikt (>= 25 Tote in 3 Monaten) | Foundation | Ensemble | AUC Ausbrüche | 0.013 | -0.004 | 0.036 | 0.915 |
| Gewaltkonflikt (>= 25 Tote in 3 Monaten) | Foundation | Ensemble | AUC schwierige Fälle | -0.000 | -0.028 | 0.025 | 0.540 |
| Gewaltkonflikt (>= 25 Tote in 3 Monaten) | Foundation | Ensemble | PR-AUC Ausbrüche | 0.002 | -0.004 | 0.011 | 0.590 |
| Gewaltkonflikt (>= 25 Tote in 3 Monaten) | ML vs. Faustregel | Ensemble | AUC Ausbrüche | 0.080 | -0.024 | 0.185 | 0.920 |
| Gewaltkonflikt (>= 25 Tote in 3 Monaten) | ML vs. Faustregel | Ensemble | AUC schwierige Fälle | 0.038 | -0.059 | 0.133 | 0.710 |
| Gewaltkonflikt (>= 25 Tote in 3 Monaten) | ML vs. Faustregel | Ensemble | PR-AUC Ausbrüche | -0.005 | -0.045 | 0.010 | 0.290 |
| Gewaltkonflikt (>= 25 Tote in 3 Monaten) | Foundation vs. Faustregel | Foundation-Stack | AUC Ausbrüche | -0.004 | -0.067 | 0.078 | 0.440 |
| Gewaltkonflikt (>= 25 Tote in 3 Monaten) | Foundation vs. Faustregel | Foundation-Stack | AUC schwierige Fälle | -0.019 | -0.136 | 0.073 | 0.310 |
| Gewaltkonflikt (>= 25 Tote in 3 Monaten) | Foundation vs. Faustregel | Foundation-Stack | PR-AUC Ausbrüche | -0.003 | -0.044 | 0.056 | 0.365 |
| Währungskrise (>= 15 % Abwertung in 3 Monaten) | News | Elastic Net | AUC Ausbrüche | 0.058 | 0.019 | 0.093 | 1.000 |
| Währungskrise (>= 15 % Abwertung in 3 Monaten) | News | Elastic Net | AUC schwierige Fälle | 0.072 | 0.028 | 0.119 | 1.000 |
| Währungskrise (>= 15 % Abwertung in 3 Monaten) | News | Elastic Net | PR-AUC Ausbrüche | -0.005 | -0.043 | 0.031 | 0.420 |
| Währungskrise (>= 15 % Abwertung in 3 Monaten) | News | Random Forest | AUC Ausbrüche | 0.002 | -0.046 | 0.053 | 0.575 |
| Währungskrise (>= 15 % Abwertung in 3 Monaten) | News | Random Forest | AUC schwierige Fälle | 0.008 | -0.028 | 0.051 | 0.685 |
| Währungskrise (>= 15 % Abwertung in 3 Monaten) | News | Random Forest | PR-AUC Ausbrüche | 0.012 | -0.002 | 0.031 | 0.900 |
| Währungskrise (>= 15 % Abwertung in 3 Monaten) | News | Boosting | AUC Ausbrüche | -0.003 | -0.043 | 0.052 | 0.465 |
| Währungskrise (>= 15 % Abwertung in 3 Monaten) | News | Boosting | AUC schwierige Fälle | -0.008 | -0.053 | 0.050 | 0.410 |
| Währungskrise (>= 15 % Abwertung in 3 Monaten) | News | Boosting | PR-AUC Ausbrüche | -0.010 | -0.034 | 0.001 | 0.050 |
| Währungskrise (>= 15 % Abwertung in 3 Monaten) | Foundation | Elastic Net | AUC Ausbrüche | 0.022 | -0.064 | 0.112 | 0.685 |
| Währungskrise (>= 15 % Abwertung in 3 Monaten) | Foundation | Elastic Net | AUC schwierige Fälle | 0.050 | -0.056 | 0.163 | 0.760 |
| Währungskrise (>= 15 % Abwertung in 3 Monaten) | Foundation | Elastic Net | PR-AUC Ausbrüche | 0.062 | -0.007 | 0.141 | 0.955 |
| Währungskrise (>= 15 % Abwertung in 3 Monaten) | Foundation | Random Forest | AUC Ausbrüche | 0.022 | -0.015 | 0.065 | 0.855 |
| Währungskrise (>= 15 % Abwertung in 3 Monaten) | Foundation | Random Forest | AUC schwierige Fälle | 0.033 | -0.029 | 0.075 | 0.890 |
| Währungskrise (>= 15 % Abwertung in 3 Monaten) | Foundation | Random Forest | PR-AUC Ausbrüche | -0.004 | -0.026 | 0.023 | 0.480 |
| Währungskrise (>= 15 % Abwertung in 3 Monaten) | Foundation | Boosting | AUC Ausbrüche | 0.088 | 0.034 | 0.157 | 1.000 |
| Währungskrise (>= 15 % Abwertung in 3 Monaten) | Foundation | Boosting | AUC schwierige Fälle | 0.112 | 0.007 | 0.205 | 0.985 |
| Währungskrise (>= 15 % Abwertung in 3 Monaten) | Foundation | Boosting | PR-AUC Ausbrüche | 0.016 | -0.033 | 0.054 | 0.770 |
| Währungskrise (>= 15 % Abwertung in 3 Monaten) | Foundation | Ensemble | AUC Ausbrüche | 0.006 | -0.028 | 0.033 | 0.630 |
| Währungskrise (>= 15 % Abwertung in 3 Monaten) | Foundation | Ensemble | AUC schwierige Fälle | 0.037 | -0.025 | 0.081 | 0.900 |
| Währungskrise (>= 15 % Abwertung in 3 Monaten) | Foundation | Ensemble | PR-AUC Ausbrüche | 0.003 | -0.062 | 0.049 | 0.590 |
| Währungskrise (>= 15 % Abwertung in 3 Monaten) | ML vs. Faustregel | Ensemble | AUC Ausbrüche | 0.136 | 0.032 | 0.246 | 0.995 |
| Währungskrise (>= 15 % Abwertung in 3 Monaten) | ML vs. Faustregel | Ensemble | AUC schwierige Fälle | 0.197 | -0.035 | 0.450 | 0.935 |
| Währungskrise (>= 15 % Abwertung in 3 Monaten) | ML vs. Faustregel | Ensemble | PR-AUC Ausbrüche | 0.030 | -0.017 | 0.120 | 0.785 |
| Währungskrise (>= 15 % Abwertung in 3 Monaten) | Foundation vs. Faustregel | Foundation-Stack | AUC Ausbrüche | 0.079 | -0.073 | 0.231 | 0.870 |
| Währungskrise (>= 15 % Abwertung in 3 Monaten) | Foundation vs. Faustregel | Foundation-Stack | AUC schwierige Fälle | 0.242 | 0.026 | 0.454 | 0.985 |
| Währungskrise (>= 15 % Abwertung in 3 Monaten) | Foundation vs. Faustregel | Foundation-Stack | PR-AUC Ausbrüche | 0.086 | 0.007 | 0.171 | 0.985 |

![Mehrwert](figures/02_value_added.png)

## Diagnostik

![Kalibrierung](figures/03_calibration.png)

![Zeit](figures/04_auc_over_time.png)

![Treiber](figures/05_drivers.png)

![Fälle](figures/06_case_studies.png)

## Beobachtungsliste 10/2026 bis 12/2026

![Watchlist](figures/07_watchlist.png)

### Gewaltkonflikt - Frühwarnung (derzeit ruhige Länder)

| Land | Region | Risiko Ensemble | Elastic Net | Random Forest | Boosting | Hybrid-Ensemble | Chronos-2 | TimesFM 3 | Moirai-2 |
|---|---|---|---|---|---|---|---|---|---|
| Uganda | Sub-Saharan Africa  | 0.067 | 0.074 | 0.046 | 0.079 | 0.058 | 0.006 | 0.028 | 0.031 |
| Oman | Middle East, North Africa, Afghanistan & Pakistan | 0.055 | 0.017 | 0.120 | 0.027 | 0.046 | 0.038 | 0.056 | 0.032 |
| Turkiye | Europe & Central Asia | 0.043 | 0.062 | 0.036 | 0.032 | 0.030 | 0.018 | 0.035 | 0.057 |
| Cote d'Ivoire | Sub-Saharan Africa  | 0.041 | 0.022 | 0.067 | 0.035 | 0.050 | 0.068 | 0.081 | 0.118 |
| United States | North America | 0.034 | 0.024 | 0.050 | 0.029 | 0.030 | 0.036 | 0.018 | 0.018 |
| Peru | Latin America & Caribbean  | 0.033 | 0.032 | 0.037 | 0.029 | 0.021 | 0.024 | 0.053 | 0.049 |
| Nepal | South Asia | 0.026 | 0.014 | 0.056 | 0.009 | 0.022 | 0.031 | 0.005 | 0.027 |
| Dominican Republic | Latin America & Caribbean  | 0.025 | 0.026 | 0.023 | 0.026 | 0.019 | 0.037 | 0.020 | 0.005 |
| Djibouti | Middle East, North Africa, Afghanistan & Pakistan | 0.024 | 0.016 | 0.035 | 0.021 | 0.023 | 0.002 | 0.000 | 0.000 |
| Spain | Europe & Central Asia | 0.024 | 0.015 | 0.049 | 0.008 | 0.020 | 0.043 | 0.062 | 0.001 |
| Kuwait | Middle East, North Africa, Afghanistan & Pakistan | 0.023 | 0.018 | 0.033 | 0.016 | 0.023 | 0.081 | 0.000 | 0.025 |
| Algeria | Middle East, North Africa, Afghanistan & Pakistan | 0.023 | 0.028 | 0.006 | 0.034 | 0.027 | 0.010 | 0.023 | 0.024 |
| United Arab Emirates | Middle East, North Africa, Afghanistan & Pakistan | 0.022 | 0.012 | 0.029 | 0.024 | 0.019 | 0.005 | 0.000 | 0.000 |
| Jordan | Middle East, North Africa, Afghanistan & Pakistan | 0.021 | 0.014 | 0.040 | 0.008 | 0.022 | 0.050 | 0.049 | 0.052 |
| Argentina | Latin America & Caribbean  | 0.017 | 0.014 | 0.013 | 0.023 | 0.015 | 0.008 | 0.000 | 0.013 |

### Währungskrise - Frühwarnung (derzeit ruhige Länder)

| Land | Region | Risiko Ensemble | Elastic Net | Random Forest | Boosting | Hybrid-Ensemble | Chronos-2 | TimesFM 3 | Moirai-2 |
|---|---|---|---|---|---|---|---|---|---|
| Nigeria | Sub-Saharan Africa  | 0.045 | 0.024 | 0.077 | 0.035 | 0.030 | - | - | - |
| Russian Federation | Europe & Central Asia | 0.041 | 0.010 | 0.064 | 0.050 | 0.019 | - | - | - |
| Congo, Dem. Rep. | Sub-Saharan Africa  | 0.031 | 0.034 | 0.037 | 0.024 | 0.026 | - | - | - |
| Turkiye | Europe & Central Asia | 0.027 | 0.012 | 0.043 | 0.027 | 0.029 | - | - | - |
| Ethiopia | Sub-Saharan Africa  | 0.026 | 0.026 | 0.042 | 0.010 | 0.026 | - | - | - |
| Zambia | Sub-Saharan Africa  | 0.025 | 0.016 | 0.045 | 0.016 | 0.010 | - | - | - |
| Bulgaria | Europe & Central Asia | 0.024 | 0.006 | 0.046 | 0.019 | 0.029 | - | - | - |
| Lebanon | Middle East, North Africa, Afghanistan & Pakistan | 0.022 | 0.012 | 0.042 | 0.013 | 0.017 | - | - | - |
| Ghana | Sub-Saharan Africa  | 0.022 | 0.009 | 0.046 | 0.010 | 0.010 | - | - | - |
| Mali | Sub-Saharan Africa  | 0.021 | 0.016 | 0.037 | 0.008 | 0.020 | - | - | - |
| Ukraine | Europe & Central Asia | 0.019 | 0.010 | 0.027 | 0.020 | 0.014 | - | - | - |
| Egypt, Arab Rep. | Middle East, North Africa, Afghanistan & Pakistan | 0.017 | 0.012 | 0.021 | 0.018 | 0.010 | - | - | - |
| Pakistan | Middle East, North Africa, Afghanistan & Pakistan | 0.017 | 0.014 | 0.028 | 0.008 | 0.027 | - | - | - |
| Madagascar | Sub-Saharan Africa  | 0.016 | 0.026 | 0.013 | 0.008 | 0.008 | - | - | - |
| Argentina | Latin America & Caribbean  | 0.015 | 0.020 | 0.018 | 0.008 | 0.008 | - | - | - |
