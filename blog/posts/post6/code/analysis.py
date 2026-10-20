"""Run from any directory: python path/to/code/analysis.py.
Raw PSID files stay in the standalone blog6 directory; override with PSID_DATA_DIR.
Only aggregate outputs are written here. No raw microdata are redistributed.
"""
from pathlib import Path
import os, re, sqlite3, json, zipfile, xml.etree.ElementTree as ET
import numpy as np
import pandas as pd
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

POST = Path(__file__).resolve().parents[1]
RAW = Path(os.environ.get('PSID_DATA_DIR', str(POST.parents[3] / 'blog6' / 'data/raw')))
OUT = POST / 'results'
FIG = OUT / 'figures'
FIG.mkdir(parents=True, exist_ok=True)

# PSID's supplied Stata statements define fixed-width column positions.
def read_fixed(stem, variables):
    definition = stem.with_suffix('.do').read_text()
    ranges = {v: (int(a)-1, int(b)) for v,a,b in re.findall(r'\b((?:ER|PID)\d+)\s+(\d+)\s*-\s*(\d+)', definition.split('using')[0])}
    assert all(v in ranges for v in variables)
    rows=[]
    with stem.with_suffix('.txt').open() as f:
        for line in f:
            rows.append([int(line[s:e].strip() or 0) for s,e in (ranges[v] for v in variables)])
    return pd.DataFrame(rows, columns=variables)

# The PSID workbook has a nonstandard sheetPr attribute which openpyxl rejects.
# Read its original numeric cells and shared-string header without changing it.
def read_income(path):
    ns={'m':'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}
    with zipfile.ZipFile(path) as z:
        strings=[''.join(n.itertext()).strip() for n in ET.fromstring(z.read('xl/sharedStrings.xml'))]
        rows=[]
        for row in ET.fromstring(z.read('xl/worksheets/sheet1.xml')).findall('.//m:sheetData/m:row', ns):
            vals=[None]*26
            for cell in row:
                col=re.match('[A-Z]+',cell.attrib['r'])[0]
                index=0
                for c in col: index=index*26+ord(c)-64
                val=cell.find('m:v',ns)
                if val is not None:
                    vals[index-1]=strings[int(val.text)] if cell.get('t')=='s' else float(val.text)
            rows.append(vals)
    return pd.DataFrame(rows[1:],columns=rows[0])

# Interview year, individual prefix, age field, family ID, RP earnings, spouse earnings.
waves=[(2011,'ER341','ER34104','ER47302','ER52237',None),
       (2013,'ER342','ER34204','ER53002','ER58038',None),
       (2015,'ER343','ER34305','ER60002','ER65216','ER65244'),
       (2019,'ER347','ER34704','ER72002','ER77315','ER77343'),
       (2021,'ER349','ER34904','ER78002','ER81642','ER81670'),
       (2023,'ER351','ER35104','ER82002','ER85496','ER85524')]
variables=['ER30001','ER30002']
for _,prefix,age,*_ in waves: variables.extend([prefix+'01',prefix+'02',prefix+'03',age])
ind=read_fixed(RAW/'ind2023er/IND2023ER',variables)
assert not ind.duplicated(['ER30001','ER30002']).any()
ind['person']=ind.ER30001*1000+ind.ER30002
pid=read_fixed(RAW/'pid23/PID23',['PID2','PID3','PID23','PID24'])
links=pd.DataFrame({'child':pid.PID2*1000+pid.PID3,'father':pid.PID23*1000+pid.PID24})
links=links[(pid.PID23>0)&(pid.PID24.between(1,995))].drop_duplicates()
assert not links.child.duplicated().any()
assert ind.ER30001.gt(0).all() and ind.ER30002.between(1,995).all()
income=read_income(RAW/'J366467.xlsx')
family=[]; people=[]
for wave,prefix,age,fid,rp,sp in waves:
    cols=[fid,rp]+([sp] if sp else [])
    f=income[cols].dropna(subset=[fid]).query(f'{fid} > 0').drop_duplicates()
    assert not f[fid].duplicated().any(), f'Duplicate family ID {wave}'
    for _,r in f.iterrows():
        family.append([wave,int(r[fid]),r[rp],r[sp] if sp else None])
    p=ind[['person',prefix+'01',prefix+'02',prefix+'03',age]].copy()
    p.columns=['person','family','sequence','role','age']
    p['wave']=wave
    people.append(p)
family=pd.DataFrame(family,columns=['wave','family','rp_income','spouse_income'])
for col in ['rp_income','spouse_income']:
    family.loc[~family[col].between(0,9999997),col]=np.nan
people=pd.concat(people,ignore_index=True)

cpi=pd.read_csv(POST/'data/cpi_monthly.csv')
cpi['year']=pd.to_datetime(cpi.iloc[:,0]).dt.year
cpi['cpi']=pd.to_numeric(cpi['CPIAUCNS'],errors='coerce')
annual=cpi.groupby('year').agg(cpi=('cpi','mean'),months=('cpi','count')).reset_index()
assert (annual.months==12).all()
annual['factor']=float(annual.loc[annual.year==2022,'cpi'].iloc[0])/annual.cpi
con=sqlite3.connect(':memory:')
for name,df in [('people',people),('family_income',family),('parent_links',links),('cpi',annual)]: df.to_sql(name,con,index=False)
con.executescript((POST/'sql/build_sample.sql').read_text())
assert con.execute('SELECT COUNT(*) FROM (SELECT person,year FROM earnings GROUP BY person,year HAVING COUNT(*)>1)').fetchone()[0]==0
checks={
 'person_wave_rows':len(people), 'family_wave_rows':len(family),
 'person_family_join_rows':con.execute('SELECT COUNT(*) FROM people p JOIN family_income f ON p.wave=f.wave AND p.family=f.family WHERE p.family>0').fetchone()[0],
 'links_with_both_individual_records':con.execute('SELECT COUNT(*) FROM parent_links l WHERE l.child IN (SELECT person FROM people) AND l.father IN (SELECT person FROM people)').fetchone()[0],
 'eligible_member_rows':con.execute('SELECT COUNT(*) FROM earnings').fetchone()[0],
 'unavailable_or_unsupported_role_income':con.execute('SELECT COUNT(*) FROM earnings WHERE real_income IS NULL').fetchone()[0],
 'zero_income_member_rows':con.execute('SELECT COUNT(*) FROM earnings WHERE real_income=0').fetchone()[0],
 'duplicate_person_year_keys':0, 'duplicate_family_year_keys':0}
(OUT/'matching_checks.json').write_text(json.dumps(checks,indent=2)+'\n')
sample=pd.read_sql_query('SELECT * FROM matched_pairs ORDER BY child',con)
assert len(sample)>30, 'Too few matched pairs to continue.'
assert not sample.child.duplicated().any()
assert (sample.father!=sample.child).all()

# All comparisons use these same complete pairs. Cluster bootstrap by father
# keeps siblings together when measuring uncertainty.
def slope(x,y):
    x=np.log(np.asarray(x));y=np.log(np.asarray(y))
    return float(np.sum((x-x.mean())*(y-y.mean()))/np.sum((x-x.mean())**2))
models=[('Single year: 2012 / 2020','f2012','c2020'),('Three-year averages','father_mean','child_mean')]
rng=np.random.default_rng(6400)
clusters=[g.index.to_numpy() for _,g in sample.groupby('father')]
boot=[]
for _ in range(1000):
    idx=np.concatenate([clusters[i] for i in rng.integers(0,len(clusters),len(clusters))])
    b=sample.iloc[idx]
    boot.append([slope(b[x],b[y]) for _,x,y in models])
boot=np.array(boot)
estimates=[]
for i,(name,x,y) in enumerate(models):
    lo,hi=np.quantile(boot[:,i],[.025,.975])
    estimates.append({'measure':name,'estimate':slope(sample[x],sample[y]),'intercept':float(np.log(sample[y]).mean()-slope(sample[x],sample[y])*np.log(sample[x]).mean()),'low':lo,'high':hi,'pairs':len(sample),'fathers':len(clusters)})
est=pd.DataFrame(estimates)
est.to_csv(OUT/'elasticities.csv',index=False)
changes=boot[:,1]-boot[:,0]
sensitivity=[]
for fy in [2010,2012,2014]:
    for cy in [2018,2020,2022]:
        sensitivity.append({'father_year':fy,'child_year':cy,'estimate':slope(sample[f'f{fy}'],sample[f'c{cy}'])})
sens=pd.DataFrame(sensitivity);sens.to_csv(OUT/'year_sensitivity.csv',index=False)

summary={'pairs':len(sample),'fathers':len(clusters),'difference':est.estimate.iloc[1]-est.estimate.iloc[0],
 'difference_low':float(np.quantile(changes,.025)),'difference_high':float(np.quantile(changes,.975)),
 'father_age_mean':sample.father_age.mean(),'child_age_mean':sample.child_age.mean(),
 'single_min':sens.estimate.min(),'single_max':sens.estimate.max(),
 'income_definition':'Labor income excluding farm and unincorporated business income',
 'age_rule':'Interview age 35-60 in all father waves; 30-50 in all child waves',
 'weights':'Unweighted; descriptive selected sample, not a national estimate'}
# Anonymous summaries only; never save person IDs or the matched microdata.
flow=[]
for name,query in [('Individuals','SELECT COUNT(DISTINCT person) FROM people'),('Birth-father links','SELECT COUNT(*) FROM parent_links'),('Fathers with three valid years','SELECT COUNT(*) FROM father_means'),('Children with three valid years','SELECT COUNT(*) FROM child_means'),('Matched complete pairs','SELECT COUNT(*) FROM matched_pairs')]:
 flow.append({'stage':name,'count':con.execute(query).fetchone()[0]})
pd.DataFrame(flow).to_csv(OUT/'sample_counts.csv',index=False)
(OUT/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
plt.rcParams.update({'font.size':11,'axes.spines.top':False,'axes.spines.right':False})
colors=['#286789','#c27636']
fig,ax=plt.subplots(figsize=(8,4.8))
for i,r in est.iterrows():
 ax.errorbar(r.estimate,i,xerr=[[r.estimate-r.low],[r.high-r.estimate]],fmt='o',color=colors[i],capsize=5,markersize=8)
 ax.annotate(f'{r.estimate:.2f}',(r.estimate,i),xytext=(0,13),textcoords='offset points',ha='center')
ax.set_yticks([0,1],[m[0] for m in models]);ax.set_ylim(-.5,1.5);ax.axvline(0,color='gray',lw=.8)
ax.set_xlabel('Intergenerational earnings elasticity');ax.set_title('Does averaging change the earnings link?')
fig.text(.02,.02,f'PSID | {len(sample):,} pairs | 95% father-cluster bootstrap intervals | Unweighted',fontsize=9)
fig.tight_layout(rect=(0,.06,1,1));fig.savefig(FIG/'income-measures.png',dpi=180);plt.close(fig)

fig,ax=plt.subplots(figsize=(7,4.8))
matrix=sens.pivot(index='father_year',columns='child_year',values='estimate')
im=ax.imshow(matrix,cmap='YlGnBu',vmin=0,vmax=max(.5,matrix.to_numpy().max()))
for i in range(3):
 for j in range(3):ax.text(j,i,f'{matrix.iloc[i,j]:.2f}',ha='center',va='center',color='black')
ax.set_xticks(range(3),matrix.columns);ax.set_yticks(range(3),matrix.index)
ax.set_xlabel('Child income year');ax.set_ylabel('Father income year');ax.set_title('The selected year changes the estimate')
fig.colorbar(im,ax=ax,label='Earnings elasticity')
fig.text(.02,.02,'Same complete pairs in every cell. Point estimates; differences are not significance tests.',fontsize=9)
fig.tight_layout(rect=(0,.06,1,1));fig.savefig(FIG/'year-sensitivity.png',dpi=180);plt.close(fig)
print(est.to_string(index=False));print(json.dumps(summary,indent=2));print(pd.DataFrame(flow).to_string(index=False))

# Life-cycle check: identical people observed before age 30 and again eight years later.
life=pd.read_sql_query("""SELECT m.*, e.real_income AS early_income, e.age AS early_age,
                            later.age AS later_age
FROM matched_pairs m JOIN earnings e ON m.child=e.person AND e.year=2014
JOIN earnings later ON m.child=later.person AND later.year=2022
WHERE e.age BETWEEN 22 AND 29 AND e.real_income>0""",con)
assert len(life)>30
life=life.reset_index(drop=True)
lclusters=[g.index.to_numpy() for _,g in life.groupby('father')]
lboot=[]
for _ in range(1000):
 idx=np.concatenate([lclusters[i] for i in rng.integers(0,len(lclusters),len(lclusters))])
 b=life.iloc[idx]
 lboot.append([slope(b.father_mean,b.early_income),slope(b.father_mean,b.c2022)])
lboot=np.array(lboot)
ld=[]
for i,(year,col,agecol) in enumerate([(2014,'early_income','early_age'),(2022,'c2022','later_age')]):
 lo,hi=np.quantile(lboot[:,i],[.025,.975])
 ld.append({'year':year,'estimate':slope(life.father_mean,life[col]),'low':lo,'high':hi,
            'mean_interview_age':life[agecol].mean(),'pairs':len(life),
            'median_real_earnings':life[col].median()})
ld=pd.DataFrame(ld);ld.to_csv(OUT/'life_cycle.csv',index=False)
summary['life_pairs']=len(life)
summary['life_difference']=float(ld.estimate.iloc[1]-ld.estimate.iloc[0])
summary['life_difference_low']=float(np.quantile(lboot[:,1]-lboot[:,0],.025))
summary['life_difference_high']=float(np.quantile(lboot[:,1]-lboot[:,0],.975))
(OUT/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
fig,ax=plt.subplots(figsize=(8,4.8))
for i,r in ld.iterrows():
 ax.errorbar(r.estimate,i,xerr=[[r.estimate-r.low],[r.high-r.estimate]],fmt='o',color=colors[i],capsize=5,markersize=8)
 ax.annotate(f'{r.estimate:.2f}',(r.estimate,i),xytext=(0,13),textcoords='offset points',ha='center')
ax.set_yticks([0,1],[f"2014 earnings\nMean interview age {ld.mean_interview_age.iloc[0]:.1f}",f"2022 earnings\nMean interview age {ld.mean_interview_age.iloc[1]:.1f}"])
ax.set_ylim(-.5,1.5);ax.axvline(0,color='gray',lw=.8)
ax.set_xlabel('Elasticity relative to the same father three-year average')
ax.set_title('The same children at two career stages')
fig.text(.02,.02,f'{len(life)} identical pairs | 95% father-cluster bootstrap intervals | Age and calendar time both change',fontsize=9)
fig.tight_layout(rect=(0,.06,1,1));fig.savefig(FIG/'life-cycle.png',dpi=180);plt.close(fig)
print(ld.to_string(index=False));print(json.dumps(summary,indent=2))

# Insert calculated results into the article; no hand-copied numerical results.
values={**summary,'single':est.estimate.iloc[0],'multi':est.estimate.iloc[1],
 'early_age':ld.mean_interview_age.iloc[0],'later_age':ld.mean_interview_age.iloc[1],
 'early_ige':ld.estimate.iloc[0],'later_ige':ld.estimate.iloc[1],
 'early_income':ld.median_real_earnings.iloc[0],'later_income':ld.median_real_earnings.iloc[1],
 'life_low':summary['life_difference_low'],'life_high':summary['life_difference_high']}
article=(POST/'code/article-template.txt').read_text()
for key,value in values.items():
 if key in ['pairs','fathers','life_pairs']: value=f'{value:,}'
 elif key in ['early_income','later_income']: value=f'{value:,.0f}'
 elif key in ['early_age','later_age']: value=f'{value:.1f}'
 elif isinstance(value,(float,np.floating)):value=f'{value:.3f}'
 article=article.replace('@'+key+'@',str(value))
assert not re.search(r'@[a-z_]+@',article)
(POST/'index.qmd').write_text(article)
