
-- Fonction de calcul d'une ligne 3D à partir d'une ligne et d'un MNT
-- DROP FUNCTION IF EXISTS drape_linestring(geometry, integer);
-- DROP FUNCTION IF EXISTS drape_linestring(regclass, geometry, integer);
CREATE OR REPLACE FUNCTION public.drape_linestring(source_dem regclass, source_geom geometry, segment_size integer, OUT geom3d geometry)
RETURNS geometry AS
$$
DECLARE
    newgeom geometry;
    newgeom_wkt text;
BEGIN
    IF segment_size > 0 THEN
        newgeom = st_segmentize(ST_Force2D(source_geom), segment_size);
    ELSE
        newgeom = ST_Force2D(source_geom);
    END IF;
    newgeom_wkt:= ST_AsEWKT(newgeom);

    EXECUTE format('
    WITH points2d AS (
        SELECT ST_DumpPoints(ST_GeomFromEWKT(''%s'')) AS point2d
    )
    SELECT
        ST_MakeLine(
            ST_Translate(
                ST_Force3DZ((point2d).geom),
                0,
                0,
                ST_NearestValue(
                    rast,
                    (point2d).geom
                )
            )
            ORDER BY (point2d).path
        )
    FROM points2d
    LEFT JOIN %s ON ST_Intersects(rast, (point2d).geom)
    ', newgeom_wkt, source_dem)
    INTO geom3d
    ;

END;
$$ LANGUAGE plpgsql;


-- Calcul dénivelé
-- DROP FUNCTION IF EXISTS public.calcul_denivele(geometry, integer);
--DROP FUNCTION IF EXISTS public.calcul_denivele(regclass, geometry, integer);
CREATE OR REPLACE FUNCTION public.calcul_denivele(source_dem regclass, source_geom geometry, segment_size integer)
    RETURNS TABLE(c_climb double precision, c_dhill double precision, c_deniv double precision, c_pclimb_max double precision, c_pdhill_max double precision)
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE
    ROWS 1000
AS $BODY$
DECLARE
    source_geom_wkt text;
BEGIN
    source_geom_wkt:= ST_AsEWKT(source_geom);

    RETURN QUERY EXECUTE format('
    WITH
    segments AS (
        SELECT
        -- ordre
        (pt).path AS ordre,

        -- denivele
        ST_Z((pt).geom)
        - ST_Z(
            lag((pt).geom, 1, NULL) OVER (ORDER BY (pt).path)
        ) AS denivele,

        -- longueur du segment
        ST_Length(
            ST_MakeLine(
                (pt).geom,
                lag((pt).geom, 1, NULL) OVER (ORDER BY (pt).path)
            )
        ) AS longueur_segment

        FROM (
        -- decomposition de la ligne en segments de maximum segment_size
            SELECT ST_DumpPoints(geom) AS pt
            FROM (
                SELECT drape_linestring(%s, %s, %s) AS geom
            ) a
        ) as dumps
        ORDER BY ordre
    ), calcul AS (
        SELECT
        -- positif
        CASE
            WHEN denivele >=0 THEN denivele
            ELSE NULL
        END AS climb,
        CASE
            WHEN denivele >=0 AND longueur_segment > 0 THEN 100 * denivele / longueur_segment
            ELSE NULL
        END AS pclimb,

        -- negatif
        CASE
            WHEN denivele < 0 THEN denivele
            ELSE NULL
        END AS dhill,
        CASE
            WHEN denivele < 0 AND longueur_segment > 0 THEN 100 * abs(denivele) / longueur_segment
            ELSE NULL
        END AS pdhill,
        denivele
        FROM segments
        WHERE denivele IS NOT NULL
    )
    SELECT
    sum(climb) AS c_climb,
    sum(dhill) AS c_dhill,
    sum(denivele) AS c_deniv,
    max(pclimb) AS c_pclimb_max,
    max(pdhill) AS c_pdhill_max
    FROM calcul
    ', quote_literal(source_dem), quote_literal(source_geom_wkt), segment_size )
    ;

END;
$BODY$;


