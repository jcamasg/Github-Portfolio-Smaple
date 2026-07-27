.PHONY: payments agrifood vocational compile

payments:
	cd projects/01_ecb_payments_statistics && \
	python payments_statistics_pipeline.py all --profile ci

agrifood:
	cd projects/02_bde_agrifood_climate && \
	python agrifood_climate_econometrics.py --profile ci

vocational:
	cd projects/03_government_vocational_training_prtr && \
	python vocational_training_prtr_evaluation.py --profile ci

compile:
	python -m py_compile \
	projects/01_ecb_payments_statistics/payments_statistics_pipeline.py \
	projects/02_bde_agrifood_climate/agrifood_climate_econometrics.py \
	projects/03_government_vocational_training_prtr/vocational_training_prtr_evaluation.py
