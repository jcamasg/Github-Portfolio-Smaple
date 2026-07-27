# Upload to GitHub

1. Extract the ZIP.
2. Create an empty GitHub repository without automatically adding a README,
   licence or `.gitignore`.
3. Upload the contents of the extracted
   `jose-camas-garrdiow-applied-economics-portfolio/` folder.
4. Commit to `main`.
5. Open the Actions tab. Three separate Python jobs should appear: payments,
   agri-food and vocational training.

Local command-line alternative:

```bash
git init
git branch -M main
git add .
git commit -m "Add independent applied economics projects"
git remote add origin https://github.com/YOUR-USERNAME/YOUR-REPOSITORY.git
git push -u origin main
```

Suggested repository description:

> Four independent research projects in payments statistics, banking,
> agri-food prices, climate risk and vocational-training policy evaluation.

Suggested topics:

`econometrics`, `payments`, `banking`, `python`, `r`, `official-statistics`,
`policy-evaluation`, `time-series`, `climate-economics`
