SELECT
    NULLIF(UPPER(REPLACE(sku, '_', '-')), '') as sku,
    NULLIF(TRIM(product_name), '') as product_name,
    CASE
    WHEN LOWER(TRIM(category)) = 'electronis' THEN 'electronics'
    ELSE LOWER(TRIM(category))
END as category,

    -- again trying to change the data type
    REPLACE(REGEXP_REPLACE(unit_price_czk, '[^0-9,.-]', '', 'g'), ',', '.') as unit_price_czk,

    -- again normalizing the
    CASE
    WHEN LOWER(TRIM(unit)) IN ('ks', 'piece', 'pieces') THEN 'pcs'
    ELSE LOWER(TRIM(unit))
END as unit


FROM
    {{source('warehouse' ,'raw_products')}}

UNION ALL
SELECT
    NULLIF(UPPER(REPLACE(sku, '_', '-')), '') as sku,
    NULLIF(TRIM(product_name), '') as product_name,
    CASE
    WHEN LOWER(TRIM(category)) = 'electronis' THEN 'electronics'
    ELSE LOWER(TRIM(category))
END as category,

    -- again trying to change the data type
    REPLACE(REGEXP_REPLACE(unit_price_czk, '[^0-9,.-]', '', 'g'), ',', '.') as unit_price_czk,

    -- again normalizing the
    CASE
    WHEN LOWER(TRIM(unit)) IN ('ks', 'piece', 'pieces') THEN 'pcs'
    ELSE LOWER(TRIM(unit))
END as unit


FROM
    {{source('warehouse' ,'raw_products_day2')}}