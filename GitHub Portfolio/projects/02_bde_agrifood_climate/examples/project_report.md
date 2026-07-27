# Agri-food Price Transmission and Climate Risk

**Author: Jose Camas Garrdiow**

This independent project uses generated producer, processor, retail, input-cost,
commodity, output and climate series. It contains no Banco de España, FAO or
NOAA microdata and its coefficients are not institutional results.

## Scale

- Harmonised country-product-month rows: 1,440
- Error-correction terms: 17
- VAR impulse-response rows: 76
- Panel local-projection horizons: 13

## Model diagnostics

```text
                      model country product  observations  r_squared  durbin_watson  condition_number
           error_correction      ES cereals           115   0.468814       0.835616          6.115297
asymmetric_error_correction      ES cereals           115   0.512855       0.891322               NaN
        panel_fixed_effects     all     all          1428   0.668826       1.928321         40.429456
           reduced_form_var      ES cereals           117        NaN            NaN               NaN
```

## Acceptance checks

```text
                        check status                                                                                                                                                                     observed                    expected
     source_keys_and_coverage   pass                                                                                                                                                                            0                  0 failures
       monthly_panel_nonempty   pass                                                                                                                                                                         1440                         > 0
          ecm_adjustment_term   pass                                                                                                                                                                            1                           1
asymmetric_pass_through_terms   pass                                                                                                                                                                           17 positive and negative terms
    local_projection_horizons   pass [np.int64(0), np.int64(1), np.int64(2), np.int64(3), np.int64(4), np.int64(5), np.int64(6), np.int64(7), np.int64(8), np.int64(9), np.int64(10), np.int64(11), np.int64(12)]                0 through 12
    panel_coefficients_finite   pass                                                                                                                                                                         True                        True
       var_responses_nonempty   pass                                                                                                                                                                           76                         > 0
```

## Interpretation

The project demonstrates time-series harmonisation, cointegration,
error-correction, asymmetric pass-through, VARs, local projections and
fixed-effects estimation. Synthetic estimates should not be interpreted as
evidence about observed countries or products.
