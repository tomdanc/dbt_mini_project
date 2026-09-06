SELECT
    TRIM(order_id) as order_id,
    TRIM(customer_id) as customer_id,

    -- this solves that  03/28/2024 — regex rewrites it to 2024-28-03 - this month is invalid, that is why we need the coalesce
    CAST(COALESCE(
        TRY_STRPTIME(REGEXP_REPLACE(order_date, '^(\d{1,2})[./-](\d{1,2})[./-](\d{4})$', '\3-\2-\1'), '%Y-%-m-%-d'),
        TRY_STRPTIME(TRIM(order_date), '%m/%d/%Y'),
        TRY_STRPTIME(TRIM(order_date), '%Y-%m-%dT%H:%M:%SZ')
    ) AS DATE) as order_date,

    -- here again condition
    CASE 
    WHEN LOWER(TRIM(status)) = 'canceled' THEN 'cancelled' -- spelling error
    ELSE LOWER(TRIM(status))
    END as status,

    NULLIF(UPPER(TRIM(currency)), '') as currency,
    -- again why try cast? because we need to change the datatype
    TRY_CAST(REPLACE(REGEXP_REPLACE(total_amount, '[^0-9,.-]', '', 'g'), ',', '.') AS DECIMAL(18,2)) as total_amount

FROM 
    {{source('warehouse' ,'raw_orders')}}