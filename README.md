# Module Lizmap altitude

Module Lizmap d'ajout d'outils de requêtes sur les raster d'altitude stockés dans PostgreSQL

## Import DEM to PostGIS

We support you have already installed and configured PostgreSQL with PostGIS extension, and a spatial database.


```bash
createdb altitude
psql -d altitude -c "CREATE EXTENSION postgis"
```

You can then import your DEM into your database

```bash

# Go in dem folder
# Adapt for your context
cd altitude/install/data/

# only if needed - Transform DEM into your working projection in meters
gdalwarp -co "COMPRESS=DEFLATE" -s_srs EPSG:4326 -t_srs EPSG:3857 srtm_montpellier_4326.tif srtm_montpellier_3857.tif

# Create SQL file with raster2pgsql
raster2pgsql -d -s 3857  -C -I -r -M srtm_montpellier_3857.tif -F -Y -t 200x200 public.srtm_montpellier > import_srtm_montpellier.sql

# Import data to postgis database
psql -d altitude -f import_srtm_montpellier.sql

```

Then import some test linestring

```
# Go in dem folder
# Adapt for your context
cd altitude/install/data/

# Import data to database and transform it into working projection
ogr2ogr -overwrite -a_srs "EPSG:3857" -f PostgreSQL PG:"dbname=altitude" test_linestring_3857.geojson -nln test_linestring  -lco GEOMETRY_NAME=geom
```

Test some PostgreSQL raster queries

```sql
-- Drape 2D geom to DEM and get 3D length and compare it to 2D length
SELECT ST_Length(geom) AS longueur_2D, ST_3DLength(drape_linestring('public.srtm_montpellier', geom, 50)) AS longueur_3D
FROM public.test_linestring
LIMIT 1;


-- Calcul denivels
SELECT c.c_climb, c.c_dhill, c.c_deniv, c.c_pclimb_max, c.c_pdhill_max
FROM public.test_linestring,
calcul_denivele(
    'public.srtm_montpellier',
    drape_linestring('public.srtm_montpellier', geom, 50),
    50
) AS c
LIMIT 1;

-- Requête pour récupérer le profil 3D d'une ligne 3D pour réaliser ensuite un graphique
WITH
source AS (
    SELECT drape_linestring('public.srtm_montpellier', geom, 50) AS geom_3d
    FROM public.test_linestring
    LIMIT 1
),
points3d AS (
    SELECT
    (ST_DumpPoints(geom_3d)).geom AS geom,
    ST_StartPoint(geom_3d) AS origin
    FROM source
)
SELECT ST_distance(origin, geom) AS x, ST_Z(geom) AS y
FROM points3d;

```
