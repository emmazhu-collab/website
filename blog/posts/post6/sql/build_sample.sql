-- Keep current family members and assign only their own role's earnings.
CREATE TABLE earnings AS
SELECT p.person, p.wave - 1 AS year, p.age,
       (CASE WHEN p.role = 10 AND p.sequence = 1 THEN f.rp_income
             WHEN p.role IN (20,22) THEN f.spouse_income END) * c.factor AS real_income
FROM people AS p
INNER JOIN family_income AS f ON p.wave=f.wave AND p.family=f.family
INNER JOIN cpi AS c ON c.year=p.wave-1
WHERE p.sequence BETWEEN 1 AND 20 AND p.family>0;

CREATE TABLE father_means AS
SELECT person, AVG(real_income) AS father_mean, AVG(age) AS father_age,
       MAX(CASE WHEN year=2010 THEN real_income END) AS f2010,
       MAX(CASE WHEN year=2012 THEN real_income END) AS f2012,
       MAX(CASE WHEN year=2014 THEN real_income END) AS f2014
FROM earnings
WHERE year IN (2010,2012,2014) AND age BETWEEN 35 AND 60
  AND real_income>0
GROUP BY person HAVING COUNT(DISTINCT year)=3;

CREATE TABLE child_means AS
SELECT person, AVG(real_income) AS child_mean, AVG(age) AS child_age,
       MAX(CASE WHEN year=2018 THEN real_income END) AS c2018,
       MAX(CASE WHEN year=2020 THEN real_income END) AS c2020,
       MAX(CASE WHEN year=2022 THEN real_income END) AS c2022
FROM earnings
WHERE year IN (2018,2020,2022) AND age BETWEEN 30 AND 50
  AND real_income>0
GROUP BY person HAVING COUNT(DISTINCT year)=3;

CREATE TABLE matched_pairs AS
SELECT l.child, l.father, f.father_mean, c.child_mean,
       f.father_age,c.child_age,f.f2010,f.f2012,f.f2014,c.c2018,c.c2020,c.c2022
FROM parent_links AS l
INNER JOIN father_means AS f ON l.father=f.person
INNER JOIN child_means AS c ON l.child=c.person
WHERE l.child<>l.father;
