"""Local-only same-age analysis. Only aggregate outputs; no record-level exports.
Run locally from either project with Python 3; use --raw-dir for another input path.
Importing this module does not access data. Do not run it through an AI tool.
"""
from pathlib import Path
from datetime import datetime, timezone
from collections import Counter
import argparse
import io
import json
import re
import uuid
import urllib.request
import zipfile
import xml.etree.ElementTree as ET
import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
SHARED_BLOG6_RAW = ROOT.parents[3] / 'blog6/data/raw'
DEFAULT_RAW = SHARED_BLOG6_RAW if SHARED_BLOG6_RAW.exists() else ROOT / 'data/raw'
# survey, Individual prefix, age field, family ID, RP earnings, spouse earnings
WAVES = [
 (1994,'ER331','ER33104','ER2002','ER4140','ER4144'),
 (1995,'ER332','ER33204','ER5002','ER6980','ER6984'),
 (1996,'ER333','ER33304','ER7002','ER9231','ER9235'),
 (1997,'ER334','ER33404','ER10002','ER12080','ER12082'),
 (1999,'ER335','ER33504','ER13002','ER16463','ER16465'),
 (2001,'ER336','ER33604','ER17002','ER20443','ER20447'),
 (2003,'ER337','ER33704','ER21002','ER24116','ER24135'),
 (2005,'ER338','ER33804','ER25002','ER27931','ER27943'),
 (2007,'ER339','ER33904','ER36002','ER40921','ER40933'),
 (2009,'ER340','ER34004','ER42002','ER46829','ER46841'),
 (2011,'ER341','ER34104','ER47302','ER52237','ER52249'),
 (2013,'ER342','ER34204','ER53002','ER58038','ER58050'),
 (2015,'ER343','ER34305','ER60002','ER65216','ER65244'),
 (2017,'ER345','ER34504','ER66002','ER71293','ER71321'),
 (2019,'ER347','ER34704','ER72002','ER77315','ER77343'),
 (2021,'ER349','ER34904','ER78002','ER81642','ER81670'),
 (2023,'ER351','ER35104','ER82002','ER85496','ER85524'),
]
# Actual positive ranges and explicit top codes from the two supplied codebooks.
# Top-coded amounts are excluded, not treated as exact earnings or missing codes.
RULES = {}
for wave, _, _, _, rp, sp in WAVES:
    for var in (rp, sp):
        RULES[var] = (1, 9999998 if wave <= 2009 else 9999997,
                      9999999 if 1999 <= wave <= 2009 else None)
RULES.update({'ER12080':(.01,999998.99,999999),
              'ER12082':(1,999998,None),
              'ER16465':(1,9999996,9999997)})
CPI_URL = ('https://fred.stlouisfed.org/graph/fredgraph.csv?'
           'id=CPIAUCNS&cosd=1993-01-01&coed=2022-12-31')


def fixed(stem, variables):
    layout = stem.with_suffix('.do').read_text()
    positions = {v:(int(a)-1,int(b)) for v,a,b in re.findall(
        r'\b((?:ER|PID)\d+)\s+(\d+)\s*-\s*(\d+)',layout.split('using')[0])}
    if not set(variables) <= positions.keys():
        raise ValueError('Required fields absent from fixed-width layout.')
    rows = []
    with stem.with_suffix('.txt').open() as source:
        for line in source:
            rows.append([int(line[positions[v][0]:positions[v][1]].strip() or 0)
                         for v in variables])
    return pd.DataFrame(rows,columns=variables)


def excel_columns(path, wanted):
    """Read selected named columns without depending on workbook column count."""
    ns = '{http://schemas.openxmlformats.org/spreadsheetml/2006/main}'
    with zipfile.ZipFile(path) as z:
        strings = [''.join(n.itertext()) for n in
                   ET.fromstring(z.read('xl/sharedStrings.xml'))]
        columns = None
        rows = []
        with z.open('xl/worksheets/sheet1.xml') as stream:
            for _, node in ET.iterparse(stream,events=('end',)):
                if node.tag != ns+'row':
                    continue
                cells = {}
                for cell in node:
                    letter = re.match('[A-Z]+',cell.attrib['r'])[0]
                    val = cell.find(ns+'v')
                    if val is not None:
                        cells[letter] = strings[int(val.text)] if cell.get('t') == 's' else val.text
                    elif cell.get('t') == 'inlineStr':
                        cells[letter] = ''.join(cell.itertext())
                if columns is None:
                    columns = {k:str(v).strip() for k,v in cells.items() if str(v).strip() in wanted}
                    if not columns:
                        raise ValueError('No expected column headers in income workbook.')
                else:
                    rows.append({name:cells.get(k) for k,name in columns.items()})
                node.clear()
    return pd.DataFrame(rows,columns=list(columns.values())).apply(pd.to_numeric,errors='raise')


def family_table(frames, fid, rp, sp, checks):
    """Union by family ID; compare overlapping values; never double-count extracts."""
    merged = None
    for frame in frames:
        if fid not in frame:
            continue
        part = frame[[c for c in (fid,rp,sp) if c in frame]].copy()
        part = part[part[fid].notna() & (part[fid]>0)].drop_duplicates()
        if part[fid].duplicated().any():
            raise ValueError('Conflicting duplicate family keys within an extract.')
        if (part[fid] % 1 != 0).any():
            raise ValueError('Noninteger family identifier.')
        part = part.set_index(fid)
        if merged is None:
            merged = part
        else:
            for col in merged.columns.intersection(part.columns):
                both = pd.concat([merged[col],part[col]],axis=1,join='inner').dropna()
                checks['overlapping_nonmissing_cells_checked'] += len(both)
                if (both.iloc[:,0] != both.iloc[:,1]).any():
                    raise ValueError('Overlapping extracts disagree. Resolve releases locally before proceeding.')
            merged = merged.combine_first(part)
    if merged is None or not {rp,sp} <= set(merged.columns):
        raise ValueError('Required wave or earnings columns missing.')
    return merged[[rp,sp]].rename(columns={rp:'rp',sp:'sp'}).rename_axis('family').reset_index()


def summarize_cpi(data):
    frame = pd.read_csv(io.BytesIO(data))
    dates = pd.to_datetime(frame.iloc[:,0],errors='raise')
    frame = pd.DataFrame({'year':dates.dt.year,'month':dates.dt.month,
                          'cpi':pd.to_numeric(frame['CPIAUCNS'],errors='coerce')})
    frame = frame[frame.year.between(1993,2022)]
    if frame.duplicated(['year','month']).any() or frame.cpi.isna().any() or (frame.cpi<=0).any():
        raise ValueError('CPI contains duplicate, missing, or nonpositive months.')
    annual = frame.groupby('year').cpi.agg(['mean','count'])
    if not set(range(1993,2023)) <= set(annual.index) or (annual['count']!=12).any():
        raise ValueError('CPI needs all 12 months in every year from 1993 through 2022.')
    return annual


def cpi_input(path):
    if path:
        data = Path(path).read_bytes()
        return summarize_cpi(data), data
    local = ROOT/'data/cpi_same_age.csv'
    if local.exists():
        data = local.read_bytes()
        try:
            return summarize_cpi(data), data
        except ValueError:
            # The saved file starts in 1994; fetch the extended public series.
            pass
    # Public CPI download only. No PSID values are sent in this request.
    with urllib.request.urlopen(CPI_URL,timeout=60) as response:
        data = response.read()
    return summarize_cpi(data), data


def select_ages(earnings):
    ordered = earnings[earnings.age.between(35,45)].copy()
    ordered['distance'] = abs(ordered.age-40)
    # Ties: younger interview age first, then earlier income year. No outcome-based choice.
    ordered = ordered.sort_values(['person','distance','age','year'])
    eligible = ordered.groupby('person').size()
    ordered = ordered[ordered.person.isin(eligible[eligible>=3].index)]
    chosen = ordered.groupby('person',sort=False).head(3).copy()
    chosen['rank'] = chosen.groupby('person',sort=False).cumcount()+1
    means = chosen.groupby('person').agg(mean_income=('real_income','mean'),
              mean_age=('age','mean'),min_year=('year','min'),max_year=('year','max'))
    first = chosen[chosen['rank']==1].set_index('person')[['real_income','age','year']]
    first.columns=['single_income','single_age','single_year']
    return chosen, means.join(first)


def build_sample(links, earnings, identified):
    """Build one age-matched sample from an in-memory earnings window."""
    if earnings.duplicated(['person','year']).any():
        raise ValueError('Duplicate person-income-year observations.')
    counts = earnings.groupby('person').size()
    in_window = earnings[earnings.age.between(35,45)].groupby('person').size()

    def eligible(person_counts, minimum):
        ids = person_counts[person_counts >= minimum].index
        return links[links.child.isin(ids) & links.father.isin(ids)].copy()

    one = eligible(counts, 1)
    three = eligible(counts, 3)
    window = eligible(in_window, 3)
    age_one = eligible(in_window, 1)
    chosen, measures = select_ages(earnings)
    matched = window.merge(measures.add_prefix('father_'), left_on='father',
                           right_index=True, validate='many_to_one')
    matched = matched.merge(measures.add_prefix('child_'), left_on='child',
                            right_index=True, validate='many_to_one')
    matched['single_gap'] = abs(matched.father_single_age - matched.child_single_age)
    matched['mean_gap'] = abs(matched.father_mean_age - matched.child_mean_age)
    final = matched[matched.single_gap.le(2) & matched.mean_gap.le(2)].copy()
    stages = [
        ('valid_identified_links', identified, None),
        ('both_in_individual_file', len(links), links),
        ('both_at_least_one_positive_year_any_valid_age', len(one), one),
        ('both_at_least_three_positive_years_any_valid_age', len(three), three),
        ('both_at_least_three_years_ages_35_45', len(window), window),
        ('single_age_gap_at_most_2', int(matched.single_gap.le(2).sum()),
         matched[matched.single_gap.le(2)]),
        ('mean_age_gap_at_most_2_separate_check', int(matched.mean_gap.le(2).sum()),
         matched[matched.mean_gap.le(2)]),
        ('both_age_gaps_at_most_2_final', len(final), final),
    ]
    flow = pd.DataFrame([
        {'stage': label, 'pairs': count,
         'unique_fathers': None if frame is None else frame.father.nunique()}
        for label, count, frame in stages
    ])
    return final, chosen, flow, matched, window, one, three, age_one


def compare_samples(old_sample, new_sample, old_chosen, new_chosen, output):
    """Write overlap and changed-year counts only; never export person IDs."""
    old_pairs = set(zip(old_sample.child, old_sample.father))
    new_pairs = set(zip(new_sample.child, new_sample.father))
    shared = old_pairs & new_pairs
    overlap = pd.DataFrame([
        {'group': 'retained_in_both', 'pairs': len(shared),
         'unique_fathers': len({father for _, father in shared})},
        {'group': 'new_only', 'pairs': len(new_pairs - old_pairs),
         'unique_fathers': len({father for _, father in new_pairs - old_pairs})},
        {'group': 'old_only', 'pairs': len(old_pairs - new_pairs),
         'unique_fathers': len({father for _, father in old_pairs - new_pairs})},
    ])
    overlap.to_csv(output/'sample_overlap.csv', index=False)

    def year_map(frame):
        return {person: tuple(int(y) for y in group.sort_values('rank').year)
                for person, group in frame.groupby('person', sort=False)}

    old_years, new_years = year_map(old_chosen), year_map(new_chosen)
    change_counts = Counter()
    for child, father in shared:
        pair_single_changed = False
        pair_three_changed = False
        for generation, person in [('father', father), ('child', child)]:
            before, after = old_years[person], new_years[person]
            if before[0] != after[0]:
                change_counts[(generation, 'single_year_changed')] += 1
                pair_single_changed = True
            if tuple(sorted(before)) != tuple(sorted(after)):
                change_counts[(generation, 'three_year_set_changed')] += 1
                pair_three_changed = True
        if pair_single_changed:
            change_counts[('either_generation','single_year_changed')] += 1
        if pair_three_changed:
            change_counts[('either_generation','three_year_set_changed')] += 1
    pd.DataFrame([
        {'generation': generation, 'measure': measure, 'retained_pairs_changed': count}
        for (generation, measure), count in sorted(change_counts.items())
    ], columns=['generation','measure','retained_pairs_changed']).to_csv(
        output/'selected_year_changes.csv', index=False)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--raw-dir',type=Path,default=DEFAULT_RAW)
    parser.add_argument('--cpi-csv',type=Path,help='Optional local monthly CPIAUCNS, 1993–2022.')
    args = parser.parse_args()
    # No imports of analysis.py: it would execute the original analysis and overwrite results.
    annual, cpi_bytes = cpi_input(args.cpi_csv)
    variables = ['ER30001','ER30002']
    for _,prefix,age,*_ in WAVES:
        variables.extend([prefix+'01',prefix+'02',prefix+'03',age])
    people = fixed(args.raw_dir/'ind2023er/IND2023ER',variables)
    if people.duplicated(['ER30001','ER30002']).any():
        raise ValueError('Duplicate permanent individual keys.')
    if not (people.ER30001.gt(0)&people.ER30002.between(1,995)).all():
        raise ValueError('Invalid permanent individual identifiers.')
    people['person'] = people.ER30001*1000+people.ER30002
    pid = fixed(args.raw_dir/'pid23/PID23',['PID2','PID3','PID23','PID24'])
    valid = pid.PID2.gt(0)&pid.PID3.between(1,995)&pid.PID23.gt(0)&pid.PID24.between(1,995)
    links = pd.DataFrame({'child':pid.loc[valid,'PID2']*1000+pid.loc[valid,'PID3'],
                          'father':pid.loc[valid,'PID23']*1000+pid.loc[valid,'PID24']}).drop_duplicates()
    links = links[links.child!=links.father]
    if links.child.duplicated().any():
        raise ValueError('Conflicting birth-father links.')
    identified = len(links)
    links = links[links.child.isin(people.person)&links.father.isin(people.person)].copy()
    wanted = {v for w in WAVES for v in w[3:]}
    frames = [excel_columns(args.raw_dir/name,wanted) for name in ['J366581.xlsx','J366467.xlsx']]
    checks = Counter()
    diagnostics=[]; rows=[]
    relevant = set(links.child)|set(links.father)
    people = people[people.person.isin(relevant)]
    for wave,prefix,age,fid,rp,sp in WAVES:
        fam = family_table(frames,fid,rp,sp,checks)
        p = people[['person',prefix+'01',prefix+'02',prefix+'03',age]].copy()
        p.columns=['person','family','sequence','role','age']
        p = p.merge(fam,on='family',how='left',validate='many_to_one',indicator=True)
        status = pd.Series('valid',index=p.index)
        def exclude(mask,label):
            status.loc[mask & status.eq('valid')] = label
        exclude(~p.sequence.between(1,20)|p.family.le(0),'not_current_member_or_no_family_id')
        exclude(p['_merge'].ne('both'),'no_family_income_record')
        exclude(~p.age.between(1,120),'invalid_interview_age')
        is_rp = p.role.eq(10)&p.sequence.eq(1)
        is_sp = p.role.isin([20,22])
        exclude(~(is_rp|is_sp),'unsupported_household_role')
        p['nominal'] = np.where(is_rp,p.rp,np.where(is_sp,p.sp,np.nan))
        exclude(p.nominal.isna(),'missing_income')
        exclude(p.nominal.eq(0),'zero_or_inapplicable_income')
        for mask,var in [(is_rp,rp),(is_sp,sp)]:
            low,high,top = RULES[var]
            if top is not None:
                exclude(mask & p.nominal.eq(top),'topcoded_income_excluded')
            exclude(mask & ~p.nominal.between(low,high),'invalid_or_special_income_code')
        for reason,n in status.value_counts().items():
            diagnostics.append({'survey_year':wave,'income_year':wave-1,'reason':reason,'person_wave_rows':int(n)})
        good = p.loc[status.eq('valid'),['person','age','nominal']].copy()
        good['year'] = wave-1
        good['real_income'] = good.nominal*annual.loc[2022,'mean']/annual.loc[wave-1,'mean']
        rows.append(good)
    earnings = pd.concat(rows,ignore_index=True)
    final, chosen, flow, matched, window, one, three, age_one = build_sample(links, earnings, identified)
    old_final, old_chosen, *_ = build_sample(
        links, earnings[earnings.year.ge(1994)].copy(), identified)
    ages=[];years=[]
    for label,pairs in [('before_age_gap',matched),('after_age_gap',final)]:
        for generation in ['father','child']:
            for measure in ['single','mean']:
                agevals=pairs[generation+'_'+measure+'_age']
                ages.append({'sample':label,'generation':generation,'measure':measure,
                             'pairs':len(pairs),'mean_age':agevals.mean(),'min_age':agevals.min(),'max_age':agevals.max()})
            # Each father is weighted once per pair, consistent with the intended regression.
            records=pairs[[generation]].merge(chosen,left_on=generation,right_on='person',how='inner')
            for measure,sub in [('single',records[records['rank']==1]),('three_year',records)]:
                for year,n in sub.groupby('year').size().items():
                    years.append({'sample':label,'generation':generation,'measure':measure,
                                  'income_year':int(year),'pair_weighted_observations':int(n)})
    exclusions=[('missing_individual_record',identified-len(links)),
                ('no_positive_supported_income_for_one_or_both',len(links)-len(one)),
                ('fewer_than_three_years_for_one_or_both',len(one)-len(three)),
                ('fewer_than_three_years_in_age_window',len(three)-len(window)),
                ('fails_one_or_both_age_gap_rules',len(window)-len(final))]
    summary={'status':'same_age_analysis_completed','final_pairs':len(final),
             'final_unique_fathers':int(final.father.nunique()),
             'both_at_least_one_year_ages_35_45':len(age_one),
             'single_gap_mean_before':matched.single_gap.mean(),
             'mean_gap_mean_before':matched.mean_gap.mean(),
             'single_gap_mean_after':final.single_gap.mean(),
             'mean_gap_mean_after':final.mean_gap.mean(),
             'overlap_checks':dict(checks),
             'rules':{'target_interview_age':40,'age_window':[35,45],
                      'three_distinct_income_years':True,'max_gap_both_measures':2,
                      'tie_break':'distance to 40, younger interview age, earlier income year',
                      'topcodes':'exclude and count separately; not imputed',
                      'scope':'unweighted selected positive earners; no national inference'}}
    # A unique new directory prevents overwriting any previous audit or analysis output.
    output=ROOT/'results_same_age'/('same_age_'+datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')+'_'+uuid.uuid4().hex[:8])
    output.mkdir(parents=True,exist_ok=False)
    compare_samples(old_final, final, old_chosen, chosen, output)
    flow.to_csv(output/'sample_flow.csv',index=False)
    pd.DataFrame(exclusions,columns=['reason','pairs_excluded']).to_csv(output/'pair_exclusions.csv',index=False)
    pd.DataFrame(diagnostics).to_csv(output/'record_exclusions.csv',index=False)
    pd.DataFrame(ages).to_csv(output/'measurement_ages.csv',index=False)
    pd.DataFrame(years,columns=['sample','generation','measure','income_year','pair_weighted_observations']).to_csv(output/'income_years.csv',index=False)
    # pandas serializes empty-sample NaN values as JSON null.
    (output/'summary.json').write_text(pd.Series(summary).to_json(indent=2)+'\n')
    # Public CPI is not PSID microdata; save the exact audit input for reproducibility.
    (output/'cpi_public_input.csv').write_bytes(cpi_bytes)
    (output/'README.txt').write_text('Aggregate sample audit and IGE analysis. A local comparison of the 1994+ and 1993+ income windows writes only pair counts and selected-year change counts; no personal IDs or earnings records are saved.\n'
        'Age is interview age, approximately one year after earnings. Both single and mean age gaps must be <=2.\n'
        'The separate mean-gap row is not a sequential funnel stage. Income-year counts weight fathers once per child.\n'
        'Record exclusions are mutually exclusive in processing order, for linked people only; they are not pair counts.\n'
        'No automatic sample-size threshold approves an IGE analysis. Review father clusters, ages, coverage and exclusions.\n'
        'Public CPI source: '+CPI_URL+'\n')
    print(flow.to_string(index=False))
    print('\nAggregate output folder:',output)
    return final, chosen, earnings, output


def life_cycle_check(sample, chosen, earnings, output):
    """Compare early- and later-career child earnings on one main-sample subset."""
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt

    early = earnings[earnings.age.between(22,29)].copy()
    early['distance'] = abs(early.age - 25)
    early = (early.sort_values(['person','distance','age','year'])
             .groupby('person',sort=False).head(1)
             .rename(columns={'real_income':'early_income','age':'early_age','year':'early_year'}))
    later = (chosen[chosen['rank'].eq(1)][['person','real_income','age','year']]
             .rename(columns={'real_income':'later_income','age':'later_age','year':'later_year'}))
    father_mean = (chosen.groupby('person',as_index=False).real_income.mean()
                   .rename(columns={'person':'father','real_income':'father_mean'}))
    pairs = (sample[['child','father']].merge(father_mean,on='father',validate='many_to_one')
             .merge(early[['person','early_income','early_age','early_year']],
                    left_on='child',right_on='person',how='inner',validate='many_to_one')
             .merge(later[['person','later_income','later_age','later_year']],
                    left_on='child',right_on='person',how='inner',validate='many_to_one',
                    suffixes=('_early','_later')))
    n_fathers = pairs.father.nunique()
    summary = {
        'status': 'estimated' if len(pairs) >= 3 and n_fathers >= 3 else 'too_few_pairs_to_estimate',
        'pairs': int(len(pairs)), 'unique_fathers': int(n_fathers),
        'early_age_window': [22,29], 'early_target_age': 25,
        'later_age_window': [35,45], 'later_target_age': 40,
        'same_pairs_for_both_age_stages': True,
        'father_measure': 'mean of the three selected positive real-earnings observations near age 40',
        'interpretation': 'descriptive age-stage comparison; age and calendar year both change; not causal'
    }
    (output/'life_cycle_summary.json').write_text(json.dumps(summary,indent=2)+'\n')
    if len(pairs) < 3 or n_fathers < 3:
        pd.DataFrame(columns=['stage','generation','mean_age','min_age','max_age']).to_csv(
            output/'life_cycle_measurement.csv',index=False)
        return

    father_ages = chosen.groupby('person').age.mean()
    selected_father_ages = pairs.father.map(father_ages)
    ages = pd.DataFrame([
        {'stage':'early','generation':'child','mean_age':pairs.early_age.mean(),
         'min_age':pairs.early_age.min(),'max_age':pairs.early_age.max()},
        {'stage':'later','generation':'child','mean_age':pairs.later_age.mean(),
         'min_age':pairs.later_age.min(),'max_age':pairs.later_age.max()},
        {'stage':'both','generation':'father','mean_age':selected_father_ages.mean(),
         'min_age':selected_father_ages.min(),'max_age':selected_father_ages.max()},
    ])
    ages.to_csv(output/'life_cycle_measurement.csv',index=False)
    year_counts = pd.concat([
        pairs.early_year.value_counts().rename_axis('income_year').reset_index(name='pairs').assign(stage='early'),
        pairs.later_year.value_counts().rename_axis('income_year').reset_index(name='pairs').assign(stage='later')
    ],ignore_index=True)
    year_counts.to_csv(output/'life_cycle_income_years.csv',index=False)

    def slope(frame, child_field):
        x = np.log(frame.father_mean.to_numpy())
        y = np.log(frame[child_field].to_numpy())
        X = np.column_stack([np.ones(len(x)),x])
        if len(frame) <= 2 or np.linalg.matrix_rank(X) < X.shape[1]:
            return np.nan
        return float(np.linalg.lstsq(X,y,rcond=None)[0][1])

    estimates = [slope(pairs,'early_income'),slope(pairs,'later_income')]
    clusters = [g.index.to_numpy() for _,g in pairs.groupby('father')]
    rng = np.random.default_rng(6401)
    boot = np.empty((2000,2))
    for i in range(2000):
        ids = np.concatenate([clusters[j] for j in rng.integers(0,len(clusters),len(clusters))])
        draw = pairs.iloc[ids]
        boot[i] = [slope(draw,'early_income'),slope(draw,'later_income')]

    def interval(values):
        valid = values[np.isfinite(values)]
        if len(valid) < 1980:
            return np.nan,np.nan,len(valid)
        low,high = np.quantile(valid,[.025,.975])
        return float(low),float(high),len(valid)

    rows=[]
    for label,value,draws in [('early',estimates[0],boot[:,0]),('later',estimates[1],boot[:,1])]:
        low,high,valid=interval(draws)
        rows.append({'stage':label,'estimate':value,'low':low,'high':high,
                     'valid_bootstrap_draws':valid,'pairs':len(pairs),'fathers':n_fathers})
    pd.DataFrame(rows).to_csv(output/'life_cycle_estimates.csv',index=False)
    low,high,valid=interval(boot[:,1]-boot[:,0])
    pd.DataFrame([{'comparison':'later_minus_early','estimate':estimates[1]-estimates[0],
                   'low':low,'high':high,'valid_bootstrap_draws':valid,
                   'pairs':len(pairs),'fathers':n_fathers}]).to_csv(
                       output/'life_cycle_difference.csv',index=False)
    fig,ax=plt.subplots(figsize=(8,4))
    for i,row in enumerate(rows):
        if np.isfinite(row['low']) and np.isfinite(row['high']):
            ax.hlines(i,row['low'],row['high'],color='#286789',linewidth=2)
        ax.plot(row['estimate'],i,'o',color='#286789')
    ax.set_yticks([0,1],['Early career: ages 22–29','Later: ages 35–45'])
    ax.axvline(0,color='gray',linewidth=.8)
    ax.set_xlabel('IGE using the same fathers and children')
    ax.set_title('Does the estimate change across career stages?')
    fig.text(.02,.01,f'{len(pairs)} pairs; {n_fathers} fathers | 95% father-cluster bootstrap intervals',fontsize=9)
    fig.tight_layout(rect=(0,.06,1,1))
    fig.savefig(output/'figures/life-cycle-sameage-sample.png',dpi=180)
    plt.close(fig)


def estimate_and_plot(sample, chosen, earnings, output):
    import sqlite3
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt

    # SQL rebuilds the actual income summaries and links used for estimation.
    # Personal tables exist in RAM only and are never exported.
    with sqlite3.connect(':memory:') as con:
        chosen.to_sql('selected_earnings',con,index=False)
        sample[['child','father']].to_sql('eligible_links',con,index=False)
        query = (ROOT/'sql/same_age_sample.sql').read_text()
        pairs = pd.read_sql_query(query,con).sort_values(['father','child']).reset_index(drop=True)
    if len(pairs)!=len(sample) or pairs.child.duplicated().any():
        raise ValueError('SQL sample does not match the audited sample.')
    for generation in ['father','child']:
        for field in ['single_income','mean_income','single_age','mean_age']:
            col=generation+'_'+field
            if not np.allclose(pairs.set_index('child')[col].sort_index(),
                               sample.set_index('child')[col].sort_index()):
                raise ValueError('SQL summaries disagree with audit summaries.')
    if len(pairs)<3 or pairs.father.nunique()<3:
        raise ValueError('Insufficient independent fathers for estimation; review audit outputs.')

    def fit(frame,measure,adjusted=False):
        x=np.log(frame['father_'+measure+'_income'].to_numpy())
        y=np.log(frame['child_'+measure+'_income'].to_numpy())
        columns=[np.ones(len(x)),x]
        if adjusted:
            columns.extend([frame['father_'+measure+'_age'].to_numpy()-40,
                            frame['child_'+measure+'_age'].to_numpy()-40])
        X=np.column_stack(columns)
        if len(x)<=X.shape[1] or np.linalg.matrix_rank(X)<X.shape[1]:
            return np.nan
        return float(np.linalg.lstsq(X,y,rcond=None)[0][1])

    specifications=[('single',False),('mean',False),('single',True),('mean',True)]
    estimates=np.array([fit(pairs,m,a) for m,a in specifications])
    if not np.isfinite(estimates[:2]).all():
        raise ValueError('Main models lack sufficient log-earnings variation.')
    clusters=[g.index.to_numpy() for _,g in pairs.groupby('father')]
    rng=np.random.default_rng(6400); reps=2000
    boot=np.empty((reps,4))
    for i in range(reps):
        ids=np.concatenate([clusters[j] for j in rng.integers(0,len(clusters),len(clusters))])
        draw=pairs.iloc[ids]
        boot[i]=[fit(draw,m,a) for m,a in specifications]
    def interval(values):
        valid=values[np.isfinite(values)]
        # Do not silently discard a material number of singular bootstrap draws.
        if len(valid)<.99*reps:return np.nan,np.nan,len(valid)
        low,high=np.quantile(valid,[.025,.975])
        return float(low),float(high),len(valid)
    records=[]
    for j,(measure,adjusted) in enumerate(specifications):
        lo,hi,n=interval(boot[:,j])
        records.append(dict(measure=measure,age_controls=adjusted,estimate=estimates[j],
                            low=lo,high=hi,valid_bootstrap_draws=n,pairs=len(pairs),fathers=len(clusters)))
    pd.DataFrame(records).to_csv(output/'ige_estimates.csv',index=False)
    differences=[]
    for label,a,b in [('mean_minus_single',1,0),('adjusted_mean_minus_single',3,2),
                      ('age_control_change_single',2,0),('age_control_change_mean',3,1)]:
        lo,hi,n=interval(boot[:,a]-boot[:,b])
        differences.append(dict(comparison=label,estimate=estimates[a]-estimates[b],low=lo,high=hi,
                                valid_bootstrap_draws=n))
    pd.DataFrame(differences).to_csv(output/'ige_differences.csv',index=False)
    info={'pairs':len(pairs),'unique_fathers':len(clusters),'bootstrap_replications':reps,'seed':6400,
          'bootstrap_unit':'father; paired draws across all specifications',
          'age_controls':'linear father and child measurement ages centered at 40; sensitivity only',
          'selection':'same sample for single and three-year average',
          'interpretation':'unweighted association; age matching and controls do not eliminate life-cycle or cohort bias',
          'main_intervals_available':all(np.isfinite([r['low'],r['high']]).all() for r in records[:2])}
    (output/'analysis_summary.json').write_text(json.dumps(info,indent=2)+'\n')
    # Only aggregated estimates and mean ages are plotted, never individual earnings.
    figdir=output/'figures';figdir.mkdir()
    if info['main_intervals_available']:
        fig,ax=plt.subplots(figsize=(8,4))
        for i,r in enumerate(records[:2]):
            ax.hlines(i,r['low'],r['high'],color='#286789',linewidth=2)
            ax.plot(r['estimate'],i,'o',color='#286789')
        ax.set_yticks([0,1],['Single year','Three-year average'])
        ax.axvline(0,color='gray',linewidth=.8)
        ax.set_xlabel('Intergenerational earnings elasticity')
        ax.set_title('Does averaging change the earnings link at similar ages?')
        fig.text(.02,.01,f'{len(pairs)} pairs; {len(clusters)} fathers | 95% father-cluster bootstrap intervals',fontsize=9)
        fig.tight_layout(rect=(0,.06,1,1));fig.savefig(figdir/'same-age-ige.png',dpi=180);plt.close(fig)
    ages=[]
    for m in ['single','mean']:
        for g in ['father','child']:
            vals=pairs[g+'_'+m+'_age']
            ages.append(dict(measure=m,generation=g,mean_age=vals.mean(),minimum_age=vals.min(),maximum_age=vals.max()))
    pd.DataFrame(ages).to_csv(output/'selected_age_summary.csv',index=False)
    fig,ax=plt.subplots(figsize=(8,4))
    for i,m in enumerate(['single','mean']):
        for g,offset,color in [('father',-.12,'#286789'),('child',.12,'#c27636')]:
            ax.scatter(pairs[g+'_'+m+'_age'].mean(),i+offset,color=color,label=g.title() if i==0 else None)
    ax.set_yticks([0,1],['Single year','Three-year average'])
    ax.set_xlim(35,45);ax.axvline(40,color='gray',linestyle='--',linewidth=.8)
    ax.set_xlabel('Mean selected interview age');ax.set_title('Are fathers and children measured at similar ages?')
    ax.legend();fig.text(.02,.01,'Pair-weighted means, not distributions | Both within-pair age gaps are at most two years',fontsize=9)
    fig.tight_layout(rect=(0,.06,1,1));fig.savefig(figdir/'same-age-measurement.png',dpi=180);plt.close(fig)
    print(pd.DataFrame(records).to_string(index=False))
    print(pd.DataFrame(differences).to_string(index=False))
    life_cycle_check(pairs, chosen, earnings, output)
    print('New aggregate analysis saved to:',output)


if __name__ == '__main__':
    matched, selected, earnings, destination = main()
    estimate_and_plot(matched, selected, earnings, destination)
