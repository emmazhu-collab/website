WITH summaries AS (
 SELECT person, AVG(real_income) AS mean_income, AVG(age) AS mean_age,
        MAX(CASE WHEN rank=1 THEN real_income END) AS single_income,
        MAX(CASE WHEN rank=1 THEN age END) AS single_age
 FROM selected_earnings
 WHERE age BETWEEN 35 AND 45 AND real_income>0
 GROUP BY person
 HAVING COUNT(*)=3 AND COUNT(DISTINCT year)=3
)
SELECT l.child,l.father,
       f.mean_income AS father_mean_income,c.mean_income AS child_mean_income,
       f.single_income AS father_single_income,c.single_income AS child_single_income,
       f.mean_age AS father_mean_age,c.mean_age AS child_mean_age,
       f.single_age AS father_single_age,c.single_age AS child_single_age
FROM eligible_links l
JOIN summaries f ON l.father=f.person
JOIN summaries c ON l.child=c.person
WHERE l.child<>l.father
  AND ABS(f.single_age-c.single_age)<=2
  AND ABS(f.mean_age-c.mean_age)<=2;
