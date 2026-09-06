SELECT
    NULLIF(item_id, '') as item_id,
    NULLIF(order_id, '') as order_id,
    NULLIF(UPPER(REPLACE(sku, '_', '-')), '') as sku,
    TRY_CAST(REPLACE(quantity, ' ks', '') AS DECIMAL(18,2)) as quantity, -- case when 

    -- case when for all of this, and try cast because we need to change the data type (because its was still a string)
    TRY_CAST(REPLACE(REGEXP_REPLACE(unit_price, '[^0-9,.-]', '', 'g'), ',', '.') AS DECIMAL(18,2)) as unit_price,
    TRY_CAST(REPLACE(REGEXP_REPLACE(line_total, '[^0-9,.-]', '', 'g'), ',', '.') AS DECIMAL(18,2)) as line_total
FROM 

    {{source('warehouse' ,'raw_order_items')}}