select
    o.order_id,
    c.customer_id,
    o.order_date,
    o.status,
    o.currency,
    o.total_amount

from {{ ref('L02_ORDERS') }} o
left join {{ ref('DIM_CUSTOMERS') }} c

    on o.customer_id = c.customer_id

