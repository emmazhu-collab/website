# Blog 6: Does One Year of Income Tell the Whole Story?

This post uses real PSID data to compare single-year and three-year-average earnings elasticities for birth fathers and their adult children. A second comparison follows the same younger children at two career stages. Python reads the files, SQLite matches people and calculates averages, and Python estimates the slopes and saves the figures.


The article is a six-step tutorial: obtain the inputs, prepare the data with Python, match IDs with SQL, calculate average income, compare IGE estimates, and check life-cycle bias. Detailed setup and reproduction instructions stay in this README. The short article examples assume the preparation steps have run; use the complete script for reproduction.

## Files

- `index.qmd`: article text. Edit this file directly.
- `code/analysis.py`: reads the original files and runs the analysis.
- `sql/build_sample.sql`: actual matching, role assignment, age restrictions, and income aggregation.
- `data/cpi_monthly.csv`: saved BLS CPI series from FRED, January 2010–December 2022.
- `results/elasticities.csv`: slopes, intercepts, intervals, and sample counts.
- `results/year_sensitivity.csv`: nine income-year combinations for identical pairs.
- `results/life_cycle.csv`: the younger group's early and later estimates and median earnings.
- `results/sample_counts.csv` and `matching_checks.json`: sample and matching checks.
- `results/summary.json`: numbers used in the article.
- `results/figures/`: the three PNG figures used in the article.

The SQLite database is created in memory on every run. It contains individual records temporarily, but the script does not save or publish those records. Saved outputs are aggregate results only.

## Data sources and inputs

Get PSID files from https://simba.isr.umich.edu/Zips/ZipMain.aspx using your own registered account. The current local inputs are in `6400 R/blog6/data/raw`, beside the website project. Original files are not changed or copied into the website.

Required layout inside that input folder:

```text
pid23/PID23.txt
pid23/PID23.do
ind2023er/IND2023ER.txt
ind2023er/IND2023ER.do
J366467.xlsx
```

Keep the supplied codebooks and labels with your originals. The script reads only the needed fixed-width columns, using positions from the `.do` files. It reads numeric Excel cells directly because the PSID workbook has a nonstandard worksheet attribute that some Excel libraries reject.

Child identifiers are `PID2` and `PID3`; birth-father identifiers are `PID23` and `PID24`. They match Individual File `ER30001` and `ER30002`. The combined numeric key is family ID times 1,000 plus person number. Missing or unknown father IDs are excluded, and both people must have records supporting the required income observations.

Income columns are documented in `J366467_labels.txt`. The main comparison uses father income in 2010/2012/2014 and child income in 2018/2020/2022. The 2016 income fields are available but not used. The 2014 child observation is used for the career-stage check. Only Reference Person earnings are available for 2010 and 2012; later waves also have Spouse/Partner earnings.

CPI source: https://fred.stlouisfed.org/series/CPIAUCNS. Download URL: https://fred.stlouisfed.org/graph/fredgraph.csv?id=CPIAUCNS&cosd=2010-01-01&coed=2022-12-31. Retrieved October 20, 2026. The script checks that every annual CPI average contains 12 months and converts all earnings to 2022 dollars. Normal reproduction uses the saved CSV and needs no internet connection.

## Replication instructions

Use Python 3 with `pandas`, `numpy`, and `matplotlib`. RStudio’s Python Console, Terminal, and Jupyter may use different Python environments. Install dependencies with the same interpreter you use to run the script. The standalone Blog 6 README includes the author’s tested Anaconda command. SQLite and the file-reading tools are included with Python. If these packages are missing, install them in the Python environment you plan to use:

```sh
python3 -m pip install pandas numpy matplotlib
```

Open the website project in RStudio. In **Terminal**, with the website folder as the working directory, copy only this command (not the backticks):

```sh
python3 blog/posts/post6/code/analysis.py
```

This rebuilds the aggregate tables and figures. It does not change the article. It reads the original PSID files from the sibling `blog6/data/raw` folder. For a different input location, use:

```sh
PSID_DATA_DIR="/full/path/to/your/PSID/files" python3 blog/posts/post6/code/analysis.py
```

Do not paste a Terminal command into the R Console. To use Jupyter, select a Python kernel with the same packages, open the notebook in the website folder, and run this in one cell:

```python
%run blog/posts/post6/code/analysis.py
```

For another data location, set `os.environ['PSID_DATA_DIR']` before `%run`. Running the whole script is required; do not start with a middle section. To change article wording, edit `index.qmd` directly. If you rerun the analysis with different inputs, check the article numbers against the saved results.

Once analysis succeeds, open `blog/posts/post6/index.qmd` in RStudio and click **Render**, or run this in Terminal when Quarto is on PATH:

```sh
quarto render blog/posts/post6/index.qmd
```

Render uses the saved article and images; it does not rerun Python or download data. The webpage has prose and figures, with SQL examples displayed directly in the article. Output goes to `docs/blog/posts/post6/index.html`. Rendering does not publish or commit anything.

## Sample and interpretation

Both main estimates use 336 complete pairs and 238 fathers. Every father must have positive earnings and interview age 35–60 in all three father waves; every child must have positive earnings and interview age 30–50 in all three child waves. The life-cycle check uses 140 of these pairs with positive child earnings in 2014 and interview age 22–29 in 2015. Ages refer to interviews, one year after the income year.

The income measure excludes farm and unincorporated business income; PSID imputes missing components. Role 10 and sequence 1 receive Reference Person earnings. Current members with role 20 or 22 receive Spouse/Partner earnings when available. Other roles are never assigned the Reference Person's income. Unsupported roles, missing income, and zero income do not enter the log regressions. Special income codes outside 0–9,999,997 are excluded before inflation adjustment.

The slope is OLS of log child earnings on log father earnings with an intercept. Multi-year income is the arithmetic average of real earnings, followed by its logarithm. All estimates are unweighted descriptions of this selected sample, not national estimates or causal effects. Intervals use 1,000 bootstrap samples of fathers, keeping their sampled children together; the random seed is 6400. Differences use paired bootstrap draws. This extra uncertainty calculation does not change the SQL matching or OLS estimate.

Averaging may reduce temporary income variation. It does not remove life-cycle bias. In the age comparison, calendar time changes too, so the difference cannot be attributed only to aging. Neither difference interval rules out zero. The article also discusses positive-income selection, attrition, role changes, and unequal ages across generations.
